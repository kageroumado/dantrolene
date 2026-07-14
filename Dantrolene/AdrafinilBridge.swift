import Foundation
import os

#if !APPSTORE

/// Blocks lid-close sleep through the Adrafinil CLI while Dantrolene is active on the home network.
///
/// Adrafinil is a separate app whose privileged helper keeps a MacBook awake with the lid closed.
/// Its CLI exposes reference-counted holds keyed per client: Dantrolene places holds under its own
/// `Dantrolene:` keys and releases exactly those keys, leaving holds from agents untouched.
///
/// Two daemon-side reapers shape the hold lifecycle:
/// - Every hold here carries a TTL of three renewal intervals, so a crashed or force-quit
///   Dantrolene can never pin the Mac awake for long — and up to two consecutive renewals
///   can be missed before the hold lapses.
/// - The daemon's max-age backstop releases any assertion ~24h after it was *first* acquired,
///   and re-acquiring the same key does not reset that clock. Renewal therefore rotates keys:
///   acquire a fresh key first, then release the previous one, so blocking never gaps and no
///   single key lives long enough to be reaped.
///
/// The daemon is the source of truth and this process can die at any moment, so consistency is
/// eventual by design: `outstandingKeys` tracks every key that may still be registered
/// daemon-side, the synchronous teardown releases them all, and anything that still slips
/// through (a subprocess in flight at teardown) expires via its TTL.
@Observable
final class AdrafinilBridge {
    private(set) var isInstalled = false
    /// Intent: Dantrolene wants a hold and the renewal timer is running.
    private(set) var isBlockingSleep = false
    /// Whether the most recent acquire is believed to have landed. Optimistically true while an
    /// acquire is in flight (so the UI doesn't flash a failure on every renewal), flipped false
    /// when the CLI reports a soft failure such as "daemon not running". Renewals keep retrying,
    /// so this self-heals once the daemon is back.
    private(set) var isHoldConfirmed = false

    private enum Constants {
        static let toolName = "Dantrolene"
        static let renewalInterval: TimeInterval = 10 * 60
        static let renewalTolerance: TimeInterval = 60
        static let holdTTL: TimeInterval = 30 * 60
        /// Where the Adrafinil installer symlinks its CLI (`AdrafinilConstants.cliInstallPath`
        /// and its no-admin fallback). Checked before $PATH because GUI apps inherit a minimal
        /// PATH that omits /usr/local/bin.
        static let installPaths = [
            "/usr/local/bin/adrafinil",
            "\(NSHomeDirectory())/.local/bin/adrafinil",
        ]
    }

    private static let log = Logger(subsystem: "glass.kagerou.dantrolene", category: "AdrafinilBridge")

    @ObservationIgnored private var cliPath: String?
    @ObservationIgnored private var currentHoldKey: String?
    /// Keys that may still be registered daemon-side: inserted when an acquire is enqueued,
    /// removed once the matching release has actually run. The synchronous teardown releases
    /// them all, so an in-flight renewal can't leak its predecessor.
    @ObservationIgnored private var outstandingKeys: Set<String> = []
    /// Bumped by every teardown. Queued acquires capture the generation at enqueue time and
    /// no-op when stale, so a draining queue can't re-place a hold that a synchronous teardown
    /// already released.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var renewalTimer: Timer?
    @ObservationIgnored private var holdReason = ""
    /// Serializes CLI invocations so an acquire/release pair can never be reordered
    /// around a later renewal or release.
    @ObservationIgnored private var pendingOperations: Task<Void, Never>?
    /// Held while blocking so App Nap can't defer the renewal timer past the hold's TTL.
    @ObservationIgnored private var appNapActivity: (any NSObjectProtocol)?

    init() {
        refreshInstallation()
    }

    /// Re-detects the CLI. Cheap (a handful of stat calls) — safe to call every time the
    /// popover opens so an install/uninstall of Adrafinil is picked up without relaunching.
    func refreshInstallation() {
        cliPath = Self.locateCLI()
        isInstalled = cliPath != nil
        if !isInstalled, isBlockingSleep {
            // Adrafinil was removed from under us; nothing left to release against.
            // Its daemon (if still running) expires the holds via TTL.
            stopRenewal()
            generation += 1
            outstandingKeys.removeAll()
            currentHoldKey = nil
            isBlockingSleep = false
            isHoldConfirmed = false
        }
    }

    /// Places a lid-close sleep hold and keeps it renewed until `stopBlocking()`.
    /// Idempotent while already blocking.
    func startBlocking(reason: String) {
        guard cliPath != nil, !isBlockingSleep else { return }
        isBlockingSleep = true
        isHoldConfirmed = true
        holdReason = reason
        let key = Self.mintKey()
        Self.log.notice("Blocking lid-close sleep via Adrafinil (key \(key, privacy: .public))")
        enqueueAcquire(key: key)
        startRenewalTimer()
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: .background, reason: "Renewing Adrafinil sleep hold"
        )
    }

    /// Releases Dantrolene's own holds (never anyone else's). Idempotent while not blocking.
    func stopBlocking() {
        guard isBlockingSleep else { return }
        isBlockingSleep = false
        isHoldConfirmed = false
        stopRenewal()
        generation += 1
        currentHoldKey = nil
        // Snapshot now: a later startBlocking may enqueue a fresh acquire behind this release
        // op, and that new key must not be swept up with the old ones.
        let keys = outstandingKeys
        guard !keys.isEmpty else { return }
        Self.log.notice("Releasing Adrafinil sleep hold\(keys.count == 1 ? "" : "s") (\(keys.joined(separator: ", "), privacy: .public))")
        enqueue { [self] in
            for key in keys {
                await runCLI(releaseArguments(key: key))
                outstandingKeys.remove(key)
            }
        }
    }

    /// Synchronous best-effort release of every possibly-live hold, for the willSleep and
    /// willTerminate paths where the queued async release might never get to run. Double
    /// releases are harmless daemon-side warnings; a hold that still slips through (an acquire
    /// subprocess in flight right now) expires via its TTL.
    func releaseSynchronously() {
        stopRenewal()
        isBlockingSleep = false
        isHoldConfirmed = false
        generation += 1
        currentHoldKey = nil
        guard let cliPath else {
            outstandingKeys.removeAll()
            return
        }
        for key in outstandingKeys {
            let process = Self.makeProcess(at: cliPath, arguments: releaseArguments(key: key))
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
        outstandingKeys.removeAll()
    }

    // MARK: - Renewal

    private func startRenewalTimer() {
        renewalTimer?.invalidate()
        let timer = Timer(timeInterval: Constants.renewalInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renew()
            }
        }
        timer.tolerance = Constants.renewalTolerance
        // .common, not .default: a tracking run loop (open menu, live resize) suppresses
        // default-mode timers, and a long-lived one could outlast the hold's TTL.
        RunLoop.main.add(timer, forMode: .common)
        renewalTimer = timer
    }

    private func stopRenewal() {
        renewalTimer?.invalidate()
        renewalTimer = nil
        if let appNapActivity {
            ProcessInfo.processInfo.endActivity(appNapActivity)
            self.appNapActivity = nil
        }
    }

    private func renew() {
        guard isBlockingSleep, cliPath != nil, let previousKey = currentHoldKey else { return }
        enqueueAcquire(key: Self.mintKey(), releasingAfterward: previousKey)
    }

    // MARK: - CLI plumbing

    /// Enqueues an acquire of `key` (and, for renewals, the release of the key it replaces).
    /// The release runs after the fresh acquire so blocking never gaps mid-rotation.
    private func enqueueAcquire(key: String, releasingAfterward previousKey: String? = nil) {
        currentHoldKey = key
        outstandingKeys.insert(key)
        let expectedGeneration = generation
        enqueue { [self] in
            guard expectedGeneration == generation else {
                // A teardown ran while this was queued and released everything, including
                // `previousKey`; acquiring now would orphan the hold until its TTL.
                outstandingKeys.remove(key)
                return
            }
            let landed = await runCLI(acquireArguments(key: key))
            if currentHoldKey == key {
                isHoldConfirmed = landed
            }
            if let previousKey {
                await runCLI(releaseArguments(key: previousKey))
                outstandingKeys.remove(previousKey)
            }
        }
    }

    private func acquireArguments(key: String) -> [String] {
        [
            "acquire", key,
            "--tool", Constants.toolName,
            "--reason", holdReason,
            "--ttl", String(Int(Constants.holdTTL)),
        ]
    }

    private func releaseArguments(key: String) -> [String] {
        ["release", key, "--tool", Constants.toolName]
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = pendingOperations
        pendingOperations = Task {
            await previous?.value
            await operation()
        }
    }

    /// Runs the CLI and returns whether the invocation landed: launched, exited zero, and
    /// stayed silent on stderr. The last check matters because the CLI fails soft — exit 0
    /// with a warning like "daemon not running" — so silence is the only success signal.
    @discardableResult
    private func runCLI(_ arguments: [String]) async -> Bool {
        guard let cliPath else { return false }
        let process = Self.makeProcess(at: cliPath, arguments: arguments)
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        // Drain stderr concurrently with the wait for exit: a post-exit read would deadlock
        // the whole operation chain if the child ever filled the pipe buffer.
        let stderrTask = Task { () -> Data in
            var data = Data()
            do {
                for try await byte in stderrPipe.fileHandleForReading.bytes {
                    data.append(byte)
                }
            } catch {}
            return data
        }

        let launched = await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume(returning: true) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                Self.log.error("Failed to launch adrafinil: \(error.localizedDescription)")
                continuation.resume(returning: false)
            }
        }
        if !launched {
            // No child ever held the write end; close ours so the drain task sees EOF.
            try? stderrPipe.fileHandleForWriting.close()
        }

        let stderrData = await stderrTask.value
        let message = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !message.isEmpty {
            Self.log.warning("adrafinil \(arguments.first ?? "", privacy: .public): \(message, privacy: .public)")
        }
        return launched && process.terminationStatus == 0 && message.isEmpty
    }

    private static func makeProcess(at path: String, arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        // The CLI polls stdin for a hook payload before falling back to the positional key;
        // the null device reads as immediate EOF.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        return process
    }

    private static func locateCLI() -> String? {
        var candidates = Constants.installPaths
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/adrafinil" }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The daemon key becomes `Dantrolene:home-<hex>` (`--tool` + positional). A fresh suffix
    /// per acquire is what makes key rotation defeat the max-age backstop.
    private static func mintKey() -> String {
        "home-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    }
}

#else

/// App Store builds are sandboxed: they can neither spawn the Adrafinil CLI nor reach its
/// daemon socket, so the integration is compiled out. This inert stand-in keeps the manager
/// and popover code identical across both builds — `isInstalled` staying false hides the
/// lid-close sleep section entirely.
@Observable
final class AdrafinilBridge {
    let isInstalled = false
    let isBlockingSleep = false
    let isHoldConfirmed = false

    func refreshInstallation() {}
    func startBlocking(reason: String) {}
    func stopBlocking() {}
    func releaseSynchronously() {}
}

#endif

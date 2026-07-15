import AppKit
import CoreGraphics
import Foundation
import os

/// The idle → dim → off → restore state machine behind both editions' "the display sleeps but
/// never locks" illusion. It owns the timeouts, the poll loop, idle measurement, display-topology
/// observation, and the external-assertion policy; *how* a screen is darkened and restored is the
/// only thing that differs between editions, injected as `DisplaySleepEffects`:
///
/// - the direct edition lowers the real backlight (private `DisplayServices` + keyboard backlight),
/// - the sandboxed App Store edition covers each screen with a black borderless window.
///
/// Previously these were two near-identical files that had already drifted (wake-settle guards and
/// display-usability logic in one, the public idle query in the other). Unifying them means the
/// state-machine bugs are fixed once, on this type, rather than twice.
final class DisplaySleepStateMachine {
    enum State {
        case idle
        case active
        case dimmed
        case off
    }

    private(set) var state: State = .idle

    private let effects: any DisplaySleepEffects
    private var pollTask: Task<Void, Never>?
    private var topologyObserver: (any NSObjectProtocol)?

    private var dimTimeout: TimeInterval = 570
    private var offTimeout: TimeInterval = 600

    private nonisolated static let log = Logger(
        subsystem: "glass.kagerou.dantrolene", category: "DisplaySleep",
    )

    init() {
        #if APPSTORE
            effects = OverlayEffects()
        #else
            effects = BrightnessEffects()
        #endif
    }

    // MARK: - Public

    func start(mode: DisplaySleepMode) {
        guard state == .idle else { return }
        guard effects.begin() else {
            Self.log.error("Effects unavailable — not starting")
            return
        }
        applyMode(mode)
        state = .active
        startObservingTopology()
        startPolling()
        Self.log.notice(
            "Started (dim at \(self.dimTimeout, format: .fixed(precision: 0))s, off at \(self.offTimeout, format: .fixed(precision: 0))s)",
        )
    }

    func stop() {
        guard state != .idle else { return }
        pollTask?.cancel()
        pollTask = nil
        stopObservingTopology()
        if state == .dimmed || state == .off {
            effects.restore()
        }
        effects.end()
        state = .idle
        Self.log.notice("Stopped")
    }

    func updateTimeout(_ mode: DisplaySleepMode) {
        guard state != .idle else { return }
        applyMode(mode)
        Self.log.info(
            "Updated timeouts (dim at \(self.dimTimeout, format: .fixed(precision: 0))s, off at \(self.offTimeout, format: .fixed(precision: 0))s)",
        )
    }

    // MARK: - Timeout configuration

    private func applyMode(_ mode: DisplaySleepMode) {
        switch mode {
        case .matchSystem:
            switch DisplayPowerInfo.systemDisplaySleep() {
            case .never:
                // The user set the system display sleep to Never — honor it: never dim or off.
                dimTimeout = .infinity
                offTimeout = .infinity
            case let .minutes(minutes):
                setTimeouts(totalSeconds: TimeInterval(minutes * 60))
            case .unknown:
                // Couldn't read the setting; leave the current timeouts rather than guessing.
                break
            }
        case let .custom(minutes):
            setTimeouts(totalSeconds: TimeInterval(minutes * 60))
        }
    }

    private func setTimeouts(totalSeconds: TimeInterval) {
        offTimeout = totalSeconds
        dimTimeout = max(totalSeconds - 30, totalSeconds * 0.75)
    }

    // MARK: - Idle measurement

    /// Seconds since the last hardware input event. `kCGAnyInputEventType` has no Swift spelling,
    /// so this takes the minimum across the event types a user actually wakes a machine with.
    private static let watchedEventTypes: [CGEventType] = [
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .mouseMoved, .leftMouseDragged, .rightMouseDragged,
        .keyDown, .flagsChanged, .scrollWheel,
    ]

    private func idleSeconds() -> TimeInterval {
        Self.watchedEventTypes
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
            .min() ?? 0
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                poll()
                try? await Task.sleep(for: .milliseconds(500), tolerance: .milliseconds(200))
            }
        }
    }

    private func poll() {
        let canDarken = effects.tick(shouldBeAwake: state == .active)
        let idle = idleSeconds()

        switch state {
        case .active:
            // The effect may forbid darkening this tick (direct edition: a panel is asleep or
            // still ramping after a wake, so a reading now would be captured as the user's value).
            guard canDarken else { break }
            if idle >= offTimeout {
                guard !DisplayPowerInfo.otherProcessHoldsDisplayAssertion() else { return }
                Self.log.info("Idle \(idle, format: .fixed(precision: 0))s → OFF")
                effects.captureBaseline()
                effects.applyOff()
                state = .off
            } else if idle >= dimTimeout {
                guard !DisplayPowerInfo.otherProcessHoldsDisplayAssertion() else { return }
                Self.log.info("Idle \(idle, format: .fixed(precision: 0))s → DIM")
                effects.captureBaseline()
                effects.applyDim()
                state = .dimmed
            }

        case .dimmed:
            if idle < 1.0 {
                Self.log.info("Activity → RESTORE")
                restoreToActive()
            } else if idle >= offTimeout {
                if DisplayPowerInfo.otherProcessHoldsDisplayAssertion() {
                    Self.log.info("External assertion detected → RESTORE from dim")
                    restoreToActive()
                    return
                }
                Self.log.info("→ OFF")
                effects.applyOff()
                state = .off
            }

        case .off:
            if idle < 1.0 {
                Self.log.info("Activity → RESTORE")
                restoreToActive()
            } else if DisplayPowerInfo.otherProcessHoldsDisplayAssertion() {
                // A real dark panel still lights up for an incoming display assertion — a call or
                // a presentation shouldn't stay hidden behind our black. Match that.
                Self.log.info("External assertion detected → RESTORE from off")
                restoreToActive()
            }

        case .idle:
            break
        }
    }

    private func restoreToActive() {
        effects.restore()
        state = .active
    }

    // MARK: - Display topology

    private func startObservingTopology() {
        topologyObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.effects.displayTopologyChanged()
            }
        }
    }

    private func stopObservingTopology() {
        if let topologyObserver {
            NotificationCenter.default.removeObserver(topologyObserver)
            self.topologyObserver = nil
        }
    }
}

/// How a screen is darkened and restored — the only behavior that differs between the direct
/// (real backlight) and App Store (black overlay) editions. The `DisplaySleepStateMachine` owns
/// all timing and policy and drives an implementation of this.
protocol DisplaySleepEffects: AnyObject {
    /// Acquire resources / snapshot the displays. Return `false` to abort the whole simulation
    /// (e.g. the direct edition's private frameworks are unavailable), leaving the machine idle.
    func begin() -> Bool

    /// Per-poll hook, called before the machine evaluates transitions. `shouldBeAwake` is true
    /// only in the active state. Returns whether the machine may enter the dim/off stages this
    /// tick — the direct edition returns false while a panel is asleep or still ramping after a
    /// wake; the overlay edition always returns true.
    func tick(shouldBeAwake: Bool) -> Bool

    /// Snapshot the current state to restore later (direct: save brightness). Called from the
    /// active state immediately before `applyDim`/`applyOff`.
    func captureBaseline()

    /// Enter the dim stage (partial darken).
    func applyDim()

    /// Enter the off stage (full darken).
    func applyOff()

    /// Return to the captured baseline (wake).
    func restore()

    /// Release resources; the machine has returned to idle.
    func end()

    /// A display was attached or detached while running.
    func displayTopologyChanged()
}

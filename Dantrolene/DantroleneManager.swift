import AppKit
import CoreLocation
import Foundation
import os
import ServiceManagement

@Observable
final class DantroleneManager {
    enum Mode: String, CaseIterable, Identifiable {
        case automatic = "Automatic"
        case alwaysOn = "Always On"
        case off = "Off"

        var id: Self {
            self
        }
    }

    enum LocationState {
        case authorized
        case notDetermined
        case denied
    }

    // MARK: - User Settings

    var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode)
            evaluate()
        }
    }

    var homeSSID: String? {
        didSet {
            UserDefaults.standard.set(homeSSID, forKey: Keys.homeSSID)
            evaluate()
        }
    }

    var displaySleepMode: DisplaySleepMode = .matchSystem {
        didSet {
            switch displaySleepMode {
            case .matchSystem:
                UserDefaults.standard.set(false, forKey: Keys.displaySleepModeIsCustom)
            case let .custom(minutes):
                UserDefaults.standard.set(true, forKey: Keys.displaySleepModeIsCustom)
                UserDefaults.standard.set(minutes, forKey: Keys.displaySleepCustomMinutes)
            }
            if isPreventingLock {
                displaySimulator.updateTimeout(displaySleepMode)
            }
        }
    }

    var blockLidCloseSleep: Bool {
        didSet {
            UserDefaults.standard.set(blockLidCloseSleep, forKey: Keys.blockLidCloseSleep)
            evaluate()
        }
    }

    @ObservationIgnored private var isUpdatingLaunchAtLogin = false

    var launchAtLogin: Bool {
        didSet {
            guard !isUpdatingLaunchAtLogin else { return }
            isUpdatingLaunchAtLogin = true
            defer { isUpdatingLaunchAtLogin = false }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = oldValue
            }
        }
    }

    // MARK: - Derived State

    private(set) var isPreventingLock = false

    // MARK: - Computed

    var currentSSID: String? {
        wifiMonitor.currentSSID
    }

    var locationState: LocationState {
        switch wifiMonitor.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        default: .authorized
        }
    }

    var isOnHomeNetwork: Bool {
        guard let home = homeSSID, let current = currentSSID else { return false }
        return home == current
    }

    var isAdrafinilInstalled: Bool {
        adrafinil.isInstalled
    }

    var isBlockingLidCloseSleep: Bool {
        adrafinil.isBlockingSleep
    }

    var isLidCloseHoldConfirmed: Bool {
        adrafinil.isHoldConfirmed
    }

    var statusText: String {
        isPreventingLock ? "Lock Prevention Active" : "Lock Prevention Inactive"
    }

    var detailText: String {
        switch locationState {
        case .notDetermined:
            return "Location access needed"
        case .denied:
            return "Location access denied"
        case .authorized:
            switch mode {
            case .automatic:
                guard currentSSID != nil else { return "No WiFi connection" }
                return isOnHomeNetwork ? "On home network" : "Away from home network"
            case .alwaysOn:
                return isPreventingLock ? "Always preventing lock" : "Always on mode"
            case .off:
                return "Manually disabled"
            }
        }
    }

    // MARK: - Private

    private enum Keys {
        static let mode = "mode"
        static let homeSSID = "homeSSID"
        static let displaySleepModeIsCustom = "displaySleepModeIsCustom"
        static let displaySleepCustomMinutes = "displaySleepCustomMinutes"
        static let blockLidCloseSleep = "blockLidCloseSleep"
    }

    private enum Constants {
        /// Grace before releasing the lid-close hold once the current SSID reads nil, so a
        /// transient WiFi drop (router reboot, DFS switch, roam) doesn't let a closed-lid Mac
        /// sleep — a sleeping Mac can't re-associate, which would defeat the hold entirely.
        static let ssidLossGraceSeconds: TimeInterval = 60
    }

    private static let log = Logger(subsystem: "glass.kagerou.dantrolene", category: "Manager")

    @ObservationIgnored private let wifiMonitor = WiFiMonitor()
    @ObservationIgnored private let lockPreventer = ScreenLockPreventer()
    @ObservationIgnored private let displaySimulator = DisplaySleepStateMachine()
    @ObservationIgnored private let adrafinil = AdrafinilBridge()
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var ssidLossGraceTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var sleepWakeObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private nonisolated(unsafe) var terminationObserver: (any NSObjectProtocol)?

    // MARK: - Init

    init() {
        let savedMode = UserDefaults.standard.string(forKey: Keys.mode) ?? Mode.automatic.rawValue
        self.mode = Mode(rawValue: savedMode) ?? .automatic
        self.homeSSID = UserDefaults.standard.string(forKey: Keys.homeSSID)

        if UserDefaults.standard.bool(forKey: Keys.displaySleepModeIsCustom) {
            let minutes = UserDefaults.standard.integer(forKey: Keys.displaySleepCustomMinutes)
            self.displaySleepMode = .custom(minutes: max(minutes, 1))
        }

        self.blockLidCloseSleep = UserDefaults.standard.bool(forKey: Keys.blockLidCloseSleep)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        lockPreventer.onStateChanged = { [weak self] isActive in
            guard let self else { return }
            self.isPreventingLock = isActive
        }

        Self.log.notice("Dantrolene \(BuildChannel.description, privacy: .public) started")

        startObserving()
        registerForSleepWake()

        DispatchQueue.main.async { [self] in
            wifiMonitor.start()
            evaluate()
        }
    }

    deinit {
        observationTask?.cancel()
        ssidLossGraceTask?.cancel()
        for observer in sleepWakeObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    // MARK: - Actions

    func setCurrentAsHome() {
        homeSSID = currentSSID
    }

    func clearHomeNetwork() {
        homeSSID = nil
    }

    func requestLocationAccess() {
        wifiMonitor.requestLocationAccess()
    }

    /// Re-detects the Adrafinil CLI (called when the popover opens) and re-evaluates, so an
    /// install or uninstall takes effect without relaunching Dantrolene.
    func refreshAdrafinilDetection() {
        adrafinil.refreshInstallation()
        evaluate()
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    private func startObserving() {
        let monitor = wifiMonitor
        observationTask = Task { [weak self] in
            for await _ in Observations({ (monitor.currentSSID, monitor.authorizationStatus) }) {
                self?.evaluate()
            }
        }
    }

    private func evaluate() {
        let shouldPrevent: Bool = switch mode {
        case .automatic: isOnHomeNetwork
        case .alwaysOn: true
        case .off: false
        }

        if shouldPrevent {
            lockPreventer.enable()
            displaySimulator.start(mode: displaySleepMode)
        } else {
            displaySimulator.stop()
            lockPreventer.disable()
        }

        // Lid-close sleep blocking follows the WiFi signal directly (not `shouldPrevent`):
        // in Always On mode away from home, blocking sleep in a closed laptop bag would be
        // a hazard, so the hold is only ever placed on the home network.
        let wantsBlockAtHome = blockLidCloseSleep && mode != .off
        if wantsBlockAtHome, isOnHomeNetwork {
            cancelSSIDLossGrace()
            let reason = homeSSID.map { "On home network \"\($0)\"" } ?? "On home network"
            adrafinil.startBlocking(reason: reason)
        } else if adrafinil.isBlockingSleep, wantsBlockAtHome, currentSSID == nil {
            // A transient WiFi drop reads as "not home", but releasing the hold now would let the
            // closed lid sleep — and a sleeping Mac can't re-associate, killing the exact workload
            // the hold protects. Debounce only this nil-SSID release; a *different* SSID means the
            // user actually moved and falls through to the immediate release below.
            startSSIDLossGrace()
        } else {
            cancelSSIDLossGrace()
            adrafinil.stopBlocking()
        }
    }

    // MARK: - Lid-close hold grace

    /// Debounces the lid-close hold's release across a transient SSID loss. Cancelled the moment
    /// the home network returns (or a different one appears); fires a real release if we're still
    /// away when it elapses. A crash mid-grace is covered by the hold's daemon-side TTL.
    private func startSSIDLossGrace() {
        guard ssidLossGraceTask == nil else { return }
        Self.log.notice("WiFi dropped while holding lid-close sleep — grace before release")
        ssidLossGraceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.ssidLossGraceSeconds))
            guard let self, !Task.isCancelled else { return }
            ssidLossGraceTask = nil
            if !isOnHomeNetwork {
                Self.log.notice("Grace elapsed, still away from home — releasing lid-close hold")
                adrafinil.stopBlocking()
            }
        }
    }

    private func cancelSSIDLossGrace() {
        ssidLossGraceTask?.cancel()
        ssidLossGraceTask = nil
    }

    // MARK: - Sleep/Wake

    private func registerForSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter

        sleepWakeObservers.append(
            nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Self.log.notice("System will sleep — releasing assertion and stopping simulator")
                    self.displaySimulator.stop()
                    self.lockPreventer.disable()
                    self.cancelSSIDLossGrace()
                    // Sleep is proceeding despite any hold (e.g. user-initiated). Release ours
                    // synchronously — a merely-enqueued release could be suspended with the
                    // rest of the process and leave the hold registered across sleep.
                    // didWake re-evaluates and re-acquires.
                    self.adrafinil.releaseSynchronously()
                }
            },
        )

        sleepWakeObservers.append(
            nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Self.log.notice("System did wake — re-evaluating")
                    self.evaluate()
                }
            },
        )

        // The Adrafinil hold lives in its daemon, not in this process, so unlike the
        // IOPMAssertions it survives our exit — release it synchronously on the way out.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Restore hardware brightness before exit. Persisted 0/0.03 (simulated .off)
                // would otherwise survive process death — a nightly macOS-update restart would
                // wake to a black login screen. The willSleep path stops the simulator; so must this.
                self.displaySimulator.stop()
                self.lockPreventer.disable()
                self.cancelSSIDLossGrace()
                self.adrafinil.releaseSynchronously()
            }
        }
    }
}

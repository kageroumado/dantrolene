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
    }

    private static let log = Logger(subsystem: "glass.kagerou.dantrolene", category: "Manager")

    @ObservationIgnored private let wifiMonitor = WiFiMonitor()
    @ObservationIgnored private let lockPreventer = ScreenLockPreventer()
    @ObservationIgnored private let displaySimulator = DisplaySleepSimulator()
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var sleepWakeObservers: [any NSObjectProtocol] = []

    // MARK: - Init

    init() {
        let savedMode = UserDefaults.standard.string(forKey: Keys.mode) ?? Mode.automatic.rawValue
        self.mode = Mode(rawValue: savedMode) ?? .automatic
        self.homeSSID = UserDefaults.standard.string(forKey: Keys.homeSSID)

        if UserDefaults.standard.bool(forKey: Keys.displaySleepModeIsCustom) {
            let minutes = UserDefaults.standard.integer(forKey: Keys.displaySleepCustomMinutes)
            self.displaySleepMode = .custom(minutes: max(minutes, 1))
        }

        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        lockPreventer.onStateChanged = { [weak self] isActive in
            guard let self else { return }
            self.isPreventingLock = isActive
        }

        startObserving()
        registerForSleepWake()

        DispatchQueue.main.async { [self] in
            wifiMonitor.start()
            evaluate()
        }
    }

    deinit {
        observationTask?.cancel()
        for observer in sleepWakeObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
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
    }

    // MARK: - Sleep/Wake

    private func registerForSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter

        sleepWakeObservers.append(
            nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Self.log.notice("System will sleep — releasing assertion and stopping simulator")
                    self.displaySimulator.stop()
                    self.lockPreventer.disable()
                }
            }
        )

        sleepWakeObservers.append(
            nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Self.log.notice("System did wake — re-evaluating")
                    self.evaluate()
                }
            }
        )
    }
}

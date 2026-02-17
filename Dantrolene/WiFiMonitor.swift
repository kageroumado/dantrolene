import CoreLocation
import CoreWLAN
import Foundation

@Observable
final class WiFiMonitor: NSObject {
    // MARK: - Observable State

    private(set) var currentSSID: String?
    private(set) var authorizationStatus = CLAuthorizationStatus.notDetermined

    // MARK: - Private

    @ObservationIgnored private let wifiClient = CWWiFiClient.shared()
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var isRunning = false

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        locationManager.delegate = self

        let status = locationManager.authorizationStatus
        authorizationStatus = status

        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        wifiClient.delegate = self
        try? wifiClient.startMonitoringEvent(with: .ssidDidChange)

        refreshSSID()
    }

    func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
    }

    private func refreshSSID() {
        currentSSID = wifiClient.interface()?.ssid()
    }
}

// MARK: - CWEventDelegate

extension WiFiMonitor: CWEventDelegate {
    nonisolated func ssidDidChangeForWiFiInterface(withName _: String) {
        DispatchQueue.main.async {
            self.refreshSSID()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WiFiMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.refreshSSID()
        }
    }
}

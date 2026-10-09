import AppKit
import CoreLocation
import Observation
import os

let weatherLog = Logger(subsystem: "com.rohithgilla.Notchemon", category: "weather")

/// Fetches the forecast for the Mac's approximate location while Show
/// Weather is on. Core Location is not touched until then, and the location
/// prompt appears only through `requestAccess`, which the toggle calls.
@MainActor
@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    private(set) var forecast: Forecast?
    private(set) var access = LocationAccess.undetermined
    private(set) var isEnabled = false
    private(set) var failed = false

    var display: WeatherDisplay {
        WeatherDisplay(enabled: isEnabled, access: access, forecast: forecast, failed: failed)
    }

    @ObservationIgnored private let fetcher: any DataFetcher
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var refresher: Task<Void, Never>?
    @ObservationIgnored private var locating = false

    init(fetcher: any DataFetcher = URLSessionFetcher()) {
        self.fetcher = fetcher
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        refresher?.cancel()
        guard on else {
            forecast = nil
            failed = false
            return
        }
        access = LocationAccess(locationManager().authorizationStatus)
        refresh()
        // The cached forecast decides whether a tick fetches, so this costs
        // one request an hour at most.
        refresher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                self?.refresh()
            }
        }
    }

    func requestAccess() {
        let manager = locationManager()
        if LocationAccess(manager.authorizationStatus) == .undetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func refresh() {
        guard isEnabled, access == .allowed, !locating else { return }
        if let forecast, forecast.isFresh(at: Date()) { return }
        locating = true
        locationManager().requestLocation()
    }

    static func openLocationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
    }

    func fetch(latitude: Double, longitude: Double) async {
        defer { locating = false }
        do {
            let data = try await fetcher.data(from: OpenMeteo.url(latitude: latitude, longitude: longitude))
            let next = try OpenMeteo.parse(data, fetchedAt: Date())
            guard isEnabled else { return }
            forecast = next
            failed = false
            weatherLog.info("Fetched a forecast with \(next.days.count) days")
        } catch {
            weatherLog.error("Forecast fetch failed: \(error.localizedDescription, privacy: .public)")
            if isEnabled { failed = true }
        }
    }

    private func locationManager() -> CLLocationManager {
        if let manager { return manager }
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
        self.manager = manager
        return manager
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            await self.fetch(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.locating = false
            self.failed = true
            weatherLog.error("Location failed: \(message, privacy: .public)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let access = LocationAccess(manager.authorizationStatus)
        Task { @MainActor in
            self.access = access
            weatherLog.info("Location access is \(String(describing: access), privacy: .public)")
            self.refresh()
        }
    }
}

extension LocationAccess {
    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .undetermined
        case .restricted, .denied: self = .denied
        case .authorizedAlways, .authorizedWhenInUse: self = .allowed
        @unknown default: self = .denied
        }
    }
}

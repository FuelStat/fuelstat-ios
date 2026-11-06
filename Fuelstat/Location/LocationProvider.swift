import CoreLocation

/// One-off location request for the station search. Asks for "while using the app" permission when needed.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum Failure: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied:
                String(localized: "Ohne Standortfreigabe kann Fuelstat keine Tankstellen in der Nähe suchen. Du kannst sie in den Einstellungen erteilen.")
            case .unavailable:
                String(localized: "Dein Standort konnte nicht bestimmt werden.")
            }
        }
    }

    private let manager = CLLocationManager()
    private var authorization: CheckedContinuation<Void, Never>?
    private var location: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        // A few hundred metres are enough to find the station you are standing at.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// True when the user already allowed location access, so asking for the location shows no prompt.
    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    func currentLocation() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { authorization = $0; manager.requestWhenInUseAuthorization() }
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: break
        default: throw Failure.denied
        }
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -120,
           recent.horizontalAccuracy >= 0, recent.horizontalAccuracy < 500 {
            return recent
        }
        return try await withCheckedThrowingContinuation { continuation in
            location?.resume(throwing: Failure.unavailable)
            location = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard manager.authorizationStatus != .notDetermined else { return }
            authorization?.resume()
            authorization = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let latest = locations.last else { return }
            location?.resume(returning: latest)
            location = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            location?.resume(throwing: Failure.unavailable)
            location = nil
        }
    }
}

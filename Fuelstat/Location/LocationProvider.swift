import CoreLocation

/// One-off location request for the station search. Asks for "while using the app" permission when needed.
///
/// Uses `CLServiceSession` and `CLLocationUpdate.liveUpdates()`: the session asks for permission, the first
/// usable update is the answer.
@MainActor
final class LocationProvider {
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

    /// Only read for the permission and the last known location; updates come from `liveUpdates()`.
    private let manager = CLLocationManager()

    /// True when the user already allowed location access, so asking for the location shows no prompt.
    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    func currentLocation() async throws -> CLLocation {
        // A few hundred metres and two minutes are enough to find the station you are standing at.
        if isAuthorized, let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -120,
           recent.horizontalAccuracy >= 0, recent.horizontalAccuracy < 500 {
            return recent
        }
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        throw Failure.denied
                    }
                    if let location = update.location { return location }
                }
                throw Failure.unavailable
            }
            group.addTask {
                // Without a fix after a while (no GPS, flight mode) give up instead of waiting forever. Long
                // enough to include the permission prompt on first use.
                try await Task.sleep(for: .seconds(45))
                throw Failure.unavailable
            }
            defer { group.cancelAll() }
            guard let location = try await group.next() else { throw Failure.unavailable }
            return location
        }
    }
}

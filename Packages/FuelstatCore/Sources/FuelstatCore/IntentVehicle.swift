/// Which vehicle a Siri or Shortcuts action uses when the user did not name one.
public enum IntentVehicleChoice: Equatable, Sendable {
    case vehicle(String)
    /// Several vehicles and no usable default: the system has to ask.
    case ask
    /// The account has no vehicles yet.
    case none

    /// Uses the named vehicle if it exists, otherwise the only vehicle, otherwise the one remembered in the app
    /// (vehicle switcher, last entry), otherwise asks.
    public static func resolve(explicit: String?, available: [String], remembered: [String?]) -> IntentVehicleChoice {
        if available.isEmpty { return .none }
        if let explicit {
            return available.contains(explicit) ? .vehicle(explicit) : .ask
        }
        if available.count == 1 { return .vehicle(available[0]) }
        for case let id? in remembered where available.contains(id) {
            return .vehicle(id)
        }
        return .ask
    }
}

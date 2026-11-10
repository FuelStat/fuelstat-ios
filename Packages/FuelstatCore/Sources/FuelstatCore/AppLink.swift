import Foundation

/// Links into the app (`fuelstat://…`), used by widgets to open a vehicle or the entry sheet.
public enum AppLink: Equatable, Sendable {
    public static let scheme = "fuelstat"

    /// `fuelstat://add?kind=fuel&vehicle=<id>`; kind is `fuel` or `charge`, both parameters are optional.
    case addEntry(kind: String?, vehicleID: String?)
    /// `fuelstat://vehicle/<id>`
    case vehicle(String)

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .addEntry(let kind, let vehicleID):
            components.host = "add"
            var items: [URLQueryItem] = []
            if let kind { items.append(URLQueryItem(name: "kind", value: kind)) }
            if let vehicleID { items.append(URLQueryItem(name: "vehicle", value: vehicleID)) }
            components.queryItems = items.isEmpty ? nil : items
        case .vehicle(let id):
            components.host = "vehicle"
            components.path = "/" + id
        }
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        func value(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        switch components.host?.lowercased() {
        case "add":
            let kind = value("kind")
            guard kind == nil || kind == "fuel" || kind == "charge" else { return nil }
            self = .addEntry(kind: kind, vehicleID: value("vehicle"))
        case "vehicle":
            let id = components.path.split(separator: "/").first.map(String.init)
            guard let id, !id.isEmpty else { return nil }
            self = .vehicle(id)
        default:
            return nil
        }
    }
}

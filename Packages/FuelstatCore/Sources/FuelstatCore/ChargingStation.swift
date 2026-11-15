import Foundation

/// Charging station from `GET /charging-stations` (Open Charge Map, CC BY 4.0).
///
/// Everything comes from the API; this only reads it and builds the texts the app shows.
public struct ChargingStation: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let operatorName: String?
    public let street: String?
    public let place: String?
    public let postCode: String?
    public let latitude: Double?
    public let longitude: Double?
    public let distanceKm: Double?
    /// Number of charge points.
    public let points: Int?
    /// Highest charging power in kW.
    public let maxKw: Double?
    /// Plug types as the API names them, e.g. `CCS`, `Typ 2`.
    public let connectors: [String]
    /// Free text of the operator, e.g. "0,59 €/kWh".
    public let usageCost: String?
    /// false = out of order.
    public let isOperational: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, street, place, postCode, points, maxKw, connectors, usageCost, isOperational, distanceKm
        case operatorName = "operator"
        case latitude = "lat"
        case longitude = "lng"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        operatorName = c.lenientText(.operatorName)
        street = c.lenientText(.street)
        place = c.lenientText(.place)
        postCode = c.lenientText(.postCode)
        latitude = c.lenientNumber(.latitude)
        longitude = c.lenientNumber(.longitude)
        distanceKm = c.lenientNumber(.distanceKm)
        points = c.lenientInt(.points)
        maxKw = c.lenientNumber(.maxKw)
        connectors = c.lenientList(.connectors, of: String.self)
        usageCost = c.lenientText(.usageCost)
        isOperational = c.lenientBool(.isOperational) ?? true
        // The id is nullable in the API; without one the name and position identify the station well enough.
        if let id = c.lenientText(.id) {
            self.id = id
        } else {
            let position = [latitude, longitude].compactMap { $0 }.map { String($0) }.joined(separator: ",")
            self.id = "\(name)|\(position)"
        }
    }

    public init(id: String, name: String, operatorName: String? = nil, street: String? = nil, place: String? = nil,
                postCode: String? = nil, latitude: Double? = nil, longitude: Double? = nil, distanceKm: Double? = nil,
                points: Int? = nil, maxKw: Double? = nil, connectors: [String] = [], usageCost: String? = nil,
                isOperational: Bool = true) {
        self.id = id
        self.name = name
        self.operatorName = operatorName
        self.street = street
        self.place = place
        self.postCode = postCode
        self.latitude = latitude
        self.longitude = longitude
        self.distanceKm = distanceKm
        self.points = points
        self.maxKw = maxKw
        self.connectors = connectors
        self.usageCost = usageCost
        self.isOperational = isOperational
    }

    /// Operator when known, otherwise the station's own name.
    public var title: String {
        guard let operatorName else { return name }
        return name.localizedCaseInsensitiveContains(operatorName) ? name : "\(operatorName) \(name)"
    }

    /// "Rotenbacher Str. 1, 73479 Ellwangen"
    public var address: String {
        let placeLine = [postCode, place].compactMap { $0 }.joined(separator: " ")
        return [street, placeLine].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Text stored as `station` of the charging session, e.g. "EnBW mobility+ EnBW HPC Ellwangen, Rotenbacher Str. 1, Ellwangen".
    public var label: String {
        [title, street, place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Power in kW without a pointless decimal, e.g. "300" or "22,5".
    public var maxPowerText: String? {
        guard let maxKw, maxKw > 0 else { return nil }
        let rounded = (maxKw * 10).rounded() / 10
        return rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rounded))
            : String(rounded).replacingOccurrences(of: ".", with: ",")
    }

    /// Plug types joined for one line, e.g. "CCS · Typ 2".
    public var connectorsText: String? {
        connectors.isEmpty ? nil : connectors.joined(separator: " · ")
    }
}

/// Response of `GET /charging-stations`.
public struct ChargingStationsResponse: Decodable, Sendable {
    public let stations: [ChargingStation]
    /// Name and licence of the data source, which the app must show.
    public let source: String?
    public let license: String?
    public let sourceUrl: String?

    enum CodingKeys: String, CodingKey { case stations, source, license, sourceUrl }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // One station the app cannot read does not hide the others.
        stations = c.lenientList(.stations, of: ChargingStation.self)
        source = c.lenientText(.source)
        license = c.lenientText(.license)
        sourceUrl = c.lenientText(.sourceUrl)
    }
}

import Foundation

struct APIUser: Decodable, Equatable {
    let id: String
    let email: String
}

struct AuthResponse: Decodable {
    let token: String
    let user: APIUser
}

struct APIErrorResponse: Decodable {
    let error: String
    let detail: String?
}

/// Fuel type as delivered by the Fuelstat API. Unknown values decode to `.other`.
enum RemoteFuelType: String, Codable, CaseIterable, Identifiable {
    case diesel, e5, e10, lpg, cng, electric, hybrid, phev, hydrogen, other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RemoteFuelType(rawValue: raw) ?? .other
    }

    var label: String {
        switch self {
        case .diesel: "Diesel"
        case .e5: "Super E5"
        case .e10: "Super E10"
        case .lpg: "Autogas (LPG)"
        case .cng: "Erdgas (CNG)"
        case .electric: "Elektro"
        case .hybrid: "Hybrid"
        case .phev: "Plug-in-Hybrid"
        case .hydrogen: "Wasserstoff"
        case .other: "Sonstige"
        }
    }

    var id: String { rawValue }

    /// Meaning of the API field `tank_capacity`: for electric cars it holds the battery size.
    var tankCapacityLabel: String { self == .electric ? "Akkukapazität" : "Tankinhalt" }

    /// Unit of `tank_capacity`.
    var tankCapacityUnit: String {
        switch self {
        case .electric: "kWh"
        case .cng, .hydrogen: "kg"
        default: "L"
        }
    }

    /// Only plug-in hybrids have a separate `battery_capacity`.
    var hasSeparateBattery: Bool { self == .phev }

    var symbol: String {
        switch self {
        case .electric: "bolt.car"
        case .phev, .hybrid: "car.side"
        default: "fuelpump"
        }
    }
}

/// Vehicle from `GET /api/v1/vehicles` and `GET /api/v1/vehicles/{id}` – basic master data only.
struct RemoteVehicle: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let fuelType: RemoteFuelType
    let brand: String?
    let model: String?
    let year: Int?
    let licensePlate: String?
    let vin: String?
    /// Calendar date `YYYY-MM-DD`.
    let firstRegistration: String?
    let odometerKm: Double?
    let tankCapacity: Double?
    let batteryCapacity: Double?
    let tireSizeSummer: String?
    let tireSizeWinter: String?

    enum CodingKeys: String, CodingKey {
        case id, name, brand, model, year, vin
        case fuelType = "fuel_type"
        case licensePlate = "license_plate"
        case firstRegistration = "first_registration"
        case odometerKm = "odometer_km"
        case tankCapacity = "tank_capacity"
        case batteryCapacity = "battery_capacity"
        case tireSizeSummer = "tire_size_summer"
        case tireSizeWinter = "tire_size_winter"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fuelType = try c.decode(RemoteFuelType.self, forKey: .fuelType)
        brand = c.text(.brand)
        model = c.text(.model)
        year = c.number(.year).map { Int($0) }
        licensePlate = c.text(.licensePlate)
        vin = c.text(.vin)
        firstRegistration = c.text(.firstRegistration).map { String($0.prefix(10)) }
        odometerKm = c.number(.odometerKm)
        tankCapacity = c.number(.tankCapacity)
        batteryCapacity = c.number(.batteryCapacity)
        tireSizeSummer = c.text(.tireSizeSummer)
        tireSizeWinter = c.text(.tireSizeWinter)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Body for `POST /api/v1/vehicles`. Nil values are left out.
struct VehicleCreateRequest: Encodable {
    var name: String
    var fuelType: RemoteFuelType
    var brand: String?
    var model: String?
    var year: Int?
    var licensePlate: String?
    var vin: String?
    /// `YYYY-MM-DD`
    var firstRegistration: String?
    var odometerKm: Double?
    var tankCapacity: Double?
    var batteryCapacity: Double?
}

private extension KeyedDecodingContainer {
    /// Non-empty string, or nil.
    func text(_ key: Key) -> String? {
        guard let value = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The API sends Postgres numerics as strings (e.g. `"50.000"`), so accept both.
    func number(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }
}

import Foundation

struct APIUser: Decodable, Equatable {
    let id: String
    let email: String
}

struct AuthResponse: Decodable {
    let token: String
    let user: APIUser
}

/// Response of `POST /auth/refresh`.
struct TokenResponse: Decodable {
    let token: String
}

/// Response of `GET /health` (no sign-in needed).
struct HealthResponse: Decodable {
    let status: String
    let version: String?
    /// Current version of the terms of use (a date such as `2026-11-09`), if the server has terms.
    let termsVersion: String?

    enum CodingKeys: String, CodingKey {
        case status, version
        case termsVersion = "terms_version"
    }
}

/// Body of `POST /feedback`.
struct FeedbackInput: Encodable {
    enum Category: String, Encodable, CaseIterable, Identifiable {
        case fehler, idee, lob, sonstiges

        var id: String { rawValue }
    }

    let category: Category
    let message: String
    /// Where the feedback comes from; the app sends its version and the iOS version.
    let page: String
}

/// Response of `POST /feedback`: always stored, `mailed` tells whether the operator also got a mail.
struct FeedbackResponse: Decodable {
    let saved: Bool?
    let mailed: Bool?
}

struct APIErrorResponse: Decodable {
    let error: String
    let detail: String?
    /// Only for `plan_required`: which plan limit was hit, its value and the current plan.
    let feature: String?
    let limit: Int?
    let plan: String?

    enum CodingKeys: String, CodingKey { case error, detail, feature, limit, plan }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = try c.decode(String.self, forKey: .error)
        detail = c.text(.detail)
        feature = c.text(.feature)
        limit = c.number(.limit).map { Int($0) }
        plan = c.text(.plan)
    }
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
        case .diesel: String(localized: "Diesel")
        case .e5: String(localized: "Super E5")
        case .e10: String(localized: "Super E10")
        case .lpg: String(localized: "Autogas (LPG)")
        case .cng: String(localized: "Erdgas (CNG)")
        case .electric: String(localized: "Elektro")
        case .hybrid: String(localized: "Hybrid")
        case .phev: String(localized: "Plug-in-Hybrid")
        case .hydrogen: String(localized: "Wasserstoff")
        case .other: String(localized: "Sonstige")
        }
    }

    var id: String { rawValue }

    /// Meaning of the API field `tank_capacity`: for electric cars it holds the battery size.
    var tankCapacityLabel: String {
        self == .electric ? String(localized: "Akkukapazität") : String(localized: "Tankinhalt")
    }

    /// Unit of `tank_capacity` and of fill-up amounts.
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

/// Vehicle from `GET /api/v1/vehicles` and `GET /api/v1/vehicles/{id}`.
struct RemoteVehicle: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let fuelType: RemoteFuelType
    let brand: String?
    let model: String?
    let year: Int?
    /// Signed, relative address of the photo (`/api/v1/files/…?exp=…&sig=…`), valid until the end of the next day.
    let imageURL: String?
    let licensePlate: String?
    let vin: String?
    /// Calendar date `YYYY-MM-DD`.
    let firstRegistration: String?
    /// Odometer when the vehicle was added; the current value comes from the statistics.
    let odometerKm: Double?
    let tankCapacity: Double?
    let batteryCapacity: Double?
    let tireSizeSummer: String?
    let tireSizeWinter: String?

    enum CodingKeys: String, CodingKey {
        case id, name, brand, model, year, vin
        case fuelType = "fuel_type"
        case imageURL = "image_url"
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
        imageURL = c.text(.imageURL)
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

/// Body for `POST /api/v1/vehicles` and `PATCH /api/v1/vehicles/{id}`.
///
/// When creating, nil values are left out. When updating, they are sent as `null`, which clears the field.
/// Fields the app does not edit (tyres, insurance, …) are never sent, so they stay unchanged.
struct VehicleInput: Encodable {
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
    /// true for PATCH.
    var sendsNulls = false

    enum CodingKeys: String, CodingKey {
        case name, fuelType, brand, model, year, licensePlate, vin, firstRegistration
        case odometerKm, tankCapacity, batteryCapacity
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(fuelType, forKey: .fuelType)
        func put<T: Encodable>(_ value: T?, _ key: CodingKeys) throws {
            if let value {
                try c.encode(value, forKey: key)
            } else if sendsNulls {
                try c.encodeNil(forKey: key)
            }
        }
        try put(brand, .brand)
        try put(model, .model)
        try put(year, .year)
        try put(licensePlate, .licensePlate)
        try put(vin, .vin)
        try put(firstRegistration, .firstRegistration)
        try put(odometerKm, .odometerKm)
        try put(tankCapacity, .tankCapacity)
        try put(batteryCapacity, .batteryCapacity)
    }
}

/// Body for `PATCH /api/v1/vehicles/{id}` that sets or removes the photo.
struct VehicleImagePatch: Encodable {
    /// Address from the upload response, or nil to remove the photo.
    var imageUrl: String?

    enum CodingKeys: String, CodingKey { case imageUrl }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let imageUrl { try c.encode(imageUrl, forKey: .imageUrl) } else { try c.encodeNil(forKey: .imageUrl) }
    }
}

/// Response of the image upload.
struct RemoteMedia: Decodable {
    let id: String
    let url: String
}

/// Key figures from `GET /api/v1/vehicles/{id}/stats`, in the unit of the vehicle (L, kWh or kg).
struct VehicleStats: Decodable {
    struct Trend {
        /// Consumption of the latest segment per 100 km.
        let current: Double
        /// Difference to the average of the earlier segments (negative = less consumption).
        let diff: Double
    }

    let currentOdometerKm: Double?
    let averageConsumption: Double?
    let averagePricePerUnit: Double?
    /// Fill-ups without a real odometer reading.
    let missingOdometer: Int
    let trend: Trend?
    /// Full-to-full segments with the consumption the API calculated for each.
    let segments: [Segment]

    /// Consumption between two full fill-ups, per 100 km in the segment's unit.
    struct Segment: Decodable, Identifiable {
        let id: String
        let date: Date
        let unit: String
        let km: Double?
        let per100Km: Double

        enum CodingKeys: String, CodingKey {
            case id = "full_id", date = "full_at", unit, km
            case per100Km = "l_per_100km"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let date = c.text(.date).flatMap(APIDate.parse), let value = c.number(.per100Km) else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "segment"))
            }
            id = c.text(.id) ?? UUID().uuidString
            self.date = date
            unit = c.text(.unit) ?? "l"
            km = c.number(.km)
            per100Km = value
        }
    }

    enum CodingKeys: String, CodingKey {
        case currentOdo, avgConsumption, avgPricePerLiter, missingOdometer, trend, segments
    }

    enum TrendKeys: String, CodingKey { case current, diff }

    /// Skips segments that cannot be read instead of failing the whole response.
    private struct LossySegment: Decodable {
        let value: Segment?
        init(from decoder: Decoder) throws { value = try? Segment(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentOdometerKm = c.number(.currentOdo)
        averageConsumption = c.number(.avgConsumption)
        averagePricePerUnit = c.number(.avgPricePerLiter)
        missingOdometer = c.number(.missingOdometer).map { Int($0) } ?? 0
        if let t = try? c.nestedContainer(keyedBy: TrendKeys.self, forKey: .trend),
           let current = t.number(.current), let diff = t.number(.diff) {
            trend = Trend(current: current, diff: diff)
        } else {
            trend = nil
        }
        segments = ((try? c.decodeIfPresent([LossySegment].self, forKey: .segments)) ?? []).compactMap(\.value)
    }
}

/// Fill-up or charging session from `GET /api/v1/vehicles/{id}/fillups`.
struct RemoteFillup: Decodable, Identifiable {
    let id: String
    let filledAt: Date?
    let odometerKm: Double?
    let amount: Double
    /// `l`, `kwh` or `kg`
    let unit: String
    let totalCostEur: Double?
    let station: String?
    let isFull: Bool

    var isCharging: Bool { unit == "kwh" }

    var unitLabel: String {
        switch unit {
        case "kwh": "kWh"
        case "kg": "kg"
        default: "L"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, amount, unit, station
        case filledAt = "filled_at"
        case odometerKm = "odometer_km"
        case totalCostEur = "total_cost_eur"
        case isFull = "is_full"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        filledAt = c.text(.filledAt).flatMap(Self.parseDate)
        odometerKm = c.number(.odometerKm)
        amount = c.number(.amount) ?? 0
        unit = c.text(.unit) ?? "l"
        totalCostEur = c.number(.totalCostEur)
        station = c.text(.station)
        isFull = (try? c.decode(Bool.self, forKey: .isFull)) ?? true
    }

    private static func parseDate(_ text: String) -> Date? { APIDate.parse(text) }
}

enum APIDate {
    /// ISO 8601 timestamp with or without fractional seconds.
    static func parse(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Calendar date `YYYY-MM-DD` (also accepts a timestamp and uses its date part).
    static func parseDay(_ text: String) -> Date? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: String(text.prefix(10)))
    }

    /// Formats a calendar date from the API without shifting it by the device's time zone.
    static func formatDay(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.day().month().year()
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }
}

// MARK: - Reminders

/// Due date from `GET /api/v1/vehicles/{id}/reminders`; status and dates are calculated by the API.
struct RemoteReminder: Decodable, Identifiable {
    enum Status: String {
        case ok, soon = "bald", overdue = "ueberfaellig", unknown = "unbekannt"
    }

    let title: String
    let category: String
    let dueDate: Date?
    let dueKm: Double?
    let status: Status
    /// Days until the due date (negative when overdue).
    let days: Int?

    var id: String { category + title }

    var symbol: String {
        switch category.uppercased() {
        case "TUV", "TÜV", "HU": "checkmark.seal"
        case "WARTUNG", "INSPEKTION", "SERVICE", "OEL", "ÖL": "wrench.and.screwdriver"
        case "VERSICHERUNG", "INSURANCE": "shield"
        case "STEUER", "TAX": "eurosign.circle"
        default: "calendar.badge.exclamationmark"
        }
    }

    enum CodingKeys: String, CodingKey {
        case title, category, status, days
        case dueDate = "due_date"
        case dueKm = "due_km"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.text(.title) ?? ""
        category = c.text(.category) ?? ""
        dueDate = c.text(.dueDate).flatMap(APIDate.parseDay)
        dueKm = c.number(.dueKm)
        status = c.text(.status).flatMap(Status.init(rawValue:)) ?? .unknown
        days = c.number(.days).map { Int($0) }
    }
}

extension KeyedDecodingContainer {
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

// MARK: - Fill-ups

/// Body for `POST /api/v1/fillups`.
struct FillupInput: Encodable {
    var vehicleId: String
    /// `l`, `kwh` or `kg`
    var unit: String
    var amount: Double
    var totalCostEur: Double
    var odometerKm: Int?
    var station: String?
    var filledAt: Date
    var isFull: Bool
    /// The previous fill-up was not recorded: consumption is not calculated across the gap.
    var skipPrevious: Bool

    enum CodingKeys: String, CodingKey {
        case vehicleId, unit, amount, totalCostEur, odometerKm, station, filledAt, isFull, skipPrevious
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vehicleId, forKey: .vehicleId)
        try c.encode(unit, forKey: .unit)
        try c.encode(amount, forKey: .amount)
        try c.encode(totalCostEur, forKey: .totalCostEur)
        try c.encodeIfPresent(odometerKm, forKey: .odometerKm)
        try c.encodeIfPresent(station, forKey: .station)
        try c.encode(ISO8601DateFormatter().string(from: filledAt), forKey: .filledAt)
        try c.encode(isFull, forKey: .isFull)
        try c.encode(skipPrevious, forKey: .skipPrevious)
    }
}

/// Response of `POST /api/v1/fillups`: the API saves implausible odometer readings but warns about them.
struct FillupCreated: Decodable {
    struct Warning: Decodable {
        let code: String
        let message: String?
    }

    let id: String
    let warnings: [Warning]

    enum CodingKeys: String, CodingKey { case id, warnings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        warnings = (try? c.decodeIfPresent([Warning].self, forKey: .warnings)) ?? []
    }
}

extension RemoteFuelType {
    /// Units a fill-up of this vehicle can have: plug-in hybrids are either fuelled (litres) or charged (kWh).
    var fillupUnits: [String] {
        switch self {
        case .electric: ["kwh"]
        case .cng, .hydrogen: ["kg"]
        case .phev: ["l", "kwh"]
        default: ["l"]
        }
    }

    /// Fuel type for the Tankerkönig search, or nil where Tankerkönig has no prices (electricity, gas, hydrogen).
    func stationSearchType(unit: String) -> String? {
        guard unit == "l" else { return nil }
        switch self {
        case .e5: return "e5"
        case .e10: return "e10"
        case .diesel: return "diesel"
        case .lpg: return nil
        default: return "all"
        }
    }
}

// MARK: - Stations

/// Fuel station from `GET /api/v1/stations` (data: Tankerkönig, CC BY 4.0).
struct RemoteStation: Decodable, Identifiable {
    let id: String
    let name: String
    let brand: String?
    let street: String?
    let houseNumber: String?
    let postCode: String?
    let place: String?
    let lat: Double?
    let lng: Double?
    let distanceKm: Double?
    let isOpen: Bool
    let prices: [String: Double?]

    /// Price for the searched fuel type; for a search over all types the petrol price, otherwise diesel.
    func price(for type: String) -> Double? {
        if type == "all" {
            return (prices["e10"] ?? nil) ?? (prices["e5"] ?? nil) ?? (prices["diesel"] ?? nil)
        }
        return prices[type] ?? nil
    }

    var latitude: Double? { lat }
    var longitude: Double? { lng }

    var address: String {
        let streetLine = [street, houseNumber].compactMap { $0 }.joined(separator: " ")
        let placeLine = [postCode, place].compactMap { $0 }.joined(separator: " ")
        return [streetLine, placeLine].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Text stored as `station` of the fill-up, e.g. "JET, Mustergasse 1, Berlin".
    var label: String {
        let title = brand.map { brand in name.localizedCaseInsensitiveContains(brand) ? name : "\(brand) \(name)" } ?? name
        let streetLine = [street, houseNumber].compactMap { $0 }.joined(separator: " ")
        return [title, streetLine, place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct StationsResponse: Decodable {
    let stations: [RemoteStation]
}

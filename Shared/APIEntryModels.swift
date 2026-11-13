import Foundation
import FuelstatCore

// Models for the entry list, expenses, categories, the trip log and vehicle sharing.
// Everything is read as the API delivers it; sums, consumption and rights are never calculated here.

// MARK: - Timeline

/// One row of `GET /vehicles/:id/timeline`: a fill-up, charging session, expense, odometer note or trip.
struct TimelineItem: Decodable, Identifiable, Hashable {
    /// Which endpoint edits the row.
    enum Source: String {
        case fillup, entry, trip
    }

    enum Kind: String, CaseIterable {
        case fuel, charge, expense, trip, odometer
    }

    let source: Source
    let kind: Kind
    let rawID: String
    let date: Date?
    /// Category key as in `GET /categories`.
    let category: String?
    let cost: Double?
    let countsAsCost: Bool
    let amount: Double?
    /// `l`, `kwh` or `kg` (fill-ups only).
    let unit: String?
    /// Fuel type of a fill-up (FuelStat/fuelstat#140).
    let fuel: String?
    let odometerKm: Double?
    let odometerEstimated: Bool
    let isFull: Bool?
    let skipPrevious: Bool?
    /// Station (fill-ups) or vendor (expenses).
    let place: String?
    let description: String?
    let purpose: String?
    let distanceKm: Double?
    let startPlace: String?
    let endPlace: String?
    /// Consumption per 100 km of the segment a full fill-up closes, as calculated by the API.
    let consumption: Double?
    let createdBy: String?
    let createdByName: String?

    var id: String { "\(source.rawValue)-\(rawID)" }

    var unitLabel: String {
        switch unit {
        case "kwh": "kWh"
        case "kg": "kg"
        default: "L"
        }
    }

    /// A fill-up without a real odometer reading: it can be added later at any time.
    var isMissingOdometer: Bool { source == .fillup && (odometerKm == nil || odometerEstimated) }

    enum CodingKeys: String, CodingKey {
        case type, kind, id, at, category, cost, countsAsCost, amount, unit, place, description, purpose, consumption, fuel
        case odometerKm = "odometer_km"
        case odometerEstimated = "odometer_estimated"
        case isFull = "is_full"
        case skipPrevious = "skip_previous"
        case distanceKm = "distance_km"
        case startPlace = "start_place"
        case endPlace = "end_place"
        case createdBy = "created_by"
        case createdByName = "created_by_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let source = c.text(.type).flatMap(Source.init(rawValue:)),
              let kind = c.text(.kind).flatMap(Kind.init(rawValue:)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "timeline row"))
        }
        self.source = source
        self.kind = kind
        rawID = try c.decode(String.self, forKey: .id)
        date = c.text(.at).flatMap(APIDate.parse)
        category = c.text(.category)
        cost = c.number(.cost)
        countsAsCost = (try? c.decodeIfPresent(Bool.self, forKey: .countsAsCost)) ?? true
        amount = c.number(.amount)
        unit = c.text(.unit)
        fuel = c.text(.fuel)
        odometerKm = c.number(.odometerKm)
        odometerEstimated = (try? c.decodeIfPresent(Bool.self, forKey: .odometerEstimated)) ?? false
        isFull = try? c.decodeIfPresent(Bool.self, forKey: .isFull)
        skipPrevious = try? c.decodeIfPresent(Bool.self, forKey: .skipPrevious)
        place = c.text(.place)
        description = c.text(.description)
        purpose = c.text(.purpose)
        distanceKm = c.number(.distanceKm)
        startPlace = c.text(.startPlace)
        endPlace = c.text(.endPlace)
        consumption = c.number(.consumption)
        createdBy = c.text(.createdBy)
        createdByName = c.text(.createdByName)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Skips rows the app cannot read (e.g. a kind added by a newer server) instead of failing the whole page.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

/// Response of `GET /vehicles/:id/timeline`.
struct TimelinePage: Decodable {
    /// Number of entries and costs of a whole month, with the same filters as the page.
    struct Month: Decodable {
        /// `YYYY-MM`
        let month: String
        let count: Int
        let total: Double
    }

    let items: [TimelineItem]
    let hasMore: Bool
    let months: [Month]
    /// Years with entries, without filters.
    let years: [Int]
    /// Number of entries per kind, without filters.
    let kinds: [String: Int]

    enum CodingKeys: String, CodingKey { case data, pagination, months, years, kinds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([Lossy<TimelineItem>].self, forKey: .data).compactMap(\.value)
        hasMore = (try? c.decode(Page<TimelineItem>.Pagination.self, forKey: .pagination))?.hasMore ?? false
        months = (try? c.decodeIfPresent([Month].self, forKey: .months)) ?? []
        years = (try? c.decodeIfPresent([Int].self, forKey: .years)) ?? []
        kinds = (try? c.decodeIfPresent([String: Int].self, forKey: .kinds)) ?? [:]
    }
}

/// Odometer warning the API returns after saving (`warnings`): the entry is stored, the user should check it.
struct OdometerWarning: Decodable {
    let code: String
    let message: String?
}

/// Reads `id` and `warnings` from any "saved" response.
struct SavedEntry: Decodable {
    let id: String
    let warnings: [OdometerWarning]

    var messages: [String] { warnings.compactMap(\.message) }

    enum CodingKeys: String, CodingKey { case id, warnings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        warnings = (try? c.decodeIfPresent([OdometerWarning].self, forKey: .warnings)) ?? []
    }
}

// MARK: - Fill-up changes

/// Body of `PATCH /fillups/:id` for a full edit. The API allows it for 14 days after the fill-up.
struct FillupPatch: Encodable {
    var unit: String
    var amount: Double
    var totalCostEur: Double
    /// nil removes the reading.
    var odometerKm: Int?
    var station: String?
    var filledAt: Date
    var isFull: Bool
    var skipPrevious: Bool
    /// Fuel type; nil leaves it unchanged.
    var fuel: String? = nil

    enum CodingKeys: String, CodingKey {
        case unit, amount, totalCostEur, odometerKm, station, filledAt, isFull, skipPrevious, fuel
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(unit, forKey: .unit)
        try c.encode(amount, forKey: .amount)
        try c.encode(totalCostEur, forKey: .totalCostEur)
        if let odometerKm { try c.encode(odometerKm, forKey: .odometerKm) } else { try c.encodeNil(forKey: .odometerKm) }
        if let station { try c.encode(station, forKey: .station) } else { try c.encodeNil(forKey: .station) }
        try c.encode(ISO8601DateFormatter().string(from: filledAt), forKey: .filledAt)
        try c.encode(isFull, forKey: .isFull)
        try c.encode(skipPrevious, forKey: .skipPrevious)
        try c.encodeIfPresent(fuel, forKey: .fuel)
    }
}

/// Body of `PATCH /fillups/:id` with the odometer only: allowed at any time, also after the 14 days.
struct OdometerPatch: Encodable {
    let odometerKm: Int
}

// MARK: - Expenses

/// Expense or odometer note from `GET /entries/:id`.
struct RemoteExpense: Decodable {
    let id: String
    let category: String
    let amountEur: Double
    let odometerKm: Double?
    let occurredAt: Date?
    let vendor: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, category, vendor, description
        case amountEur = "amount_eur"
        case odometerKm = "odometer_km"
        case occurredAt = "occurred_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = c.text(.category) ?? ""
        amountEur = c.number(.amountEur) ?? 0
        odometerKm = c.number(.odometerKm)
        occurredAt = c.text(.occurredAt).flatMap(APIDate.parse)
        vendor = c.text(.vendor)
        description = c.text(.description)
    }
}

/// Body of `POST /entries` and `PATCH /entries/:id`.
///
/// When creating, nil values are left out. When updating, they are sent as `null`, which clears the field.
struct ExpenseInput: Encodable {
    /// Category key of an odometer note (no costs).
    static let odometerCategory = "Kilometerstand"

    var vehicleId: String
    var category: String
    var amountEur: Double
    var odometerKm: Int?
    var occurredAt: Date
    var vendor: String?
    var description: String?
    /// true for PATCH.
    var sendsNulls = false

    enum CodingKeys: String, CodingKey {
        case vehicleId, category, amountEur, odometerKm, occurredAt, vendor, description
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !sendsNulls { try c.encode(vehicleId, forKey: .vehicleId) }
        try c.encode(category, forKey: .category)
        try c.encode(amountEur, forKey: .amountEur)
        try c.encode(ISO8601DateFormatter().string(from: occurredAt), forKey: .occurredAt)
        func put<T: Encodable>(_ value: T?, _ key: CodingKeys) throws {
            if let value {
                try c.encode(value, forKey: key)
            } else if sendsNulls {
                try c.encodeNil(forKey: key)
            }
        }
        try put(odometerKm, .odometerKm)
        try put(vendor, .vendor)
        try put(description, .description)
    }
}

// MARK: - Categories

/// Expense category from `GET /categories`. Name, icon and colour always come from the API.
struct RemoteCategory: Decodable, Identifiable, Hashable {
    /// Fixed key stored with the expense, e.g. `Versicherung` or `custom:<uuid>`.
    let key: String
    /// Only for own categories: the id used by `PATCH` and `DELETE /categories/:id`.
    let customID: String?
    let name: String
    /// Font Awesome name; see `CategoryStyle.symbol(forIcon:)`.
    let icon: String?
    /// Hex colour.
    let color: String?
    let group: String?
    /// `expense`, `trip`, `odometer` or `fillup`.
    let form: String
    /// `free` or `plus`.
    let plan: String
    let isCustom: Bool
    /// Offered in the category picker of an expense at all.
    let isSelectable: Bool
    /// The user's plan allows it for new entries; locked ones are shown with a hint, not hidden.
    let isAvailable: Bool
    /// Own category of the owner of a shared vehicle: shown, but only its owner can pick or change it.
    let isShared: Bool

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, id, name, icon, color, group, form, plan, custom, selectable, available, shared
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        customID = c.text(.id)
        name = c.text(.name) ?? key
        icon = c.text(.icon)
        color = c.text(.color)
        group = c.text(.group)
        form = c.text(.form) ?? "expense"
        plan = c.text(.plan) ?? "free"
        isCustom = (try? c.decodeIfPresent(Bool.self, forKey: .custom)) ?? false
        isSelectable = (try? c.decodeIfPresent(Bool.self, forKey: .selectable)) ?? false
        isAvailable = (try? c.decodeIfPresent(Bool.self, forKey: .available)) ?? false
        isShared = (try? c.decodeIfPresent(Bool.self, forKey: .shared)) ?? false
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// Response of `GET /categories`.
struct CategoriesResponse: Decodable {
    struct Group: Decodable, Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

    /// Limits and allowed symbols and colours for own categories.
    struct CustomRules: Decodable {
        let max: Int
        let used: Int
        let canCreate: Bool
        let icons: [String]
        let colors: [String]
        let nameMaxLength: Int

        enum CodingKeys: String, CodingKey { case max, used, canCreate, icons, colors, nameMaxLength }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            max = c.number(.max).map { Int($0) } ?? 0
            used = c.number(.used).map { Int($0) } ?? 0
            canCreate = (try? c.decodeIfPresent(Bool.self, forKey: .canCreate)) ?? false
            icons = (try? c.decodeIfPresent([String].self, forKey: .icons)) ?? []
            colors = (try? c.decodeIfPresent([String].self, forKey: .colors)) ?? []
            nameMaxLength = c.number(.nameMaxLength).map { Int($0) } ?? 40
        }
    }

    let groups: [Group]
    let categories: [RemoteCategory]
    let custom: CustomRules?

    enum CodingKeys: String, CodingKey { case groups, categories, custom }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = (try? c.decodeIfPresent([Group].self, forKey: .groups)) ?? []
        categories = try c.decode([Lossy<RemoteCategory>].self, forKey: .categories).compactMap(\.value)
        custom = try? c.decodeIfPresent(CustomRules.self, forKey: .custom)
    }

    func category(_ key: String?) -> RemoteCategory? {
        guard let key else { return nil }
        return categories.first { $0.key == key }
    }
}

/// Body of `POST /categories` and `PATCH /categories/:id`.
struct CategoryInput: Encodable {
    var name: String
    var icon: String
    var color: String
    var group: String
}

// MARK: - Trips

/// Purpose of a trip. The plan decides which ones are allowed; the API enforces that.
enum TripPurpose: String, CaseIterable, Identifiable {
    case personal = "private"
    case business
    case commute

    var id: String { rawValue }

    var label: String {
        switch self {
        case .personal: String(localized: "Privat")
        case .business: String(localized: "Dienstlich")
        case .commute: String(localized: "Arbeitsweg")
        }
    }

    var symbol: String {
        switch self {
        case .personal: "house.fill"
        case .business: "briefcase.fill"
        case .commute: "building.2.fill"
        }
    }
}

/// Trip from `GET /trips/:id` and `GET /vehicles/:id/trips`.
struct RemoteTrip: Decodable, Identifiable {
    let id: String
    let startedAt: Date?
    let odometerStart: Double?
    let odometerEnd: Double?
    let distanceKm: Double?
    let startPlace: String?
    let endPlace: String?
    let purpose: String
    let note: String?
    let createdBy: String?
    let createdByName: String?

    enum CodingKeys: String, CodingKey {
        case id, purpose, note
        case startedAt = "started_at"
        case odometerStart = "odometer_start"
        case odometerEnd = "odometer_end"
        case distanceKm = "distance_km"
        case startPlace = "start_place"
        case endPlace = "end_place"
        case createdBy = "created_by"
        case createdByName = "created_by_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        startedAt = c.text(.startedAt).flatMap(APIDate.parse)
        odometerStart = c.number(.odometerStart)
        odometerEnd = c.number(.odometerEnd)
        distanceKm = c.number(.distanceKm)
        startPlace = c.text(.startPlace)
        endPlace = c.text(.endPlace)
        purpose = c.text(.purpose) ?? TripPurpose.personal.rawValue
        note = c.text(.note)
        createdBy = c.text(.createdBy)
        createdByName = c.text(.createdByName)
    }

    /// "Bolbingen → Aalen", or only the place that is known.
    var route: String? {
        let places = [startPlace, endPlace].compactMap { $0 }
        return places.isEmpty ? nil : places.joined(separator: " → ")
    }
}

/// Body of `POST /trips` and `PATCH /trips/:id`. The API derives the distance from start and end.
struct TripInput: Encodable {
    var vehicleId: String
    var startedAt: Date
    /// nil: the start is unknown and `distanceKm` is sent instead.
    var odometerStart: Int?
    var odometerEnd: Int
    var distanceKm: Double?
    var startPlace: String?
    var endPlace: String?
    var purpose: String
    var note: String?
    /// true for PATCH.
    var sendsNulls = false

    enum CodingKeys: String, CodingKey {
        case vehicleId, startedAt, odometerStart, odometerEnd, distanceKm, startPlace, endPlace, purpose, note
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !sendsNulls { try c.encode(vehicleId, forKey: .vehicleId) }
        try c.encode(ISO8601DateFormatter().string(from: startedAt), forKey: .startedAt)
        try c.encode(odometerEnd, forKey: .odometerEnd)
        try c.encode(purpose, forKey: .purpose)
        func put<T: Encodable>(_ value: T?, _ key: CodingKeys) throws {
            if let value {
                try c.encode(value, forKey: key)
            } else if sendsNulls {
                try c.encodeNil(forKey: key)
            }
        }
        try put(odometerStart, .odometerStart)
        try c.encodeIfPresent(distanceKm, forKey: .distanceKm)
        try put(startPlace, .startPlace)
        try put(endPlace, .endPlace)
        try put(note, .note)
    }
}

/// Response of `GET /vehicles/:id/trips`: a page of trips plus the months on it and all years with trips.
struct TripsPage: Decodable {
    struct Month: Decodable {
        /// `YYYY-MM`
        let month: String
        let count: Int
        let km: Double
    }

    let trips: [RemoteTrip]
    let hasMore: Bool
    let months: [Month]
    let years: [Int]

    enum CodingKeys: String, CodingKey { case data, pagination, months, years }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trips = try c.decode([Lossy<RemoteTrip>].self, forKey: .data).compactMap(\.value)
        hasMore = (try? c.decode(Page<RemoteTrip>.Pagination.self, forKey: .pagination))?.hasMore ?? false
        months = (try? c.decodeIfPresent([Month].self, forKey: .months)) ?? []
        years = (try? c.decodeIfPresent([Int].self, forKey: .years)) ?? []
    }
}

/// Response of `GET /vehicles/:id/trips/summary`; all figures are calculated by the API.
struct TripSummary: Decodable {
    struct PurposeTotal: Decodable {
        let km: Double
        let count: Int
        /// Costs per km × distance, nil while the costs per km are unknown.
        let estimatedCost: Double?
    }

    struct Month: Decodable, Identifiable {
        /// `YYYY-MM`
        let month: String
        let km: [String: Double]

        var id: String { month }

        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            month = (try? c.decode(String.self, forKey: Key(stringValue: "month")!)) ?? ""
            var km: [String: Double] = [:]
            for key in c.allKeys where key.stringValue != "month" {
                if let value = try? c.decode(Double.self, forKey: key) { km[key.stringValue] = value }
            }
            self.km = km
        }
    }

    let count: Int
    let totalKm: Double
    let byPurpose: [String: PurposeTotal]
    /// Share of business trips in percent.
    let businessShare: Double?
    let costPerKm: Double?
    let months: [Month]
    /// Purposes the user's plan allows for new trips.
    let allowedPurposes: [String]
    let canExport: Bool

    enum CodingKeys: String, CodingKey {
        case count, totalKm, byPurpose, businessShare, costPerKm, months, allowedPurposes, canExport
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = c.number(.count).map { Int($0) } ?? 0
        totalKm = c.number(.totalKm) ?? 0
        byPurpose = (try? c.decodeIfPresent([String: PurposeTotal].self, forKey: .byPurpose)) ?? [:]
        businessShare = c.number(.businessShare)
        costPerKm = c.number(.costPerKm)
        months = (try? c.decodeIfPresent([Month].self, forKey: .months)) ?? []
        allowedPurposes = (try? c.decodeIfPresent([String].self, forKey: .allowedPurposes))
            ?? TripPurpose.allCases.map(\.rawValue)
        canExport = (try? c.decodeIfPresent(Bool.self, forKey: .canExport)) ?? false
    }
}

// MARK: - Sharing

/// The signed-in user's role for a vehicle. The API decides what each role may do.
enum VehicleRole: String {
    case owner, editor, viewer

    var label: String {
        switch self {
        case .owner: String(localized: "Besitzer")
        case .editor: String(localized: "Mitfahrer")
        case .viewer: String(localized: "Nur ansehen")
        }
    }

    /// Whether the app offers to record entries at all; the API has the last word.
    var canRecord: Bool { self != .viewer }
}

/// Response of `GET /vehicles/:id/members`.
struct VehicleMembers: Decodable {
    struct Member: Decodable, Identifiable {
        let userID: String
        let name: String
        let email: String?
        let role: String

        var id: String { userID }

        enum CodingKeys: String, CodingKey {
            case name, email, role
            case userID = "user_id"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            userID = try c.decode(String.self, forKey: .userID)
            email = c.text(.email)
            name = c.text(.name) ?? email ?? ""
            role = c.text(.role) ?? VehicleRole.viewer.rawValue
        }
    }

    /// Open invitation as the owner sees it.
    struct Invitation: Decodable, Identifiable {
        let id: String
        let email: String
        let role: String
        let expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, email, role
            case expiresAt = "expires_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            email = c.text(.email) ?? ""
            role = c.text(.role) ?? VehicleRole.viewer.rawValue
            expiresAt = c.text(.expiresAt).flatMap(APIDate.parse)
        }
    }

    /// The signed-in user's own role.
    let role: String
    let owner: Member?
    let members: [Member]
    /// Only delivered to the owner.
    let invitations: [Invitation]

    enum CodingKeys: String, CodingKey { case role, owner, members, invitations }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = c.text(.role) ?? VehicleRole.viewer.rawValue
        owner = try? c.decodeIfPresent(Member.self, forKey: .owner)
        members = (try? c.decodeIfPresent([Member].self, forKey: .members)) ?? []
        invitations = (try? c.decodeIfPresent([Invitation].self, forKey: .invitations)) ?? []
    }
}

/// Body of `POST /vehicles/:id/invitations` and `PATCH …/members/:userId`.
struct MemberRoleInput: Encodable {
    var email: String?
    var role: String
}

/// Invitation to someone else's vehicle, from `GET /invitations`.
struct PendingInvitation: Decodable, Identifiable {
    let id: String
    let vehicleName: String
    let role: String
    let invitedByName: String?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, role
        case vehicleName = "vehicle_name"
        case invitedByName = "invited_by_name"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        vehicleName = c.text(.vehicleName) ?? ""
        role = c.text(.role) ?? VehicleRole.viewer.rawValue
        invitedByName = c.text(.invitedByName)
        expiresAt = c.text(.expiresAt).flatMap(APIDate.parse)
    }
}

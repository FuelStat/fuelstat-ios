import Foundation

/// Response of `GET /vehicles/:id/costs?year=` (FuelStat/fuelstat#124, #140): totals, cost per km, months and
/// categories. Calculated by the API; months and years are in Europe/Berlin.
public struct VehicleCosts: Decodable, Equatable, Sendable {
    /// Costs of fuelling/charging (`energy`), of expenses that count as costs (`expenses`) and both (`total`).
    public struct Sums: Equatable, Sendable {
        public let energy: Double
        public let expenses: Double
        public let total: Double
    }

    public struct Month: Equatable, Sendable, Identifiable {
        /// `2026-02`
        public let month: String
        public let sums: Sums
        public let count: Int
        /// Costs per category key (`Versicherung`, `Tankfuellung:l` …).
        public let byCategory: [String: Double]
        public var id: String { month }
    }

    public struct Category: Equatable, Sendable, Identifiable {
        public let key: String
        public let total: Double
        public let count: Int
        public var id: String { key }
    }

    /// Energy costs of one energy in the period.
    public struct EnergyCost: Equatable, Sendable, Identifiable {
        public let energy: String
        public let name: String
        public let total: Double
        public let count: Int
        /// Share of the energy costs in percent.
        public let share: Double?
        public var id: String { energy }
    }

    public let year: Int?
    public let currency: String
    public let total: Sums
    public let distanceKm: Double?
    /// € per km for fuelling/charging only; nil without a distance.
    public let costPerKmEnergy: Double?
    /// € per km for all costs; nil without a distance.
    public let costPerKmTotal: Double?
    public let perMonth: Double?
    public let monthCount: Int
    public let currentMonth: Month?
    public let previousMonth: Month?
    /// Months with entries, latest first.
    public let months: [Month]
    /// Sum and count per category, the biggest first.
    public let categories: [Category]
    public let energies: [EnergyCost]
    /// Years with costs (whole period, independent of `year`), latest first.
    public let years: [Int]

    enum CodingKeys: String, CodingKey {
        case year, currency, total, distanceKm, costPerKm, perMonth, monthCount, currentMonth, previousMonth
        case months, categories, energies, years
    }

    private enum CostPerKmKeys: String, CodingKey { case energy, total }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = c.lenientInt(.year)
        currency = c.lenientText(.currency) ?? "EUR"
        total = (try? c.decodeIfPresent(Sums.self, forKey: .total)) ?? Sums(energy: 0, expenses: 0, total: 0)
        distanceKm = c.lenientNumber(.distanceKm)
        if let perKm = try? c.nestedContainer(keyedBy: CostPerKmKeys.self, forKey: .costPerKm) {
            costPerKmEnergy = perKm.lenientNumber(.energy)
            costPerKmTotal = perKm.lenientNumber(.total)
        } else {
            costPerKmEnergy = nil
            costPerKmTotal = nil
        }
        perMonth = c.lenientNumber(.perMonth)
        monthCount = c.lenientInt(.monthCount) ?? 0
        currentMonth = (try? c.decodeIfPresent(Month.self, forKey: .currentMonth)) ?? nil
        previousMonth = (try? c.decodeIfPresent(Month.self, forKey: .previousMonth)) ?? nil
        months = c.lenientList(.months, of: Month.self)
        categories = c.lenientList(.categories, of: Category.self)
        energies = c.lenientList(.energies, of: EnergyCost.self)
        years = c.lenientList(.years, of: Int.self)
    }
}

// MARK: - Decoding

extension VehicleCosts.Sums: Decodable {
    enum CodingKeys: String, CodingKey { case energy, expenses, total }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energy = c.lenientNumber(.energy) ?? 0
        expenses = c.lenientNumber(.expenses) ?? 0
        total = c.lenientNumber(.total) ?? 0
    }
}

extension VehicleCosts.Month: Decodable {
    enum CodingKeys: String, CodingKey { case month, count, byCategory }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let month = c.lenientText(.month) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "month"))
        }
        self.month = month
        sums = try VehicleCosts.Sums(from: decoder)
        count = c.lenientInt(.count) ?? 0
        // Values may be strings, so read the dictionary entry by entry.
        let raw = c.lenientDictionary(.byCategory, of: LenientNumber.self)
        byCategory = raw.compactMapValues(\.value)
    }
}

extension VehicleCosts.Category: Decodable {
    enum CodingKeys: String, CodingKey { case key, total, count }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = c.lenientText(.key) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "key"))
        }
        self.key = key
        total = c.lenientNumber(.total) ?? 0
        count = c.lenientInt(.count) ?? 0
    }
}

extension VehicleCosts.EnergyCost: Decodable {
    enum CodingKeys: String, CodingKey { case energy, name, total, count, share }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let energy = c.lenientText(.energy) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "energy"))
        }
        self.energy = energy
        name = c.lenientText(.name) ?? energy
        total = c.lenientNumber(.total) ?? 0
        count = c.lenientInt(.count) ?? 0
        share = c.lenientNumber(.share)
    }
}

/// A number sent as a number or a string, for dictionary values.
private struct LenientNumber: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let number = try? single.decode(Double.self) {
            value = number
        } else if let text = try? single.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }
}

// MARK: - Category keys and months

/// Keys in `/costs` `categories` and `byCategory`: fuelling and charging are `Tankfuellung:<unit>`
/// (`Tankfuellung:l`, `Tankfuellung:kwh`, `Tankfuellung:kg`), everything else is the category's name.
public struct CostCategoryKey: Equatable, Hashable, Sendable {
    public static let fuelling = "Tankfuellung"

    public let base: String
    /// `l`, `kwh` or `kg` for fuelling and charging.
    public let unit: String?

    public init(_ key: String) {
        if let range = key.range(of: Self.fuelling + ":") , range.lowerBound == key.startIndex {
            base = Self.fuelling
            unit = String(key[range.upperBound...])
        } else {
            base = key
            unit = nil
        }
    }

    public var isFuelling: Bool { base == Self.fuelling }
}

/// Months and periods as the API names them (`2026-05`, `2026`).
public enum PeriodKey {
    /// First day of a `YYYY-MM` month in the Europe/Berlin time zone, for chart axes.
    public static func monthStart(_ month: String) -> Date? {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1, hour: 12))
    }
}

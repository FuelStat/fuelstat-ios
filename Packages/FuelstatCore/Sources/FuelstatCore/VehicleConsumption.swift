import Foundation

/// Response of `GET /vehicles/:id/consumption` (FuelStat/fuelstat#82, #140, #156): consumption, amounts, CO₂ and
/// prices per energy. Everything is calculated by the API; the app only shows it.
public struct VehicleConsumption: Decodable, Equatable, Sendable {
    /// Main figure of the vehicle, set by the API (#156).
    public struct Primary: Equatable, Sendable {
        public enum Metric: String, Sendable { case costPer100km, consumption }
        public let metric: Metric
        /// `eur_per_100km`, `l`, `kwh` or `kg`
        public let unit: String?
        public let value: Double?
    }

    /// Consumption of one energy (or one unit on older servers).
    public struct Energy: Equatable, Sendable {
        public let unit: String
        public let energy: String?
        public let name: String?
        /// Share of the energy costs in percent.
        public let costShare: Double?
        /// Fuelled only on the side: no consumption figure to show.
        public let minor: Bool
        public let average: Double?
        public let minimum: Double?
        public let maximum: Double?
        public let kmConsumed: Double?
        public let amountConsumed: Double?
        public let amountBought: Double?
        public let cost: Double?
        public let averagePrice: Double?
        public let fillCount: Int?
        public let co2: CO2?
        public let months: [Month]
        public let years: [Year]
    }

    public struct CO2: Equatable, Sendable {
        public let factor: Double?
        public let totalKg: Double?
        public let gramsPerKm: Double?
    }

    public struct Month: Equatable, Sendable, Identifiable {
        /// `2026-01`
        public let month: String
        public let km: Double?
        public let amount: Double?
        public let consumption: Double?
        public var id: String { month }
    }

    public struct Year: Equatable, Sendable, Identifiable {
        public let year: Int
        public let fillCount: Int?
        public let amountBought: Double?
        public let cost: Double?
        public let amountConsumed: Double?
        public let kmConsumed: Double?
        public let consumption: Double?
        public let co2Kg: Double?
        public var id: Int { year }
    }

    /// A fuel grade (Sorte) with its price and, for premium grades, the surcharge (#140).
    public struct FuelPrice: Equatable, Sendable, Identifiable {
        public struct Markup: Equatable, Sendable {
            public let perUnit: Double?
            public let percent: Double?
            public let basePrice: Double?
        }

        public let fuel: String
        public let name: String
        public let energy: String?
        public let unit: String
        public let premium: Bool
        public let fillCount: Int?
        public let amount: Double?
        public let cost: Double?
        public let averagePrice: Double?
        public let shareOfEnergy: Double?
        public let markup: Markup?
        public var id: String { fuel }
    }

    /// Energy cost per 100 km of a month or year (#156); nil without a distance.
    public struct CostRate: Equatable, Sendable, Identifiable {
        /// `2026-05` or `2026`
        public let period: String
        public let cost: Double?
        public let distanceKm: Double?
        public let costPer100km: Double?
        public var id: String { period }
    }

    public struct CostRates: Equatable, Sendable {
        public let months: [CostRate]
        public let years: [CostRate]
        public let best: CostRate?
        public let worst: CostRate?
        public let minPeriodKm: Int?
    }

    public let fuelType: String?
    /// Units with entries, the one fitting the drive type first.
    public let units: [String]
    /// Energies with entries, the default one first (#140); empty on older servers.
    public let energyKeys: [String]
    public let byEnergy: [String: Energy]
    /// One entry per unit; the only breakdown older servers send.
    public let byUnit: [String: Energy]
    public let byFuel: [FuelPrice]
    public let costPer100km: Double?
    public let primary: Primary?
    public let costRates: CostRates?
    public let energyCost: Double?
    /// Share of the charging costs in the energy costs in percent, with several units only.
    public let electricShare: Double?
    public let co2: CO2?

    enum CodingKeys: String, CodingKey {
        case fuelType, units, energies, byEnergy, byUnit, byFuel, costPer100km, primary
        case costPer100kmPeriods, energyCost, electricShare, co2
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fuelType = c.lenientText(.fuelType)
        units = c.lenientList(.units, of: String.self)
        energyKeys = c.lenientList(.energies, of: String.self)
        byEnergy = c.lenientDictionary(.byEnergy, of: Energy.self)
        byUnit = c.lenientDictionary(.byUnit, of: Energy.self)
        byFuel = c.lenientDictionary(.byFuel, of: FuelPrice.self).values
            .sorted { ($0.amount ?? 0, $1.fuel) > ($1.amount ?? 0, $0.fuel) }
        costPer100km = c.lenientNumber(.costPer100km)
        primary = (try? c.decodeIfPresent(Primary.self, forKey: .primary)) ?? nil
        costRates = (try? c.decodeIfPresent(CostRates.self, forKey: .costPer100kmPeriods)) ?? nil
        energyCost = c.lenientNumber(.energyCost)
        electricShare = c.lenientNumber(.electricShare)
        co2 = (try? c.decodeIfPresent(CO2.self, forKey: .co2)) ?? nil
    }

    /// The breakdown to show: per energy when the server has it, otherwise per unit. The order puts the vehicle's
    /// main energy first; energies the API lists but sends no figures for are left out.
    public var breakdown: [(key: String, figures: Energy)] {
        if !byEnergy.isEmpty {
            let ordered = energyKeys.filter { byEnergy[$0] != nil } + byEnergy.keys.filter { !energyKeys.contains($0) }.sorted()
            return ordered.compactMap { key in byEnergy[key].map { (key, $0) } }
        }
        let ordered = units.filter { byUnit[$0] != nil } + byUnit.keys.filter { !units.contains($0) }.sorted()
        return ordered.compactMap { key in byUnit[key].map { (key, $0) } }
    }
}

// MARK: - Decoding

extension VehicleConsumption.Primary: Decodable {
    enum CodingKeys: String, CodingKey { case metric, unit, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let metric = c.lenientText(.metric).flatMap(Metric.init(rawValue:)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "metric"))
        }
        self.metric = metric
        unit = c.lenientText(.unit)
        value = c.lenientNumber(.value)
    }
}

extension VehicleConsumption.CO2: Decodable {
    enum CodingKeys: String, CodingKey { case factor, totalKg, gPerKm }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        factor = c.lenientNumber(.factor)
        totalKg = c.lenientNumber(.totalKg)
        gramsPerKm = c.lenientNumber(.gPerKm)
    }
}

extension VehicleConsumption.Month: Decodable {
    enum CodingKeys: String, CodingKey { case month, km, amount, consumption }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let month = c.lenientText(.month) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "month"))
        }
        self.month = month
        km = c.lenientNumber(.km)
        amount = c.lenientNumber(.amount)
        consumption = c.lenientNumber(.consumption)
    }
}

extension VehicleConsumption.Year: Decodable {
    enum CodingKeys: String, CodingKey {
        case year, fillCount, amountBought, cost, amountConsumed, kmConsumed, consumption, co2Kg
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let year = c.lenientInt(.year) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "year"))
        }
        self.year = year
        fillCount = c.lenientInt(.fillCount)
        amountBought = c.lenientNumber(.amountBought)
        cost = c.lenientNumber(.cost)
        amountConsumed = c.lenientNumber(.amountConsumed)
        kmConsumed = c.lenientNumber(.kmConsumed)
        consumption = c.lenientNumber(.consumption)
        co2Kg = c.lenientNumber(.co2Kg)
    }
}

extension VehicleConsumption.Energy: Decodable {
    enum CodingKeys: String, CodingKey {
        case unit, energy, name, costShare, minor, avg, min, max, kmConsumed, amountConsumed, amountBought, cost
        case avgPrice, fillCount, co2, months, years
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unit = c.lenientText(.unit) ?? "l"
        energy = c.lenientText(.energy)
        name = c.lenientText(.name)
        costShare = c.lenientNumber(.costShare)
        minor = c.lenientBool(.minor) ?? false
        average = c.lenientNumber(.avg)
        minimum = c.lenientNumber(.min)
        maximum = c.lenientNumber(.max)
        kmConsumed = c.lenientNumber(.kmConsumed)
        amountConsumed = c.lenientNumber(.amountConsumed)
        amountBought = c.lenientNumber(.amountBought)
        cost = c.lenientNumber(.cost)
        averagePrice = c.lenientNumber(.avgPrice)
        fillCount = c.lenientInt(.fillCount)
        co2 = (try? c.decodeIfPresent(VehicleConsumption.CO2.self, forKey: .co2)) ?? nil
        months = c.lenientList(.months, of: VehicleConsumption.Month.self)
        years = c.lenientList(.years, of: VehicleConsumption.Year.self)
    }
}

extension VehicleConsumption.FuelPrice.Markup: Decodable {
    enum CodingKeys: String, CodingKey { case perUnit, percent, basePrice }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        perUnit = c.lenientNumber(.perUnit)
        percent = c.lenientNumber(.percent)
        basePrice = c.lenientNumber(.basePrice)
    }
}

extension VehicleConsumption.FuelPrice: Decodable {
    enum CodingKeys: String, CodingKey {
        case fuel, name, energy, unit, premium, fillCount, amount, cost, avgPrice, shareOfEnergy, markup
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let fuel = c.lenientText(.fuel) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "fuel"))
        }
        self.fuel = fuel
        name = c.lenientText(.name) ?? fuel
        energy = c.lenientText(.energy)
        unit = c.lenientText(.unit) ?? "l"
        premium = c.lenientBool(.premium) ?? false
        fillCount = c.lenientInt(.fillCount)
        amount = c.lenientNumber(.amount)
        cost = c.lenientNumber(.cost)
        averagePrice = c.lenientNumber(.avgPrice)
        shareOfEnergy = c.lenientNumber(.shareOfEnergy)
        markup = (try? c.decodeIfPresent(Markup.self, forKey: .markup)) ?? nil
    }
}

extension VehicleConsumption.CostRate: Decodable {
    enum CodingKeys: String, CodingKey { case period, cost, distanceKm, costPer100km }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let period = c.lenientText(.period) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "period"))
        }
        self.period = period
        cost = c.lenientNumber(.cost)
        distanceKm = c.lenientNumber(.distanceKm)
        costPer100km = c.lenientNumber(.costPer100km)
    }
}

extension VehicleConsumption.CostRates: Decodable {
    enum CodingKeys: String, CodingKey { case months, years, best, worst, minPeriodKm }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        months = c.lenientList(.months, of: VehicleConsumption.CostRate.self)
        years = c.lenientList(.years, of: VehicleConsumption.CostRate.self)
        best = (try? c.decodeIfPresent(VehicleConsumption.CostRate.self, forKey: .best)) ?? nil
        worst = (try? c.decodeIfPresent(VehicleConsumption.CostRate.self, forKey: .worst)) ?? nil
        minPeriodKm = c.lenientInt(.minPeriodKm)
    }
}

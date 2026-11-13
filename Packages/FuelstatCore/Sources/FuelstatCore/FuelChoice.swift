import Foundation

/// A fuel type (Sorte) as `GET /fuels` delivers it (FuelStat/fuelstat#140), e.g. Super E5, Autogas or Strom.
public struct FuelOption: Equatable, Hashable, Sendable, Identifiable {
    public let key: String
    public let name: String
    /// Energy the consumption is calculated for, e.g. `petrol` for E5, E10 and Super Plus.
    public let energy: String
    /// `l`, `kg` or `kwh`
    public let unit: String
    /// Fuel type for the Tankerkönig price search (`e5`, `e10`, `diesel`), nil when there are no prices.
    public let tankerkoenig: String?

    public var id: String { key }
    public var isCharging: Bool { unit == "kwh" }

    public init(key: String, name: String, energy: String, unit: String, tankerkoenig: String?) {
        self.key = key
        self.name = name
        self.energy = energy
        self.unit = unit
        self.tankerkoenig = tankerkoenig
    }
}

/// Which fuel types an entry can have, from the vehicle's list (`fuels`, `default_fuel`) and the server's catalog.
/// The vehicle and the catalog come from the API; this only picks from them.
public enum FuelChoice {
    /// Fuels of the vehicle for fuelling (everything but kWh) or charging (kWh), in the vehicle's order.
    /// Keys the catalog does not know are left out.
    public static func options(vehicleFuels: [String], catalog: [FuelOption], charging: Bool) -> [FuelOption] {
        vehicleFuels.compactMap { key in catalog.first { $0.key == key } }.filter { $0.isCharging == charging }
    }

    /// The fuel selected when the sheet opens: the vehicle's default if it fits, otherwise the first option.
    public static func preselected(_ options: [FuelOption], defaultFuel: String?) -> FuelOption? {
        options.first { $0.key == defaultFuel } ?? options.first
    }

    /// Whether the vehicle can be fuelled and/or charged.
    public static func modes(vehicleFuels: [String], catalog: [FuelOption]) -> (fuel: Bool, charge: Bool) {
        let known = vehicleFuels.compactMap { key in catalog.first { $0.key == key } }
        return (known.contains { !$0.isCharging }, known.contains { $0.isCharging })
    }
}

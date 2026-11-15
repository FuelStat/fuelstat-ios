import Foundation

/// Status of a vehicle (FuelStat/fuelstat#79): sold and decommissioned vehicles are archived. Archived vehicles stay
/// readable but the API refuses every change (409 `vehicle_archived`). The status is never guessed from other fields:
/// a vehicle with a sale date stays active until its owner archives it.
public enum VehicleStatus: String, Equatable, Sendable, CaseIterable {
    case active
    case sold
    case decommissioned

    /// Servers before 0.13.0 send no status, and a status the app does not know is treated as active, so a vehicle
    /// never disappears from the lists because of a value this app version cannot read.
    public init(api value: String?) {
        self = value.flatMap(Self.init(rawValue:)) ?? .active
    }

    public var isArchived: Bool { self != .active }
}

/// Body of `PATCH /vehicles/:id` that archives or reactivates a vehicle. Only the fields of the chosen status are
/// sent; the API fills a missing date with today.
public struct VehicleStatusChange: Encodable, Equatable, Sendable {
    public var status: VehicleStatus
    /// `YYYY-MM-DD`
    public var saleDate: String?
    public var saleOdometerKm: Int?
    public var salePrice: Double?
    /// `YYYY-MM-DD`
    public var decommissionedFrom: String?
    /// "Abgemeldet bis", `YYYY-MM-DD`; only an indication, the vehicle never becomes active by itself.
    public var decommissionedUntil: String?

    public static func sold(date: String?, odometerKm: Int?, price: Double?) -> Self {
        .init(status: .sold, saleDate: date, saleOdometerKm: odometerKm, salePrice: price)
    }

    public static func decommissioned(from: String?, until: String?) -> Self {
        .init(status: .decommissioned, decommissionedFrom: from, decommissionedUntil: until)
    }

    public static var reactivated: Self { .init(status: .active) }

    enum CodingKeys: String, CodingKey {
        case status, saleDate, saleOdometerKm, salePrice, decommissionedFrom, decommissionedUntil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(saleDate, forKey: .saleDate)
        try c.encodeIfPresent(saleOdometerKm, forKey: .saleOdometerKm)
        try c.encodeIfPresent(salePrice, forKey: .salePrice)
        try c.encodeIfPresent(decommissionedFrom, forKey: .decommissionedFrom)
        try c.encodeIfPresent(decommissionedUntil, forKey: .decommissionedUntil)
    }
}

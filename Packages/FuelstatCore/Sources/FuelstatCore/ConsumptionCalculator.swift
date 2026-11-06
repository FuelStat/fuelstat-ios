import Foundation

/// A single refuelling or charging event, independent of persistence.
public struct FillUp: Equatable, Sendable {
    public var date: Date
    /// Odometer reading in kilometres.
    public var odometer: Double
    /// Volume in litres (or kWh for electric vehicles).
    public var volume: Double
    /// Total price paid.
    public var totalCost: Double
    /// Whether the tank was filled completely (required for consumption calculation).
    public var isFullTank: Bool

    public init(date: Date, odometer: Double, volume: Double, totalCost: Double, isFullTank: Bool = true) {
        self.date = date
        self.odometer = odometer
        self.volume = volume
        self.totalCost = totalCost
        self.isFullTank = isFullTank
    }

    public var pricePerUnit: Double? {
        volume > 0 ? totalCost / volume : nil
    }
}

/// Consumption between two full-tank fill-ups.
public struct ConsumptionSegment: Equatable, Sendable {
    public var startOdometer: Double
    public var endOdometer: Double
    public var volume: Double
    public var cost: Double

    public var distance: Double { endOdometer - startOdometer }
    /// Volume per 100 km.
    public var consumption: Double { volume / distance * 100 }
    public var costPerKilometre: Double { cost / distance }
}

public struct ConsumptionStats: Equatable, Sendable {
    public var fillUpCount: Int
    public var totalCost: Double
    public var totalVolume: Double
    /// Distance between the lowest and highest odometer reading.
    public var trackedDistance: Double
    /// Average consumption (volume per 100 km) across all complete full-tank segments.
    public var averageConsumption: Double?
    /// Average cost per kilometre across all complete full-tank segments.
    public var costPerKilometre: Double?
    public var averagePricePerUnit: Double?
    public var segments: [ConsumptionSegment]

    public static let empty = ConsumptionStats(
        fillUpCount: 0, totalCost: 0, totalVolume: 0, trackedDistance: 0,
        averageConsumption: nil, costPerKilometre: nil, averagePricePerUnit: nil, segments: []
    )
}

public enum ConsumptionCalculator {
    /// Computes statistics using the full-tank method: consumption is only measured
    /// between two full fill-ups; partial fill-ups in between are added to the next segment.
    public static func stats(for fillUps: [FillUp]) -> ConsumptionStats {
        guard !fillUps.isEmpty else { return .empty }

        let sorted = fillUps.sorted { ($0.odometer, $0.date) < ($1.odometer, $1.date) }
        let totalCost = sorted.reduce(0) { $0 + $1.totalCost }
        let totalVolume = sorted.reduce(0) { $0 + $1.volume }
        let trackedDistance = (sorted.last!.odometer - sorted.first!.odometer)

        var segments: [ConsumptionSegment] = []
        var lastFullOdometer: Double?
        var pendingVolume = 0.0
        var pendingCost = 0.0

        for fillUp in sorted {
            if let start = lastFullOdometer {
                pendingVolume += fillUp.volume
                pendingCost += fillUp.totalCost
                if fillUp.isFullTank {
                    if fillUp.odometer > start {
                        segments.append(ConsumptionSegment(
                            startOdometer: start, endOdometer: fillUp.odometer,
                            volume: pendingVolume, cost: pendingCost
                        ))
                    }
                    lastFullOdometer = fillUp.odometer
                    pendingVolume = 0
                    pendingCost = 0
                }
            } else if fillUp.isFullTank {
                // First full tank establishes the baseline; its volume belongs to earlier driving.
                lastFullOdometer = fillUp.odometer
            }
        }

        let segmentDistance = segments.reduce(0) { $0 + $1.distance }
        let segmentVolume = segments.reduce(0) { $0 + $1.volume }
        let segmentCost = segments.reduce(0) { $0 + $1.cost }

        return ConsumptionStats(
            fillUpCount: sorted.count,
            totalCost: totalCost,
            totalVolume: totalVolume,
            trackedDistance: trackedDistance,
            averageConsumption: segmentDistance > 0 ? segmentVolume / segmentDistance * 100 : nil,
            costPerKilometre: segmentDistance > 0 ? segmentCost / segmentDistance : nil,
            averagePricePerUnit: totalVolume > 0 ? totalCost / totalVolume : nil,
            segments: segments
        )
    }
}

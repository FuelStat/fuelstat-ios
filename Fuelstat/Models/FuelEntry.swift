import Foundation
import FuelstatCore
import SwiftData

@Model
final class FuelEntry {
    var date: Date
    /// Odometer reading in km.
    var odometer: Double
    /// Litres or kWh.
    var volume: Double
    var totalCost: Double
    var isFullTank: Bool
    var note: String
    var vehicle: Vehicle?

    init(date: Date, odometer: Double, volume: Double, totalCost: Double, isFullTank: Bool, note: String = "") {
        self.date = date
        self.odometer = odometer
        self.volume = volume
        self.totalCost = totalCost
        self.isFullTank = isFullTank
        self.note = note
    }

    var fillUp: FillUp {
        FillUp(date: date, odometer: odometer, volume: volume, totalCost: totalCost, isFullTank: isFullTank)
    }
}

extension Vehicle {
    var stats: ConsumptionStats {
        ConsumptionCalculator.stats(for: entries.map(\.fillUp))
    }

    var latestOdometer: Double? {
        entries.map(\.odometer).max()
    }
}

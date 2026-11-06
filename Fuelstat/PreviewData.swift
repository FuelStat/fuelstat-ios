#if DEBUG
import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Vehicle.self, FuelEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(vehicle)
        return container
    }()

    static let vehicle: Vehicle = {
        let vehicle = Vehicle(name: "Golf", fuelType: .petrol)
        let day: TimeInterval = 86_400
        let samples: [(Double, Double, Double, Bool)] = [
            (12_000, 42.1, 74.50, true),
            (12_640, 39.8, 70.20, true),
            (13_050, 15.0, 27.10, false),
            (13_310, 26.4, 47.30, true),
        ]
        vehicle.entries = samples.enumerated().map { index, sample in
            FuelEntry(
                date: .now.addingTimeInterval(Double(index - samples.count) * 14 * day),
                odometer: sample.0, volume: sample.1, totalCost: sample.2, isFullTank: sample.3
            )
        }
        return vehicle
    }()
}
#endif

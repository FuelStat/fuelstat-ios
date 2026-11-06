import SwiftData
import SwiftUI

@main
struct FuelstatApp: App {
    var body: some Scene {
        WindowGroup {
            VehicleListView()
        }
        .modelContainer(for: [Vehicle.self, FuelEntry.self])
    }
}

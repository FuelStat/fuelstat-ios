import Foundation
import SwiftData

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case petrol, diesel, lpg, electric

    var id: String { rawValue }

    var label: String {
        switch self {
        case .petrol: "Benzin"
        case .diesel: "Diesel"
        case .lpg: "Autogas (LPG)"
        case .electric: "Elektro"
        }
    }

    /// Unit of the refuelled volume.
    var unit: String { self == .electric ? "kWh" : "L" }

    var symbol: String { self == .electric ? "bolt.car" : "fuelpump" }
}

@Model
final class Vehicle {
    var name: String
    var fuelTypeRaw: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \FuelEntry.vehicle)
    var entries: [FuelEntry] = []

    init(name: String, fuelType: FuelType, createdAt: Date = .now) {
        self.name = name
        self.fuelTypeRaw = fuelType.rawValue
        self.createdAt = createdAt
    }

    var fuelType: FuelType {
        get { FuelType(rawValue: fuelTypeRaw) ?? .petrol }
        set { fuelTypeRaw = newValue.rawValue }
    }
}

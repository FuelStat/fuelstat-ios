import Testing
@testable import FuelstatCore

struct IntentVehicleTests {
    @Test func noVehicles() {
        #expect(IntentVehicleChoice.resolve(explicit: "a", available: [], remembered: ["a"]) == .none)
    }

    @Test func explicitVehicleWins() {
        #expect(IntentVehicleChoice.resolve(explicit: "b", available: ["a", "b"], remembered: ["a"]) == .vehicle("b"))
    }

    @Test func unknownExplicitVehicleAsks() {
        #expect(IntentVehicleChoice.resolve(explicit: "x", available: ["a", "b"], remembered: ["a"]) == .ask)
    }

    @Test func singleVehicleNeedsNoChoice() {
        #expect(IntentVehicleChoice.resolve(explicit: nil, available: ["a"], remembered: [nil]) == .vehicle("a"))
    }

    @Test func firstRememberedVehicleThatStillExists() {
        #expect(IntentVehicleChoice.resolve(explicit: nil, available: ["a", "b", "c"], remembered: ["gone", nil, "c", "b"])
            == .vehicle("c"))
    }

    @Test func asksWithoutDefault() {
        #expect(IntentVehicleChoice.resolve(explicit: nil, available: ["a", "b"], remembered: [nil, "gone"]) == .ask)
    }
}

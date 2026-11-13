import Testing
@testable import FuelstatCore

struct FuelChoiceTests {
    private let catalog = [
        FuelOption(key: "super_e5", name: "Super E5", energy: "petrol", unit: "l", tankerkoenig: "e5"),
        FuelOption(key: "super_e10", name: "Super E10", energy: "petrol", unit: "l", tankerkoenig: "e10"),
        FuelOption(key: "lpg", name: "Autogas", energy: "lpg", unit: "l", tankerkoenig: nil),
        FuelOption(key: "cng", name: "Erdgas", energy: "cng", unit: "kg", tankerkoenig: nil),
        FuelOption(key: "electricity", name: "Strom", energy: "electricity", unit: "kwh", tankerkoenig: nil),
    ]

    @Test func bivalentPetrolAndLPGOffersBothForFuelling() {
        let options = FuelChoice.options(vehicleFuels: ["super_e5", "lpg"], catalog: catalog, charging: false)
        #expect(options.map(\.key) == ["super_e5", "lpg"])
        #expect(FuelChoice.options(vehicleFuels: ["super_e5", "lpg"], catalog: catalog, charging: true).isEmpty)
    }

    @Test func petrolAndCNGMixUnits() {
        let options = FuelChoice.options(vehicleFuels: ["cng", "super_e10"], catalog: catalog, charging: false)
        #expect(options.map(\.unit) == ["kg", "l"])
    }

    @Test func plugInHybridSplitsFuellingAndCharging() {
        let fuels = ["super_e5", "electricity"]
        #expect(FuelChoice.options(vehicleFuels: fuels, catalog: catalog, charging: false).map(\.key) == ["super_e5"])
        #expect(FuelChoice.options(vehicleFuels: fuels, catalog: catalog, charging: true).map(\.key) == ["electricity"])
        #expect(FuelChoice.modes(vehicleFuels: fuels, catalog: catalog) == (true, true))
    }

    @Test func preselectsTheDefaultOrTheFirst() {
        let options = FuelChoice.options(vehicleFuels: ["super_e5", "lpg"], catalog: catalog, charging: false)
        #expect(FuelChoice.preselected(options, defaultFuel: "lpg")?.key == "lpg")
        #expect(FuelChoice.preselected(options, defaultFuel: "electricity")?.key == "super_e5")
        #expect(FuelChoice.preselected([], defaultFuel: "lpg") == nil)
    }

    @Test func unknownKeysAreIgnored() {
        #expect(FuelChoice.options(vehicleFuels: ["future_fuel", "lpg"], catalog: catalog, charging: false).map(\.key)
            == ["lpg"])
        #expect(FuelChoice.modes(vehicleFuels: ["future_fuel"], catalog: catalog) == (false, false))
    }
}

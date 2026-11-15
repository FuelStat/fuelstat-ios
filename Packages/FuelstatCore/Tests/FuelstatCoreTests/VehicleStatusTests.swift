import Foundation
import Testing
@testable import FuelstatCore

struct VehicleStatusTests {
    @Test func readsTheThreeStatuses() {
        #expect(VehicleStatus(api: "active") == .active)
        #expect(VehicleStatus(api: "sold") == .sold)
        #expect(VehicleStatus(api: "decommissioned") == .decommissioned)
    }

    @Test func missingOrUnknownStatusIsActive() {
        #expect(VehicleStatus(api: nil) == .active, "server before 0.13.0")
        #expect(VehicleStatus(api: "") == .active)
        #expect(VehicleStatus(api: "archived") == .active, "a value this app does not know must not hide the vehicle")
    }

    @Test func onlySoldAndDecommissionedAreArchived() {
        #expect(!VehicleStatus.active.isArchived)
        #expect(VehicleStatus.sold.isArchived)
        #expect(VehicleStatus.decommissioned.isArchived)
    }

    private func json(_ change: VehicleStatusChange) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(change), as: UTF8.self)
    }

    @Test func soldSendsTheSaleFieldsOnly() throws {
        let body = try json(.sold(date: "2026-11-01", odometerKm: 84500, price: 12500.5))
        #expect(body == #"{"saleDate":"2026-11-01","saleOdometerKm":84500,"salePrice":12500.5,"status":"sold"}"#)
    }

    @Test func soldWithoutDetailsLeavesThemToTheApi() throws {
        #expect(try json(.sold(date: nil, odometerKm: nil, price: nil)) == #"{"status":"sold"}"#)
    }

    @Test func decommissionedSendsThePeriodOnly() throws {
        let body = try json(.decommissioned(from: "2026-10-01", until: "2027-03-31"))
        #expect(body == #"{"decommissionedFrom":"2026-10-01","decommissionedUntil":"2027-03-31","status":"decommissioned"}"#)
        #expect(try json(.decommissioned(from: nil, until: nil)) == #"{"status":"decommissioned"}"#)
    }

    @Test func reactivatingSendsOnlyTheStatus() throws {
        #expect(try json(.reactivated) == #"{"status":"active"}"#)
    }
}

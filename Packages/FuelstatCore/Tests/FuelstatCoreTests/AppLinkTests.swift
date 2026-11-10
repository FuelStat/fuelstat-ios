import Foundation
import Testing
@testable import FuelstatCore

struct AppLinkTests {
    @Test(arguments: [
        AppLink.addEntry(kind: nil, vehicleID: nil),
        AppLink.addEntry(kind: "fuel", vehicleID: "3f2a-uuid"),
        AppLink.addEntry(kind: "charge", vehicleID: nil),
        AppLink.vehicle("3f2a-uuid"),
    ])
    func roundTrips(link: AppLink) {
        #expect(AppLink(url: link.url) == link)
    }

    @Test func urlsLookAsDocumented() {
        #expect(AppLink.vehicle("abc").url.absoluteString == "fuelstat://vehicle/abc")
        #expect(AppLink.addEntry(kind: "fuel", vehicleID: "abc").url.absoluteString
            == "fuelstat://add?kind=fuel&vehicle=abc")
    }

    @Test(arguments: ["https://tanken.1emc.de/vehicle/abc", "fuelstat://unknown", "fuelstat://vehicle",
                      "fuelstat://vehicle/", "fuelstat://add?kind=diesel"])
    func rejects(text: String) throws {
        #expect(AppLink(url: try #require(URL(string: text))) == nil)
    }
}

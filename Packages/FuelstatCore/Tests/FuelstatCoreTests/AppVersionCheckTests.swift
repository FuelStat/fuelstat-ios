import Foundation
import Testing
@testable import FuelstatCore

struct AppVersionCheckTests {
    @Test func comparesNumerically() {
        #expect(AppVersionCheck.compare("0.2.0", "0.10.0") == .orderedAscending)
        #expect(AppVersionCheck.compare("1.0.0", "0.99.99") == .orderedDescending)
        #expect(AppVersionCheck.compare("0.2.0", "0.2.0") == .orderedSame)
    }

    @Test func rejectsOtherFormats() {
        #expect(AppVersionCheck.compare("0.2", "0.2.0") == nil)
        #expect(AppVersionCheck.compare("0.2.0-beta", "0.2.0") == nil)
        #expect(AppVersionCheck.compare("a.b.c", "0.2.0") == nil)
    }

    @Test func noRequirementsMeansUpToDate() {
        #expect(AppVersionCheck.status(current: "0.1.0", minimum: nil, recommended: nil) == .upToDate)
    }

    @Test func belowMinimumRequiresAnUpdate() {
        #expect(AppVersionCheck.status(current: "0.1.0", minimum: "0.2.0", recommended: "0.3.0")
            == .updateRequired("0.2.0"))
    }

    @Test func belowRecommendedSuggestsAnUpdate() {
        #expect(AppVersionCheck.status(current: "0.2.0", minimum: "0.2.0", recommended: "0.3.0")
            == .updateRecommended("0.3.0"))
        #expect(AppVersionCheck.status(current: "0.3.0", minimum: "0.2.0", recommended: "0.3.0") == .upToDate)
    }

    @Test func unreadableVersionsAreIgnored() {
        #expect(AppVersionCheck.status(current: "dev", minimum: "0.2.0", recommended: nil) == .upToDate)
    }
}

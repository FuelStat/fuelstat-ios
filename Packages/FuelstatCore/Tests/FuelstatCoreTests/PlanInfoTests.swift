import Foundation
import Testing
@testable import FuelstatCore

struct PlanInfoTests {
    /// The free plan as `backend/src/services/plans.js` defines it, with limits enforced.
    private let free = Data("""
    {"plan":"free","planUntil":null,"effectivePlan":"free","limitsEnabled":true,
     "features":{"maxVehicles":1,"tripCategories":2,"tripExport":false,"premiumCategories":false,
                 "customCategories":0,"sharing":false,"comparison":false,"pdfReport":false,
                 "pushReminders":false,"fleet":false}}
    """.utf8)

    @Test func decodesTheFreePlan() throws {
        let info = try JSONDecoder().decode(PlanInfo.self, from: free)
        #expect(info.plan == "free")
        #expect(info.planUntil == nil)
        #expect(info.effectivePlan == "free")
        #expect(info.limitsEnabled)
        #expect(info.limit("maxVehicles") == .some(1))
        #expect(info.limit("customCategories") == .some(0))
        #expect(info.isEnabled("sharing") == false)
    }

    @Test func nullIsUnlimited() throws {
        let json = Data(#"{"plan":"plus","planUntil":"2027-06-30T00:00:00.000Z","effectivePlan":"plus","limitsEnabled":true,"features":{"maxVehicles":null,"sharing":true}}"#.utf8)
        let info = try JSONDecoder().decode(PlanInfo.self, from: json)
        #expect(info.limit("maxVehicles") == .some(nil), "unlimited is not the same as unknown")
        #expect(info.limit("unknownKey") == nil)
        #expect(info.isEnabled("sharing") == true)
        #expect(info.planUntil != nil)
    }

    @Test func withoutLimitsEveryoneGetsPlus() throws {
        let json = Data(#"{"plan":"free","planUntil":null,"effectivePlan":"plus","limitsEnabled":false,"features":{}}"#.utf8)
        let info = try JSONDecoder().decode(PlanInfo.self, from: json)
        #expect(info.plan == "free")
        #expect(info.effectivePlan == "plus")
        #expect(!info.limitsEnabled)
    }

    @Test func anExpiredPlanFallsBackToFree() throws {
        let json = Data(#"{"plan":"plus","planUntil":"2026-01-01","effectivePlan":"free","limitsEnabled":true,"features":{}}"#.utf8)
        let info = try JSONDecoder().decode(PlanInfo.self, from: json)
        #expect(info.hasExpired)
        #expect(info.planUntil != nil, "a plain date is read too")
    }

    @Test func aServerWithoutPlansHasNoPlanInfo() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PlanInfo.self, from: Data(#"{"features":{}}"#.utf8))
        }
    }

    @Test func oddFeatureValuesAreIgnored() throws {
        let json = Data(#"{"plan":"plus","features":{"maxVehicles":null,"weird":"x","sharing":true}}"#.utf8)
        let info = try JSONDecoder().decode(PlanInfo.self, from: json)
        #expect(info.features.keys.sorted() == ["maxVehicles", "sharing"])
    }
}

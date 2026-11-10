import Foundation
import Testing
@testable import FuelstatCore

struct PasswordChangeTests {
    @Test func validChange() {
        #expect(PasswordChangeDraft(current: "old-secret", new: "new-secret", repeated: "new-secret").isValid)
    }

    @Test func reportsProblemsInFieldOrder() {
        #expect(PasswordChangeDraft(current: "", new: "short", repeated: "x").problem == .currentMissing)
        #expect(PasswordChangeDraft(current: "old", new: "1234567", repeated: "1234567").problem == .tooShort)
        #expect(PasswordChangeDraft(current: "same-secret", new: "same-secret", repeated: "same-secret").problem
            == .unchanged)
        #expect(PasswordChangeDraft(current: "old", new: "new-secret", repeated: "new-secreT").problem == .mismatch)
    }

    @Test func eightCharactersAreEnough() {
        #expect(PasswordChangeDraft(current: "old", new: "12345678", repeated: "12345678").isValid)
    }
}

struct TOTPSecretTests {
    @Test func groupsInBlocksOfFour() {
        #expect(TOTPSecret.grouped("JBSWY3DPEHPK3PXP") == "JBSW Y3DP EHPK 3PXP")
    }

    @Test func keepsShortLastGroupAndNormalises() {
        #expect(TOTPSecret.grouped("abc defgh") == "ABCD EFGH")
        #expect(TOTPSecret.grouped("ABCDEF") == "ABCD EF")
        #expect(TOTPSecret.grouped("") == "")
    }
}

struct TermsVersionTests {
    @Test func parsesISODate() throws {
        let date = try #require(TermsVersion.date(from: "2026-11-09"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 2026, month: 11, day: 9))
    }

    @Test(arguments: ["", "v2", "2026-13-01", "2026-02-30", "26-11-09", "2026-11-9"])
    func rejectsOtherFormats(version: String) {
        #expect(TermsVersion.date(from: version) == nil)
    }
}

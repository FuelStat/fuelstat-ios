import Foundation
import Testing
@testable import FuelstatCore

struct NotificationPreferencesTests {
    private let example = Data("""
    {
      "occasions": {
        "reminders": { "email": true, "push": false },
        "odometer": { "email": false, "push": true },
        "report": { "email": true, "push": true },
        "inactive": { "email": false, "push": false }
      },
      "reminder_days": 14, "email_available": true, "push_available": false, "push_devices": 0
    }
    """.utf8)

    @Test func decodesTheEmailChannelPerOccasion() throws {
        let p = try JSONDecoder().decode(NotificationPreferences.self, from: example)
        #expect(p.isEmailOn(.reminders))
        #expect(!p.isEmailOn(.odometer), "push is not read")
        #expect(p.isEmailOn(.report))
        #expect(!p.isEmailOn(.inactive))
        #expect(p.reminderDays == 14)
        #expect(p.emailAvailable)
    }

    @Test func missingFieldsFallBackToOff() throws {
        let p = try JSONDecoder().decode(NotificationPreferences.self, from: Data("{}".utf8))
        #expect(NotificationPreferences.Occasion.allCases.allSatisfy { !p.isEmailOn($0) })
        #expect(p.reminderDays == 30)
        #expect(!p.emailAvailable)
    }

    @Test func oneChangeSendsOnlyThatOccasionsEmailChannel() throws {
        let data = try JSONEncoder.sorted.encode(NotificationPreferencesUpdate.email(.report, true))
        #expect(String(decoding: data, as: UTF8.self) == #"{"occasions":{"report":{"email":true}}}"#)
    }

    @Test func leadTimeSendsOnlyTheDays() throws {
        let data = try JSONEncoder.sorted.encode(NotificationPreferencesUpdate.reminderDays(7))
        #expect(String(decoding: data, as: UTF8.self) == #"{"reminder_days":7}"#)
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

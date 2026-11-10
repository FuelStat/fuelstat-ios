import Testing
@testable import FuelstatCore

struct FeedbackTests {
    @Test(arguments: ["", "  ", "ab", " ab \n"])
    func tooShortIsNotSendable(message: String) {
        #expect(!FeedbackDraft(message: message).isSendable)
    }

    @Test func trimmedLengthCounts() {
        let draft = FeedbackDraft(message: "  Gut!  \n")
        #expect(draft.trimmedMessage == "Gut!")
        #expect(draft.isSendable)
        #expect(draft.remainingCharacters == 4996)
    }

    @Test func tooLongIsNotSendable() {
        #expect(FeedbackDraft(message: String(repeating: "a", count: 5000)).isSendable)
        let draft = FeedbackDraft(message: String(repeating: "a", count: 5001))
        #expect(!draft.isSendable)
        #expect(draft.remainingCharacters == -1)
    }

    @Test func contextNamesAppAndSystem() {
        #expect(FeedbackDraft.context(appVersion: "0.2.0", build: "7", systemVersion: "26.1", device: "iPhone17,3")
            == "iOS-App 0.2.0 (7) · iOS 26.1 · iPhone17,3")
    }

    @Test func contextIsCappedAtPageLimit() {
        let context = FeedbackDraft.context(appVersion: String(repeating: "9", count: 400), build: "1",
                                            systemVersion: "26", device: "x")
        #expect(context.count == FeedbackDraft.maxPageLength)
    }
}

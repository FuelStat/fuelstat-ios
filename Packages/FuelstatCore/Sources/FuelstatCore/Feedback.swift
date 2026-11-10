import Foundation

/// Feedback for `POST /feedback`, checked against the limits the API enforces so the form can tell the user early.
public struct FeedbackDraft: Equatable, Sendable {
    /// Allowed message length in characters (after trimming), as documented for the API.
    public static let messageLength = 3...5000
    /// Maximum length of the `page` field.
    public static let maxPageLength = 300

    public var message: String

    public init(message: String = "") {
        self.message = message
    }

    public var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isSendable: Bool {
        Self.messageLength.contains(trimmedMessage.count)
    }

    /// Characters left until the maximum length (negative when too long).
    public var remainingCharacters: Int {
        Self.messageLength.upperBound - trimmedMessage.count
    }

    /// Context sent as `page`, so the operator knows where the feedback comes from,
    /// e.g. `iOS-App 0.2.0 (7) · iOS 26.1 · iPhone17,3`.
    public static func context(appVersion: String, build: String, systemVersion: String, device: String) -> String {
        let text = "iOS-App \(appVersion) (\(build)) · iOS \(systemVersion) · \(device)"
        return String(text.prefix(maxPageLength))
    }
}

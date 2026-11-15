import Foundation

/// `GET /notifications/preferences` (FuelStat/fuelstat#136): which occasions the server mails about, and the lead
/// time for due dates. Push channels are not used by the app (it plans local notifications), so only e-mail is read
/// and changed.
public struct NotificationPreferences: Decodable, Equatable, Sendable {
    public enum Occasion: String, CaseIterable, Sendable, Identifiable {
        /// Due dates: TÜV, service, insurance, tax
        case reminders
        /// A fill-up without an odometer reading
        case odometer
        /// Monthly report
        case report
        /// No entry for 30 days
        case inactive

        public var id: String { rawValue }
    }

    public let email: [Occasion: Bool]
    /// Lead time for due dates in days (1–180).
    public let reminderDays: Int
    /// The server has its own or a default mail server; without it no mail is sent.
    public let emailAvailable: Bool

    public static let reminderDaysRange = 1...180

    public func isEmailOn(_ occasion: Occasion) -> Bool { email[occasion] ?? false }

    public init(email: [Occasion: Bool] = [:], reminderDays: Int = 30, emailAvailable: Bool = false) {
        self.email = email
        self.reminderDays = reminderDays
        self.emailAvailable = emailAvailable
    }

    enum CodingKeys: String, CodingKey {
        case occasions, reminderDays = "reminder_days", emailAvailable = "email_available"
    }

    private struct Channels: Decodable {
        let email: Bool?
        enum CodingKeys: String, CodingKey { case email }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            email = try? c.decodeIfPresent(Bool.self, forKey: .email)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent([String: Channels].self, forKey: .occasions)) ?? [:]
        var email: [Occasion: Bool] = [:]
        for occasion in Occasion.allCases { email[occasion] = raw[occasion.rawValue]?.email ?? false }
        self.email = email
        reminderDays = c.lenientInt(.reminderDays) ?? 30
        emailAvailable = (try? c.decodeIfPresent(Bool.self, forKey: .emailAvailable)) ?? false
    }
}

/// Body of `PUT /notifications/preferences`. The call is partial: what is left out stays as it is, so the push
/// channels and the other occasions are not touched.
public struct NotificationPreferencesUpdate: Encodable, Equatable, Sendable {
    public var occasion: NotificationPreferences.Occasion?
    public var email: Bool?
    public var reminderDays: Int?

    public static func email(_ occasion: NotificationPreferences.Occasion, _ on: Bool) -> Self {
        .init(occasion: occasion, email: on, reminderDays: nil)
    }

    public static func reminderDays(_ days: Int) -> Self {
        .init(occasion: nil, email: nil, reminderDays: days)
    }

    enum CodingKeys: String, CodingKey { case occasions, reminderDays = "reminder_days" }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let occasion, let email {
            try c.encode([occasion.rawValue: ["email": email]], forKey: .occasions)
        }
        if let reminderDays { try c.encode(reminderDays, forKey: .reminderDays) }
    }
}

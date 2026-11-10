import Foundation

/// Checks for the "Passwort ändern" form. The API enforces the same minimum length (`password_too_short`);
/// checking it here lets the form explain the problem before sending.
public struct PasswordChangeDraft: Equatable, Sendable {
    /// Minimum length the API accepts for a new password.
    public static let minimumLength = 8

    public enum Problem: Equatable, Sendable {
        case currentMissing
        case tooShort
        case mismatch
        case unchanged
    }

    public var current: String
    public var new: String
    public var repeated: String

    public init(current: String = "", new: String = "", repeated: String = "") {
        self.current = current
        self.new = new
        self.repeated = repeated
    }

    /// The first problem that keeps the form from being sent, in the order the fields appear.
    public var problem: Problem? {
        if current.isEmpty { return .currentMissing }
        if new.count < Self.minimumLength { return .tooShort }
        if new == current { return .unchanged }
        if new != repeated { return .mismatch }
        return nil
    }

    public var isValid: Bool { problem == nil }
}

/// The TOTP secret from `POST /auth/mfa/setup`, for typing it into an authenticator by hand.
public enum TOTPSecret {
    /// Groups the Base32 secret in blocks of four (`JBSW Y3DP EHPK 3PXP`), which is easier to read and type.
    public static func grouped(_ secret: String, size: Int = 4) -> String {
        let characters = Array(secret.filter { !$0.isWhitespace }.uppercased())
        guard size > 0 else { return String(characters) }
        return stride(from: 0, to: characters.count, by: size)
            .map { String(characters[$0..<min($0 + size, characters.count)]) }
            .joined(separator: " ")
    }
}

/// Version of the terms of use as the API sends it (`terms_version`, e.g. `2026-11-09`).
public enum TermsVersion {
    /// The date of a version in `yyyy-MM-dd` form, or nil for any other format.
    public static func date(from version: String) -> Date? {
        let parts = version.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }
}

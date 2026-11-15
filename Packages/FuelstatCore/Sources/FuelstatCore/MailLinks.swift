import Foundation

/// Helpers for the links in the confirmation and password reset mails (FuelStat/fuelstat#175, fuelstat-ios #58).
/// None of this talks to the server; it only reads what the mail contains and compares accounts and servers.
public enum MailToken {
    /// The token from what the user pasted: the code from the mail, or the whole link
    /// (`…/email_bestaetigen.php?token=…`, `fuelstat://reset-password?token=…`). Nil for empty input.
    public static func extract(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://") || text.contains("?"),
           let components = URLComponents(string: text),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty {
            return token
        }
        // A link without a token is not a code. A bare code has no spaces; anything else is not a token.
        if text.contains("://") { return nil }
        return text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil ? text : nil
    }
}

/// Whether a link addresses the server the app is signed in to.
public enum MailServer {
    /// `server` of the link is a host or address (`tanken.1emc.de`, `https://tanken.1emc.de`, with a port); the app's
    /// server is its API base URL. Only host and port count. Without `server` in the link there is nothing to compare.
    public static func matches(linkServer: String?, current: URL) -> Bool {
        guard let raw = linkServer?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return true }
        let candidate = raw.contains("://") ? raw : "https://" + raw
        guard let link = URLComponents(string: candidate), let linkHost = link.host?.lowercased(),
              let host = current.host?.lowercased() else { return false }
        guard linkHost == host else { return false }
        return effectivePort(link.port, scheme: link.scheme) == effectivePort(current.port, scheme: current.scheme)
    }

    private static func effectivePort(_ port: Int?, scheme: String?) -> Int {
        port ?? (scheme?.lowercased() == "http" ? 80 : 443)
    }
}

/// Whether a reset or confirmation concerned the account the app is signed in to. A link can belong to another
/// account; the app must not touch the signed-in session then.
public enum MailAccount: Equatable, Sendable {
    case own
    case other(email: String)
    /// The API did not say which address it was (server before FuelStat/fuelstat#175).
    case unknown

    public static func compare(signedIn: String?, affected: String?) -> MailAccount {
        guard let affected = affected?.trimmingCharacters(in: .whitespacesAndNewlines), !affected.isEmpty else {
            return .unknown
        }
        guard let signedIn = signedIn?.trimmingCharacters(in: .whitespacesAndNewlines), !signedIn.isEmpty else {
            return .other(email: affected)
        }
        return signedIn.caseInsensitiveCompare(affected) == .orderedSame ? .own : .other(email: affected)
    }
}

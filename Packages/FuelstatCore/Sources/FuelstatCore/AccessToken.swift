import Foundation

/// Reads the expiry of an access token (a JWT) so the app can renew it shortly before it runs out instead of
/// waiting for a 401. The signature is the server's business; only the `exp` claim is read.
public enum AccessToken {
    /// `exp` of a JWT, or nil when the token cannot be read.
    public static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }

    /// The token runs out within `margin` seconds. Unreadable tokens count as valid; the server answers with a
    /// 401 then, and the app renews after that.
    public static func needsRenewal(_ token: String, now: Date = .now, margin: TimeInterval = 120) -> Bool {
        guard let expiry = expiry(of: token) else { return false }
        return expiry.timeIntervalSince(now) < margin
    }
}

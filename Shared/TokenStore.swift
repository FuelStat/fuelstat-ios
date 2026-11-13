import Foundation
import FuelstatCore

/// Version of the app; the widgets carry the same one (both targets share `MARKETING_VERSION`).
enum AppVersion {
    static var marketing: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
    static var build: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String }

    /// `X-Fuelstat-Client: ios/0.2.0 (5)` – the format `parseClient` in the API's `lib/appVersions.js` reads.
    static var clientHeader: String {
        var value = "ios/\(marketing ?? "0.0.0")"
        if let build { value += " (\(build))" }
        return value
    }
}

/// The access token of this device, renewed through the device session (FuelStat/fuelstat#117).
///
/// Access tokens of a device session live 30 minutes; the refresh token swaps them for a new pair and works
/// exactly once. App, widgets and Siri all read the pair from the shared Keychain, so:
/// - inside one process, swaps never run in parallel (this actor waits for the running one);
/// - the refresh token is read from the Keychain right before each swap and the new one stored right after, so a
///   widget never sends a token the app has already used up;
/// - if another process swapped at the same moment (`refresh_token_already_used`), the pair it stored is used.
///
/// Sign-ins from before device sessions have no refresh token; their 7-day token is used as it is.
actor TokenStore {
    static let shared = TokenStore()

    private var running: Task<String, Error>?

    /// Errors of a swap after which the session is over and the user has to sign in again.
    private static let sessionEnded: Set<String> = [
        "invalid_refresh_token", "refresh_token_reused", "session_revoked", "session_expired",
    ]

    /// A usable access token. With `force`, the session is renewed even if the token looks valid
    /// (after a 401). Throws `APIError.unauthorized` when the user is signed out.
    func accessToken(api: APIClient, force: Bool = false) async throws -> String {
        guard let current = KeychainStore.loadToken() else { throw APIError.unauthorized }
        guard KeychainStore.loadRefreshToken() != nil else {
            // Legacy sign-in without a device session.
            if force { throw APIError.unauthorized }
            return current
        }
        if !force, !AccessToken.needsRenewal(current) { return current }
        if let running { return try await running.value }

        let task = Task { try await Self.swap(api: api, previous: current) }
        running = task
        defer { running = nil }
        return try await task.value
    }

    /// Stores the tokens of a new sign-in (or of a password change).
    func store(token: String, refreshToken: String?) {
        KeychainStore.saveRefreshToken(refreshToken)
        KeychainStore.saveToken(token)
    }

    private static func swap(api: APIClient, previous: String) async throws -> String {
        guard let refreshToken = KeychainStore.loadRefreshToken() else { throw APIError.unauthorized }
        // Another process may have swapped since the caller looked: then its fresh token is used.
        if let stored = KeychainStore.loadToken(), stored != previous, !AccessToken.needsRenewal(stored) {
            return stored
        }
        do {
            let pair = try await api.refreshSession(refreshToken: refreshToken, appVersion: AppVersion.marketing)
            KeychainStore.saveRefreshToken(pair.refreshToken)
            KeychainStore.saveToken(pair.token)
            return pair.token
        } catch APIError.server(code: "refresh_token_already_used", _) {
            // Swapped by the widget or the app at the same moment; give it a moment to store the new pair.
            try await Task.sleep(for: .seconds(1))
            if let stored = KeychainStore.loadToken(), stored != previous { return stored }
            throw APIError.network(String(localized: "Die Anmeldung wird gerade erneuert. Bitte versuche es gleich noch einmal."))
        } catch let APIError.server(code, _) where sessionEnded.contains(code) {
            // Only end the sign-in if nobody stored a new pair in the meantime.
            if KeychainStore.loadRefreshToken() == refreshToken { KeychainStore.deleteToken() }
            throw APIError.unauthorized
        }
    }
}

/// Runs an API call for widgets and intents with a valid token; after a 401 it renews the session once and tries
/// again.
enum SignedInAPI {
    static func call<T>(_ api: APIClient, _ operation: (APIClient, String) async throws -> T)
        async throws -> T {
        let token = try await TokenStore.shared.accessToken(api: api)
        do {
            return try await operation(api, token)
        } catch APIError.unauthorized where KeychainStore.loadRefreshToken() != nil {
            return try await operation(api, try await TokenStore.shared.accessToken(api: api, force: true))
        }
    }
}

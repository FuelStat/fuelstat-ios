import Foundation
import Observation

@MainActor
@Observable
final class AuthSession {
    enum State: Equatable {
        /// Checking a stored token on launch.
        case restoring
        case signedOut
        case signedIn(APIUser)
    }

    private(set) var state: State = .restoring
    private(set) var token: String?
    let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    /// Validates a stored token via `/whoami`. Keeps the user signed in when offline.
    func restore() async {
        guard let stored = KeychainStore.loadToken() else {
            state = .signedOut
            return
        }
        do {
            let user = try await api.whoami(token: stored)
            token = stored
            storeUser(user)
            state = .signedIn(user)
        } catch APIError.unauthorized {
            clear()
        } catch {
            // Server not reachable: stay signed in with the last known user.
            if let user = loadUser() {
                token = stored
                state = .signedIn(user)
            } else {
                clear()
            }
        }
    }

    /// Throws `APIError.server(code: "mfa_required", …)` when a 2FA code is needed.
    func login(email: String, password: String, code: String? = nil) async throws {
        let response = try await api.login(email: email, password: password, code: code)
        signIn(response)
    }

    func register(email: String, password: String) async throws {
        let response = try await api.register(email: email, password: password)
        signIn(response)
    }

    func logout() async {
        if let token {
            try? await api.revoke(token: token)
        }
        clear()
    }

    /// Called when an API call reports an expired or revoked token.
    func handleUnauthorized() {
        clear()
    }

    private func signIn(_ response: AuthResponse) {
        KeychainStore.saveToken(response.token)
        token = response.token
        storeUser(response.user)
        state = .signedIn(response.user)
    }

    private func clear() {
        KeychainStore.deleteToken()
        UserDefaults.standard.removeObject(forKey: Self.userIDKey)
        UserDefaults.standard.removeObject(forKey: Self.userEmailKey)
        token = nil
        state = .signedOut
    }

    // Non-secret profile data, so the app can start offline.
    private static let userIDKey = "auth.user.id"
    private static let userEmailKey = "auth.user.email"

    private func storeUser(_ user: APIUser) {
        UserDefaults.standard.set(user.id, forKey: Self.userIDKey)
        UserDefaults.standard.set(user.email, forKey: Self.userEmailKey)
    }

    private func loadUser() -> APIUser? {
        guard let id = UserDefaults.standard.string(forKey: Self.userIDKey),
              let email = UserDefaults.standard.string(forKey: Self.userEmailKey) else { return nil }
        return APIUser(id: id, email: email)
    }
}

import Foundation
import Observation
import UIKit

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
    private(set) var api: APIClient
    /// Why the user was signed out without asking for it, shown on the sign-in screen.
    private(set) var signOutNotice: String?
    @ObservationIgnored private var isRenewing = false

    /// The API extends a token by 7 days per refresh; renewing once a day is plenty.
    private static let renewalInterval: TimeInterval = 20 * 60 * 60

    init(api: APIClient = .configured) {
        self.api = api
    }

    /// The signed-in account, or nil.
    var user: APIUser? {
        if case .signedIn(let user) = state { return user }
        return nil
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
            await renewIfNeeded()
        } catch APIError.unauthorized {
            clear(notice: APIError.unauthorized.localizedDescription)
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

    /// Changes the server. Only possible while signed out.
    func useServer(_ baseURL: URL) {
        guard token == nil else { return }
        ServerSettings.save(baseURL)
        api.baseURL = baseURL
    }

    /// Throws `APIError.server(code: "mfa_required", …)` when a 2FA code is needed.
    func login(email: String, password: String, code: String? = nil) async throws {
        let response = try await api.login(email: email, password: password, code: code)
        signIn(response)
        await refreshUser()
    }

    func register(email: String, password: String) async throws {
        let response = try await api.register(email: email, password: password)
        signIn(response)
        await refreshUser()
    }

    /// Reloads the account from `/whoami` (verification state, terms, 2FA, profile). Errors keep the known data.
    func refreshUser() async {
        guard let user = try? await call({ try await $0.whoami(token: $1) }) else { return }
        update(user)
    }

    // MARK: - Account settings

    func updateProfile(_ patch: ProfilePatch) async throws {
        guard let id = user?.id else { throw APIError.unauthorized }
        let updated = try await call { try await $0.updateProfile(userID: id, patch, token: $1) }
        merge(updated)
    }

    /// Uploads a photo and makes it the profile picture.
    func setProfilePhoto(_ image: UIImage) async throws {
        guard let id = user?.id else { throw APIError.unauthorized }
        guard let jpeg = VehicleStore.jpeg(from: image, maxEdge: 800) else {
            throw APIError.server(code: "invalid_image", status: 0)
        }
        let media = try await call { try await $0.uploadProfileImage(jpeg: jpeg, token: $1) }
        let updated = try await call {
            try await $0.updateProfile(userID: id, ProfilePatch(profileImageUrl: .some(media.url)), token: $1)
        }
        if let url = api.resolve(updated.profileImageURL) {
            await ImageCache.shared.store(image, data: jpeg, for: url)
        }
        merge(updated)
    }

    func removeProfilePhoto() async throws {
        try await updateProfile(ProfilePatch(profileImageUrl: .some(nil)))
    }

    /// Changes the password. The API signs out all other devices and hands this one a new token.
    func changePassword(current: String, new: String) async throws {
        let renewed = try await call { try await $0.changePassword(current: current, new: new, token: $1) }
        KeychainStore.saveToken(renewed)
        token = renewed
        UserDefaults.standard.set(Date.now, forKey: Self.renewedAtKey)
    }

    /// Sends the confirmation mail again. Returns the address it went to.
    func resendVerification() async throws -> String? {
        try await call { try await $0.resendVerification(token: $1) }.email
    }

    func acceptTerms(version: String) async throws {
        try await call { try await $0.acceptTerms(version: version, token: $1) }
        await refreshUser()
        // Without a fresh /whoami the prompt would come back; mark it accepted locally.
        if var user, user.terms?.required == true {
            user.terms = APIUser.Terms(version: version, acceptedVersion: version, required: false)
            update(user)
        }
    }

    /// Signs out on every device, this one included.
    func signOutEverywhere() async throws {
        guard let id = user?.id else { throw APIError.unauthorized }
        try await call { try await $0.revokeAll(userID: id, token: $1) }
        clear(notice: String(localized: "Du wurdest auf allen Geräten abgemeldet."))
    }

    func setUpMFA() async throws -> MFASetup {
        try await call { try await $0.mfaSetup(token: $1) }
    }

    func enableMFA(code: String) async throws {
        try await call { try await $0.mfaEnable(code: code, token: $1) }
        setMFA(true)
    }

    func disableMFA(password: String, code: String) async throws {
        try await call { try await $0.mfaDisable(password: password, code: code, token: $1) }
        setMFA(false)
    }

    private func setMFA(_ enabled: Bool) {
        guard var user else { return }
        user.mfaEnabled = enabled
        update(user)
    }

    /// PATCH answers without `terms`; keep the known value.
    private func merge(_ updated: APIUser) {
        var updated = updated
        if updated.terms == nil { updated.terms = user?.terms }
        update(updated)
    }

    private func update(_ user: APIUser) {
        guard case .signedIn(let current) = state, current.id == user.id else { return }
        storeUser(user)
        state = .signedIn(user)
    }

    func logout() async {
        if let token {
            try? await api.revoke(token: token)
        }
        clear()
    }

    /// Deletes the account on the server, then removes everything the app stored on this device
    /// (token, cached images, settings) and returns to the welcome screen.
    func deleteAccount() async throws {
        guard case .signedIn(let user) = state, let token else { throw APIError.unauthorized }
        do {
            try await api.deleteAccount(userID: user.id, token: token)
        } catch APIError.server(code: "user_not_found", _), APIError.server(code: "account_not_found", _) {
            // Already gone (e.g. deleted in the web app): clean up all the same.
        } catch APIError.unauthorized {
            clear(notice: APIError.unauthorized.localizedDescription)
            throw APIError.unauthorized
        }
        await ImageCache.shared.removeAll()
        ServerSettings.save(APIClient.defaultBaseURL)
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        api.baseURL = ServerSettings.baseURL
        clear(notice: String(localized: "Dein Konto wurde gelöscht."))
    }

    /// Runs an API call with the current token. An expired or revoked token signs the user out.
    func call<T>(_ operation: (APIClient, String) async throws -> T) async throws -> T {
        guard let token else { throw APIError.unauthorized }
        do {
            return try await operation(api, token)
        } catch APIError.unauthorized {
            clear(notice: APIError.unauthorized.localizedDescription)
            throw APIError.unauthorized
        }
    }

    /// Swaps the token for a fresh one at most once a day, so active users stay signed in.
    /// After 90 days without a password sign-in the API refuses (`reauth_required`) and the user has to sign in again.
    func renewIfNeeded() async {
        guard let current = token, !isRenewing else { return }
        if let last = UserDefaults.standard.object(forKey: Self.renewedAtKey) as? Date,
           Date.now.timeIntervalSince(last) < Self.renewalInterval {
            return
        }
        isRenewing = true
        defer { isRenewing = false }
        do {
            let renewed = try await api.refresh(token: current)
            // Ignore the result if the user signed out in the meantime.
            guard token == current else { return }
            KeychainStore.saveToken(renewed)
            token = renewed
            UserDefaults.standard.set(Date.now, forKey: Self.renewedAtKey)
        } catch APIError.unauthorized {
            if token == current { clear(notice: APIError.unauthorized.localizedDescription) }
        } catch {
            // Offline or server error: try again next time.
        }
    }

    private func signIn(_ response: AuthResponse) {
        KeychainStore.saveToken(response.token)
        token = response.token
        signOutNotice = nil
        UserDefaults.standard.set(Date.now, forKey: Self.renewedAtKey)
        storeUser(response.user)
        state = .signedIn(response.user)
        WidgetRefresh.reload()
    }

    private func clear(notice: String? = nil) {
        KeychainStore.deleteToken()
        for key in [Self.userIDKey, Self.userEmailKey, Self.renewedAtKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        token = nil
        signOutNotice = notice
        state = .signedOut
        WidgetRefresh.reload()
    }

    // Non-secret profile data, so the app can start offline.
    private static let userIDKey = "auth.user.id"
    private static let userEmailKey = "auth.user.email"
    private static let renewedAtKey = "auth.token.renewedAt"

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

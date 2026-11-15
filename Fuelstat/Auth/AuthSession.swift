import Foundation
import FuelstatCore
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
    /// An address to prefill on the sign-in screen, e.g. after a password reset.
    var prefillEmail: String?
    /// A reset link the user opened, to be shown as a sheet.
    var resetRequest: ResetRequest?
    /// Result of a mail link (wrong server, address confirmed), shown once as an alert.
    var mailLinkNotice: String?
    @ObservationIgnored private var isRenewing = false

    struct ResetRequest: Identifiable {
        let token: String
        var id: String { token }
    }

    /// What a password reset did to this sign-in.
    enum ResetOutcome: Equatable {
        /// The account of this app (or nobody was signed in): sign in again with the new password.
        case signInAgain(email: String?)
        /// A different account than the signed-in one: this session stays untouched.
        case otherAccount(email: String?)
    }

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

    /// Validates the stored sign-in via `/whoami`, renewing the device session if needed. Keeps the user signed in
    /// when offline.
    func restore() async {
        guard let stored = KeychainStore.loadToken() else {
            state = .signedOut
            return
        }
        do {
            let user = try await SignedInAPI.call(api) { try await $0.whoami(token: $1) }
            token = KeychainStore.loadToken() ?? stored
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
        let response = try await api.login(email: email, password: password, code: code, device: Self.device)
        await signIn(response)
        await refreshUser()
    }

    func register(email: String, password: String) async throws {
        let response = try await api.register(email: email, password: password, device: Self.device)
        await signIn(response)
        await refreshUser()
    }

    /// This iPhone as the API lists it under the signed-in devices (FuelStat/fuelstat#117). Since iOS 16 the
    /// device name is the model ("iPhone") unless the app has a special entitlement.
    private static var device: DeviceInfo {
        DeviceInfo(name: UIDevice.current.name, appVersion: AppVersion.marketing)
    }

    /// The sign-in uses a device session with a refresh token (sign-ins before FuelStat/fuelstat#117 do not).
    var hasDeviceSession: Bool { KeychainStore.loadRefreshToken() != nil }

    // MARK: - Devices

    func sessions() async throws -> [DeviceSession] {
        try await call { try await $0.sessions(token: $1) }
    }

    /// Signs another app out. For this device use `logout()`.
    func endSession(_ id: String) async throws {
        try await call { try await $0.deleteSession(id: id, token: $1) }
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
        let previous = user?.profileImageURL
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
        await deleteOldProfilePhoto(previous)
    }

    func removeProfilePhoto() async throws {
        let previous = user?.profileImageURL
        try await updateProfile(ProfilePatch(profileImageUrl: .some(nil)))
        await deleteOldProfilePhoto(previous)
    }

    /// Deletes a replaced or removed profile picture on the server, file included.
    private func deleteOldProfilePhoto(_ address: String?) async {
        guard let name = RemoteMedia.fileName(of: address),
              let media = try? await call({ try await $0.media(token: $1) }),
              let old = media.first(where: { $0.fileName == name }) else { return }
        _ = try? await call { try await $0.deleteMedia(id: old.id, token: $1) }
    }

    /// Changes the password. The API signs out all other devices and hands this one a new token.
    func changePassword(current: String, new: String) async throws {
        let renewed = try await call { try await $0.changePassword(current: current, new: new, token: $1) }
        // From an app with a device session the API starts a new one for this device.
        await TokenStore.shared.store(token: renewed.token, refreshToken: renewed.refreshToken)
        token = renewed.token
        UserDefaults.standard.set(Date.now, forKey: Self.renewedAtKey)
        WidgetRefresh.reload()
    }

    /// Confirms the address of a code or link from the mail. Returns whose address it was: a link can belong to
    /// another account than the signed-in one, then only the address is reported.
    func verifyEmail(input: String) async throws -> MailAccount {
        guard let token = MailToken.extract(from: input) else {
            throw APIError.server(code: "invalid_token", status: 400)
        }
        let result = try await api.verifyEmail(token: token)
        // Reading the own account changes nothing, so this is safe for a foreign address too.
        await refreshUser()
        return affectedAccount(result.email)
    }

    /// Sets a new password with the code from the mail. Never changes the session of a different account.
    func resetPassword(token: String, password: String) async throws -> ResetOutcome {
        let result = try await api.resetPassword(token: token, password: password)
        prefillEmail = result.email ?? user?.email
        guard user != nil else { return .signInAgain(email: result.email) }
        switch affectedAccount(result.email) {
        case .own:
            // The API revoked every token of this account.
            clear(notice: String(localized: "Passwort geändert. Bitte melde dich neu an."))
            return .signInAgain(email: result.email)
        case .other(let email):
            return .otherAccount(email: email)
        case .unknown:
            // Server before FuelStat/fuelstat#175 names no account: if our own token still works, it was another one
            // (a 401 signs this device out, which is right when it was the own account).
            if (try? await call({ try await $0.whoami(token: $1) })) != nil {
                return .otherAccount(email: nil)
            }
            return .signInAgain(email: nil)
        }
    }

    /// Compares the address of a mail link with the signed-in account (its confirmed or pending address).
    private func affectedAccount(_ email: String?) -> MailAccount {
        let ownAddress = MailAccount.compare(signedIn: user?.email, affected: email)
        if ownAddress == .own { return .own }
        if case .other = ownAddress, user?.pendingEmail != nil,
           MailAccount.compare(signedIn: user?.pendingEmail, affected: email) == .own {
            return .own
        }
        return ownAddress
    }

    /// Handles `fuelstat://reset-password` and `fuelstat://email-bestaetigt`. The link names its server; one that is
    /// not the signed-in server is not acted on, so a token never goes to another server.
    func handle(_ link: AppLink) {
        switch link {
        case .resetPassword(let token, let server):
            if MailServer.matches(linkServer: server, current: api.baseURL) {
                resetRequest = ResetRequest(token: token)
            } else {
                mailLinkNotice = wrongServerNotice(server)
            }
        case .emailConfirmed(let server):
            if MailServer.matches(linkServer: server, current: api.baseURL) {
                mailLinkNotice = String(localized: "Deine E-Mail-Adresse ist bestätigt.")
                Task { await refreshUser() }
            } else {
                mailLinkNotice = wrongServerNotice(server)
            }
        default:
            break
        }
    }

    private func wrongServerNotice(_ server: String?) -> String {
        let name = server ?? "?"
        return String(localized: "Der Link gehört zum Server \(name), die App ist aber mit \(ServerSettings.displayName(of: api.baseURL)) verbunden. Es wurde nichts geändert.")
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
        if updated.pendingInvitations == nil { updated.pendingInvitations = user?.pendingInvitations }
        update(updated)
    }

    private func update(_ user: APIUser) {
        guard case .signedIn(let current) = state, current.id == user.id else { return }
        storeUser(user)
        state = .signedIn(user)
    }

    /// Signs this device out: ends its device session, or revokes the token of an older sign-in.
    func logout() async {
        if token != nil {
            if hasDeviceSession {
                _ = try? await SignedInAPI.call(api) { try await $0.deleteSession(id: "current", token: $1) }
            } else if let token {
                try? await api.revoke(token: token)
            }
        }
        clear()
    }

    /// Deletes the account on the server, then removes everything the app stored on this device
    /// (token, cached images, settings) and returns to the welcome screen.
    func deleteAccount() async throws {
        guard case .signedIn(let user) = state else { throw APIError.unauthorized }
        do {
            try await call { try await $0.deleteAccount(userID: user.id, token: $1) }
        } catch APIError.server(code: "user_not_found", _), APIError.server(code: "account_not_found", _) {
            // Already gone (e.g. deleted in the web app): clean up all the same.
        }
        await ImageCache.shared.removeAll()
        ServerSettings.save(APIClient.defaultBaseURL)
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        api.baseURL = ServerSettings.baseURL
        clear(notice: String(localized: "Dein Konto wurde gelöscht."))
    }

    /// Runs an API call with a valid token, renewing the device session when it is about to expire or after a 401.
    /// A sign-in that cannot be renewed (ended session, revoked token) signs the user out.
    func call<T>(_ operation: (APIClient, String) async throws -> T) async throws -> T {
        guard token != nil else { throw APIError.unauthorized }
        do {
            let result = try await SignedInAPI.call(api, operation)
            token = KeychainStore.loadToken() ?? token
            return result
        } catch APIError.unauthorized {
            clear(notice: APIError.unauthorized.localizedDescription)
            throw APIError.unauthorized
        }
    }

    /// Keeps the sign-in alive when the app comes to the foreground.
    /// - Device session: renews the 30-minute token if it is about to run out, so widgets find a fresh one.
    /// - Older sign-in: swaps the 7-day token at most once a day; after 90 days without a password sign-in the API
    ///   refuses (`reauth_required`) and the user has to sign in again.
    func renewIfNeeded() async {
        if hasDeviceSession {
            guard token != nil else { return }
            do {
                token = try await TokenStore.shared.accessToken(api: api)
            } catch APIError.unauthorized {
                clear(notice: APIError.unauthorized.localizedDescription)
            } catch {
                // Offline: try again next time.
            }
            return
        }
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

    private func signIn(_ response: AuthResponse) async {
        // A server without device sessions sends no refresh token; any old one is removed then.
        await TokenStore.shared.store(token: response.token, refreshToken: response.refreshToken)
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
        // Due dates of this account must not be announced after signing out.
        ReminderNotifications.removeAll()
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

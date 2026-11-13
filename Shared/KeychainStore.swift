import Foundation
import Security

/// Stores the API token and the server address in the Keychain (this device only, available after first unlock).
///
/// Items live in a Keychain access group shared by the app and its widgets (Keychain Sharing,
/// `keychain-access-groups` in `Config/*.entitlements`), so a widget can call the API with the app's sign-in.
/// The group name comes from the Info.plist key `FuelstatKeychainGroup` (`$(AppIdentifierPrefix)org.fuelstat.shared`).
enum KeychainStore {
    private static let service = "org.fuelstat.ios"
    private static let tokenAccount = "api-token"
    private static let refreshTokenAccount = "api-refresh-token"
    private static let selectedVehicleAccount = "selected-vehicle"
    private static let serverAccount = "api-baseURL"

    /// The shared access group, or nil in builds without signing (e.g. CI), where only the app's own group exists.
    static let sharedGroup: String? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FuelstatKeychainGroup") as? String,
              !group.hasPrefix("."), !group.contains("$(") else { return nil }
        return group
    }()

    static func loadToken() -> String? { load(tokenAccount) }
    static func saveToken(_ token: String) { save(token, as: tokenAccount) }
    static func deleteToken() {
        delete(tokenAccount)
        delete(refreshTokenAccount)
        delete(selectedVehicleAccount)
    }

    /// The vehicle chosen in the app's switcher, for widgets that show "the" vehicle (CarPlay). Not secret; the
    /// Keychain is simply the only store app and widgets share without an App Group.
    static func loadSelectedVehicle() -> String? { load(selectedVehicleAccount) }
    static func saveSelectedVehicle(_ id: String?) {
        guard id != loadSelectedVehicle() else { return }
        if let id { save(id, as: selectedVehicleAccount) } else { delete(selectedVehicleAccount) }
    }

    /// Refresh token of the device session (FuelStat/fuelstat#117). Each one works exactly once; after a swap the
    /// new one must be stored before anything else happens. Sign-ins from before device sessions have none.
    static func loadRefreshToken() -> String? { load(refreshTokenAccount) }
    static func saveRefreshToken(_ token: String?) {
        if let token { save(token, as: refreshTokenAccount) } else { delete(refreshTokenAccount) }
    }

    /// Server address for the widgets; the app keeps its own copy in UserDefaults (see `ServerSettings`).
    static func loadServer() -> String? { load(serverAccount) }
    static func saveServer(_ address: String?) {
        if let address { save(address, as: serverAccount) } else { delete(serverAccount) }
    }

    /// Moves items stored by earlier versions (in the app's private group) into the shared group, so the widgets
    /// see them without a new sign-in. Safe to call on every launch.
    static func moveToSharedGroup() {
        guard let group = sharedGroup else { return }
        for account in [tokenAccount, serverAccount] {
            if load(account, group: group) == nil, let value = load(account) {
                save(value, as: account)
            }
        }
    }

    // MARK: - Keychain access

    private static func query(_ account: String, group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    /// Without a group the search covers every group this process may read.
    private static func load(_ account: String, group: String? = nil) -> String? {
        var query = query(account, group: group)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String, as account: String) {
        delete(account)
        var query = query(account, group: sharedGroup)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Without a group this removes the item from every group, including copies left by earlier versions.
    private static func delete(_ account: String) {
        SecItemDelete(query(account, group: nil) as CFDictionary)
    }
}

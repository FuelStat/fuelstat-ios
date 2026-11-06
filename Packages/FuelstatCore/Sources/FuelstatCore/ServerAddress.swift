import Foundation

/// Address of a Fuelstat server (the hosted service or a self-hosted installation).
public enum ServerAddress {
    /// Path of the REST API below the server root.
    public static let apiPath = "/api/v1"

    /// Turns user input such as `tanken.example.de`, `https://tanken.example.de/` or
    /// `https://tanken.example.de/api/v1` into the API base URL (`https://tanken.example.de/api/v1`).
    ///
    /// Only HTTPS is accepted: tokens and passwords must not travel unencrypted.
    /// Returns nil for anything that is not a usable address.
    public static func apiBaseURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.contains("://") { text = "https://" + text }

        guard var components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.query == nil, components.fragment == nil,
              components.user == nil, components.password == nil
        else { return nil }

        components.scheme = "https"
        components.host = host.lowercased()

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix(apiPath) { path += apiPath }
        components.path = path

        return components.url
    }

    /// Server root shown to the user, e.g. `tanken.example.de` for `https://tanken.example.de/api/v1`.
    public static func displayName(of apiBaseURL: URL) -> String {
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else {
            return apiBaseURL.absoluteString
        }
        if components.path.hasSuffix(apiPath) {
            components.path.removeLast(apiPath.count)
        }
        var text = (components.host ?? "") + (components.port.map { ":\($0)" } ?? "") + components.path
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

/// Cache key for an image delivered by the API.
///
/// The API signs image addresses (`/api/v1/files/<uuid>.webp?exp=…&sig=…`) and the signature changes daily,
/// while the file behind it never changes. So the file name, not the full URL, identifies the image.
public enum ImageCacheKey {
    public static func key(for url: URL) -> String {
        let name = url.lastPathComponent
        if url.path.contains("/files/"), isSafeFileName(name) {
            return name
        }
        // Not a signed API address: fall back to the full address, made safe for use as a file name.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let escaped = url.absoluteString.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return String(escaped.suffix(120))
    }

    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 80 && !name.hasPrefix(".")
            && name.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
            }
    }
}

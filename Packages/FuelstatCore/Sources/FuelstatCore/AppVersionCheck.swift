import Foundation

/// Compares the app's version with the minimum and recommended versions the server announces in `GET /health`
/// (`apps.ios`, FuelStat/fuelstat#118). The server decides the versions; this only compares them.
public enum AppVersionCheck {
    public enum Status: Equatable, Sendable {
        case upToDate
        /// Works, but a newer app uses all features of this server.
        case updateRecommended(String)
        /// The server no longer supports this app version.
        case updateRequired(String)
    }

    public static func status(current: String, minimum: String?, recommended: String?) -> Status {
        if let minimum, let order = compare(current, minimum), order == .orderedAscending {
            return .updateRequired(minimum)
        }
        if let recommended, let order = compare(current, recommended), order == .orderedAscending {
            return .updateRecommended(recommended)
        }
        return .upToDate
    }

    /// Compares `x.y.z` versions numerically; nil when one of them is not in that form.
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard let a = parts(lhs), let b = parts(rhs) else { return nil }
        for (x, y) in zip(a, b) where x != y {
            return x < y ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    private static func parts(_ version: String) -> [Int]? {
        let parts = version.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 && numbers.allSatisfy { $0 >= 0 } ? numbers : nil
    }
}

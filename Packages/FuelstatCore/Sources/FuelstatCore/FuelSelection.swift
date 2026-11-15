import Foundation

/// The fuel grades (Sorten) chosen for a vehicle in the form, and which one is the default for new entries
/// (FuelStat/fuelstat#140). The API allows one to eight grades and requires the default to be among them; whether a
/// grade fits the drive type is the API's decision and comes back as its error.
public struct FuelSelection: Equatable, Sendable {
    public static let maxCount = 8

    public private(set) var keys: [String]
    public private(set) var defaultKey: String?

    /// `keys` without duplicates; a default that is not among them becomes the first.
    public init(keys: [String], defaultKey: String?) {
        var seen = Set<String>()
        self.keys = keys.filter { seen.insert($0).inserted }.prefix(Self.maxCount).map { $0 }
        self.defaultKey = defaultKey.flatMap { self.keys.contains($0) ? $0 : nil } ?? self.keys.first
    }

    public func isSelected(_ key: String) -> Bool { keys.contains(key) }

    public var canAddMore: Bool { keys.count < Self.maxCount }

    /// Adds or removes a grade. The last one stays; removing the default makes the first remaining one the default.
    public mutating func toggle(_ key: String) {
        if let index = keys.firstIndex(of: key) {
            guard keys.count > 1 else { return }
            keys.remove(at: index)
            if defaultKey == key { defaultKey = keys.first }
        } else if canAddMore {
            keys.append(key)
            if defaultKey == nil { defaultKey = key }
        }
    }

    /// Makes a selected grade the default for new entries.
    public mutating func setDefault(_ key: String) {
        if keys.contains(key) { defaultKey = key }
    }

    /// Whether this differs from the vehicle's saved grades, so the app only sends what the user changed.
    public func differs(from keys: [String], defaultKey: String?) -> Bool {
        self.keys != keys || (defaultKey != nil && self.defaultKey != defaultKey)
    }
}

import Foundation

/// Plan of the account from `GET /whoami` (FuelStat/fuelstat#44, #102): which plan is booked, which one applies right
/// now and what it allows. The API decides; the app only shows it and never offers a purchase.
public struct PlanInfo: Decodable, Equatable, Sendable {
    /// One entry of `features`: a number limit (`null` = unlimited) or a yes/no right.
    public enum Feature: Equatable, Sendable {
        case limit(Int?)
        case flag(Bool)
    }

    /// Booked plan: `free`, `plus` or `fleet`.
    public let plan: String
    /// End of the booked plan; nil = no end. Afterwards `free` applies.
    public let planUntil: Date?
    /// The plan whose rights apply now; without plan limits on the server at least `plus`.
    public let effectivePlan: String
    /// Whether the server enforces plan limits at all (`PLAN_LIMITS_ENABLED`).
    public let limitsEnabled: Bool
    public let features: [String: Feature]

    enum CodingKeys: String, CodingKey { case plan, planUntil, effectivePlan, limitsEnabled, features }

    public init(plan: String, planUntil: Date?, effectivePlan: String, limitsEnabled: Bool,
                features: [String: Feature]) {
        self.plan = plan
        self.planUntil = planUntil
        self.effectivePlan = effectivePlan
        self.limitsEnabled = limitsEnabled
        self.features = features
    }

    /// Nil when the server sends no plan (older servers), so the app shows nothing instead of guessing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let plan = c.lenientText(.plan) else {
            throw DecodingError.keyNotFound(CodingKeys.plan, .init(codingPath: c.codingPath, debugDescription: "plan"))
        }
        self.plan = plan
        planUntil = c.lenientText(.planUntil).flatMap(Self.parseDate)
        effectivePlan = c.lenientText(.effectivePlan) ?? plan
        limitsEnabled = c.lenientBool(.limitsEnabled) ?? false
        var features: [String: Feature] = [:]
        if let raw = (try? c.decodeIfPresent([String: FeatureValue].self, forKey: .features)) ?? nil {
            for (key, value) in raw {
                if let feature = value.feature { features[key] = feature }
            }
        }
        self.features = features
    }

    /// The plan limits apply to the account and it is not on the top plan.
    public var hasExpired: Bool { plan != "free" && effectivePlan == "free" && limitsEnabled }

    public func limit(_ key: String) -> Int?? {
        if case .limit(let value)? = features[key] { return .some(value) }
        return nil
    }

    public func isEnabled(_ key: String) -> Bool? {
        if case .flag(let value)? = features[key] { return value }
        return nil
    }

    private struct FeatureValue: Decodable {
        let feature: Feature?

        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if single.decodeNil() {
                feature = .limit(nil)
            } else if let flag = try? single.decode(Bool.self) {
                feature = .flag(flag)
            } else if let number = try? single.decode(Int.self) {
                feature = .limit(number)
            } else {
                feature = nil
            }
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.date(from: String(text.prefix(10)))
    }
}

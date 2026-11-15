import Foundation

/// Reading rules for API responses: the server sends Postgres numerics as numbers or as strings, and fields may be
/// missing or null. These helpers never throw, so one odd field does not make a whole screen unreadable.
extension KeyedDecodingContainer {
    /// Non-empty text, or nil. Numbers are accepted as text (ids).
    func lenientText(_ key: Key) -> String? {
        let value: String?
        if let string = (try? decodeIfPresent(String.self, forKey: key)) ?? nil {
            value = string
        } else if let number = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil {
            value = String(number)
        } else {
            value = nil
        }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// A number sent as a number or as a string (`"50.000"`).
    func lenientNumber(_ key: Key) -> Double? {
        if let value = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil { return value }
        if let text = (try? decodeIfPresent(String.self, forKey: key)) ?? nil { return Double(text) }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let value = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil { return value }
        return lenientNumber(key).map { Int($0.rounded()) }
    }

    func lenientBool(_ key: Key) -> Bool? {
        (try? decodeIfPresent(Bool.self, forKey: key)) ?? nil
    }

    /// A list whose elements that cannot be read are left out.
    func lenientList<Element: Decodable>(_ key: Key, of _: Element.Type = Element.self) -> [Element] {
        guard let items = (try? decodeIfPresent([LenientElement<Element>].self, forKey: key)) ?? nil else { return [] }
        return items.compactMap(\.value)
    }

    /// A dictionary whose values that cannot be read are left out.
    func lenientDictionary<Value: Decodable>(_ key: Key, of _: Value.Type = Value.self) -> [String: Value] {
        guard let items = (try? decodeIfPresent([String: LenientElement<Value>].self, forKey: key)) ?? nil else {
            return [:]
        }
        return items.compactMapValues(\.value)
    }
}

/// Decodes an element or yields nil instead of failing the whole list.
struct LenientElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

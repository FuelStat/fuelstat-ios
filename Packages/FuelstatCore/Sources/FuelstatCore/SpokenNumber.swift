import Foundation

/// Reads amounts and prices as Siri transcribes them in German ("42,5", "75,30 €", "75 Euro 30",
/// "75 Euro und 30 Cent", "42 Komma 5 Liter") or as Shortcuts passes them ("75.3").
///
/// Siri cannot turn German decimal numbers into a `Double` parameter, so the intents take text and parse it here.
public enum SpokenNumber {
    public static func parse(_ text: String) -> Double? {
        var s = text.lowercased()
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // "75 Euro 30", "75 € und 30 Cent", "75 Euro 5" → euros and cents.
        if let money = euroAndCents(s) { return money }

        // Spoken separators: "42 Komma 5", "42 Punkt 5".
        s = s.replacingOccurrences(of: #"\s*\b(komma)\b\s*"#, with: ",", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*\b(punkt)\b\s*"#, with: ".", options: .regularExpression)

        // Keep digits, separators and a leading minus; drop units and currency ("l", "kWh", "€", "Euro").
        let kept = s.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
        guard kept.contains(where: \.isNumber) else { return nil }
        var number = kept.trimmingCharacters(in: CharacterSet(charactersIn: ",."))
        if number.dropFirst().contains("-") { return nil }

        let commas = number.filter { $0 == "," }.count
        let dots = number.filter { $0 == "." }.count
        if commas > 0 && dots > 0 {
            // Both separators: the last one is the decimal separator ("1.234,56" or "1,234.56").
            let decimal: Character = number.lastIndex(of: ",")! > number.lastIndex(of: ".")! ? "," : "."
            let grouping: Character = decimal == "," ? "." : ","
            number.removeAll { $0 == grouping }
            if decimal == "," { number = number.replacingOccurrences(of: ",", with: ".") }
        } else if commas == 1 {
            number = number.replacingOccurrences(of: ",", with: ".")
        } else if commas > 1 {
            number.removeAll { $0 == "," }
        } else if dots > 1 {
            number.removeAll { $0 == "." }
        } else if dots == 1, isGerman(thousands: number) {
            // "1.234" with a German thousands separator.
            number.removeAll { $0 == "." }
        }
        guard let value = Double(number), value.isFinite else { return nil }
        return value
    }

    private static func euroAndCents(_ s: String) -> Double? {
        let pattern = #"^(\d+)\s*(?:€|euro)\s*(?:und\s*)?(\d{1,2})\s*(?:cent|ct)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let euros = Range(match.range(at: 1), in: s).flatMap({ Double(s[$0]) }),
              let cents = Range(match.range(at: 2), in: s).flatMap({ Double(s[$0]) }) else { return nil }
        return euros + cents / 100
    }

    /// One dot followed by exactly three digits, with one to three digits before it.
    private static func isGerman(thousands number: String) -> Bool {
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let head = parts[0].hasPrefix("-") ? parts[0].dropFirst() : parts[0]
        return (1...3).contains(head.count) && parts[1].count == 3
    }
}

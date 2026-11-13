import Foundation

/// Icon and colour of an expense category as the API delivers them (`GET /categories`): a Font Awesome name and a
/// hex colour. The app shows SF Symbols, so the names are mapped here; the colour is only parsed.
public enum CategoryStyle {
    /// SF Symbol for a Font Awesome icon name such as `fa-shield-alt`. Unknown names get a neutral tag.
    public static func symbol(forIcon icon: String?) -> String {
        guard let icon else { return fallbackSymbol }
        return symbols[icon.trimmingCharacters(in: .whitespaces).lowercased()] ?? fallbackSymbol
    }

    public static let fallbackSymbol = "tag.fill"

    /// Red, green and blue (0…1) of a colour like `#0d6efd` or `0D6EFD`; nil when it is not a six-digit hex colour.
    public static func rgb(hex: String?) -> (red: Double, green: Double, blue: Double)? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.allSatisfy(\.isHexDigit), let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    private static let symbols: [String: String] = [
        "fa-gas-pump": "fuelpump.fill",
        "fa-shield-alt": "shield.fill",
        "fa-money-bill-wave": "banknote.fill",
        "fa-calendar-check": "checkmark.seal.fill",
        "fa-tools": "wrench.and.screwdriver.fill",
        "fa-screwdriver-wrench": "wrench.and.screwdriver.fill",
        "fa-car-crash": "exclamationmark.triangle.fill",
        "fa-cogs": "gearshape.2.fill",
        "fa-wrench": "wrench.fill",
        "fa-car-side": "car.side.fill",
        "fa-car": "car.fill",
        "fa-receipt": "doc.text.fill",
        "fa-file-invoice": "doc.text.fill",
        "fa-file-contract": "signature",
        "fa-paint-roller": "paintbrush.fill",
        "fa-brush": "paintbrush.pointed.fill",
        "fa-soap": "sparkles",
        "fa-spray-can": "sparkles",
        "fa-square-parking": "parkingsign.circle.fill",
        "fa-road": "road.lanes",
        "fa-route": "arrow.triangle.turn.up.right.diamond.fill",
        "fa-gauge-high": "gauge.with.needle.fill",
        "fa-tag": "tag.fill",
        "fa-star": "star.fill",
        "fa-heart": "heart.fill",
        "fa-car-battery": "minus.plus.batteryblock.fill",
        "fa-oil-can": "drop.fill",
        "fa-key": "key.fill",
        "fa-lock": "lock.fill",
        "fa-credit-card": "creditcard.fill",
        "fa-bolt": "bolt.fill",
        "fa-plug": "powerplug.fill",
        "fa-lightbulb": "lightbulb.fill",
        "fa-music": "music.note",
        "fa-mobile-screen": "iphone",
        "fa-camera": "camera.fill",
        "fa-ferry": "ferry.fill",
        "fa-train": "tram.fill",
        "fa-suitcase": "suitcase.fill",
        "fa-dog": "pawprint.fill",
        "fa-child": "person.fill",
        "fa-snowflake": "snowflake",
        "fa-sun": "sun.max.fill",
        "fa-umbrella": "umbrella.fill",
        "fa-box": "shippingbox.fill",
        "fa-gift": "gift.fill",
        "fa-graduation-cap": "graduationcap.fill",
        "fa-ellipsis": "ellipsis",
    ]
}

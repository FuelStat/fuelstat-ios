import Foundation

enum Fmt {
    static var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    static func pricePerUnit(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(3)))
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    static func kilometres(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) km"
    }
}

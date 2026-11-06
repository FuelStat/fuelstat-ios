import Foundation

/// Amount, price per unit and total of a fill-up: the two values entered last determine the third.
///
/// At the pump people read different numbers off the display – sometimes litres and total, sometimes litres and the
/// price per litre. Whatever two of the three were entered most recently, the remaining one is calculated.
public struct FillupAmounts: Equatable, Sendable {
    public enum Field: CaseIterable, Sendable {
        case amount, pricePerUnit, total
    }

    public private(set) var amount: Double?
    public private(set) var pricePerUnit: Double?
    public private(set) var total: Double?

    /// The fields the user entered, oldest first (at most two).
    public private(set) var entered: [Field] = []

    public init() {}

    /// The field that is calculated from the other two, or nil while fewer than two were entered.
    public var derivedField: Field? {
        guard entered.count == 2 else { return nil }
        return Field.allCases.first { !entered.contains($0) }
    }

    public mutating func set(_ field: Field, to value: Double?) {
        assign(field, value)
        entered.removeAll { $0 == field }
        if value != nil {
            entered.append(field)
            if entered.count > 2 { entered.removeFirst() }
        }
        recalculate()
    }

    private mutating func recalculate() {
        guard let derived = derivedField else { return }
        switch derived {
        case .total:
            if let amount, let pricePerUnit {
                total = Self.round(amount * pricePerUnit, digits: 2)
            }
        case .pricePerUnit:
            if let amount, let total, amount > 0 {
                pricePerUnit = Self.round(total / amount, digits: 3)
            }
        case .amount:
            if let total, let pricePerUnit, pricePerUnit > 0 {
                amount = Self.round(total / pricePerUnit, digits: 2)
            }
        }
    }

    private mutating func assign(_ field: Field, _ value: Double?) {
        switch field {
        case .amount: amount = value
        case .pricePerUnit: pricePerUnit = value
        case .total: total = value
        }
    }

    private static func round(_ value: Double, digits: Int) -> Double {
        let factor = pow(10, Double(digits))
        return (value * factor).rounded() / factor
    }
}

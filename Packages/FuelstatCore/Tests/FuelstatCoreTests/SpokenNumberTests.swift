import Testing
@testable import FuelstatCore

struct SpokenNumberTests {
    @Test(arguments: [
        ("42", 42.0), ("42,5", 42.5), ("42.5", 42.5), ("42,5 Liter", 42.5), ("42,5 l", 42.5),
        ("38,72 kWh", 38.72), ("42 Komma 5", 42.5), ("42 komma 57 Liter", 42.57),
        ("75,30 €", 75.30), ("€ 75,30", 75.30), ("75,30 Euro", 75.30), ("75 Euro 30", 75.30),
        ("75 € 30", 75.30), ("75 Euro und 30 Cent", 75.30), ("75 Euro 5", 75.05), ("75 Euro", 75.0),
        ("1.234,56 €", 1234.56), ("1,234.56", 1234.56), ("1.234", 1234.0), ("1.5", 1.5), ("0,99", 0.99),
        ("  89,9  ", 89.9), ("12,", 12.0),
    ] as [(String, Double)])
    func parses(text: String, expected: Double) throws {
        let value = try #require(SpokenNumber.parse(text))
        #expect(abs(value - expected) < 0.0001)
    }

    @Test(arguments: ["", "   ", "Euro", "keine Ahnung", "1-2"])
    func rejects(text: String) {
        #expect(SpokenNumber.parse(text) == nil)
    }
}

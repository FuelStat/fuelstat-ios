import Foundation
import Testing
@testable import FuelstatCore

struct CategoryStyleTests {
    @Test func mapsKnownIcons() {
        #expect(CategoryStyle.symbol(forIcon: "fa-shield-alt") == "shield.fill")
        #expect(CategoryStyle.symbol(forIcon: " FA-Wrench ") == "wrench.fill")
    }

    @Test func unknownIconsGetTheFallback() {
        #expect(CategoryStyle.symbol(forIcon: "fa-does-not-exist") == CategoryStyle.fallbackSymbol)
        #expect(CategoryStyle.symbol(forIcon: nil) == CategoryStyle.fallbackSymbol)
    }

    @Test func parsesHexColours() throws {
        let blue = try #require(CategoryStyle.rgb(hex: "#0d6efd"))
        #expect(abs(blue.red - 13.0 / 255) < 0.0001)
        #expect(abs(blue.green - 110.0 / 255) < 0.0001)
        #expect(abs(blue.blue - 253.0 / 255) < 0.0001)
        #expect(CategoryStyle.rgb(hex: "FFFFFF")?.red == 1)
    }

    @Test func rejectsOtherColourFormats() {
        #expect(CategoryStyle.rgb(hex: "#fff") == nil)
        #expect(CategoryStyle.rgb(hex: "#gggggg") == nil)
        #expect(CategoryStyle.rgb(hex: "+12345") == nil)
        #expect(CategoryStyle.rgb(hex: nil) == nil)
    }
}

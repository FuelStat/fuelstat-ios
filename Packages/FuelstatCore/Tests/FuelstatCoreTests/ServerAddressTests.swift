import Foundation
import Testing
@testable import FuelstatCore

struct ServerAddressTests {
    @Test(arguments: [
        "tanken.example.de",
        "tanken.example.de/",
        "https://tanken.example.de",
        "https://Tanken.Example.de/",
        "https://tanken.example.de/api/v1",
        "https://tanken.example.de/api/v1/",
        "  https://tanken.example.de  ",
    ])
    func normalisesToAPIBase(input: String) {
        #expect(ServerAddress.apiBaseURL(from: input)?.absoluteString == "https://tanken.example.de/api/v1")
    }

    @Test func keepsPortAndSubPath() {
        #expect(ServerAddress.apiBaseURL(from: "fuel.local:8443/fuelstat")?.absoluteString
            == "https://fuel.local:8443/fuelstat/api/v1")
    }

    @Test(arguments: ["", "   ", "http://tanken.example.de", "ftp://x.de", "https://", "a b.de",
                      "https://x.de/?q=1", "https://user:pw@x.de"])
    func rejectsInvalidInput(input: String) {
        #expect(ServerAddress.apiBaseURL(from: input) == nil)
    }

    @Test func displayNameDropsSchemeAndAPIPath() {
        let url = URL(string: "https://fuel.local:8443/fuelstat/api/v1")!
        #expect(ServerAddress.displayName(of: url) == "fuel.local:8443/fuelstat")
        #expect(ServerAddress.displayName(of: URL(string: "https://tanken.1emc.de/api/v1")!) == "tanken.1emc.de")
    }
}

struct ImageCacheKeyTests {
    @Test func signedURLsOfTheSameFileShareAKey() {
        let today = URL(string: "https://x.de/api/v1/files/3f2c0d1e-0000-4000-8000-000000000000.webp?exp=1&sig=a")!
        let tomorrow = URL(string: "https://x.de/api/v1/files/3f2c0d1e-0000-4000-8000-000000000000.webp?exp=2&sig=b")!
        #expect(ImageCacheKey.key(for: today) == "3f2c0d1e-0000-4000-8000-000000000000.webp")
        #expect(ImageCacheKey.key(for: today) == ImageCacheKey.key(for: tomorrow))
    }

    @Test func otherURLsGetAFileSystemSafeKey() {
        let key = ImageCacheKey.key(for: URL(string: "https://cdn.example.com/a/b.jpg?x=1")!)
        #expect(!key.contains("/"))
        #expect(!key.contains("?"))
    }
}

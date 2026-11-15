import Foundation
import Testing
@testable import FuelstatCore

struct MailLinksTests {
    @Test func bareCodeIsTheToken() {
        #expect(MailToken.extract(from: "  abc_DEF-123  ") == "abc_DEF-123")
    }

    @Test func tokenIsTakenFromAPastedLink() {
        #expect(MailToken.extract(from: "https://tanken.1emc.de/pages/email_bestaetigen.php?token=abc123&quelle=app") == "abc123")
        #expect(MailToken.extract(from: "fuelstat://reset-password?token=xyz&server=tanken.1emc.de") == "xyz")
        #expect(MailToken.extract(from: "https://example.org/pages/x.php?token=a%2Fb") == "a/b")
    }

    @Test func emptyOrMultiWordInputHasNoToken() {
        #expect(MailToken.extract(from: "") == nil)
        #expect(MailToken.extract(from: "   \n") == nil)
        #expect(MailToken.extract(from: "das ist kein code") == nil)
        #expect(MailToken.extract(from: "https://example.org/ohne-token") == nil)
    }

    @Test func resetLinkRoundTrips() throws {
        let link = AppLink.resetPassword(token: "a-b_c", server: "tanken.1emc.de")
        #expect(AppLink(url: link.url) == link)
        let parsed = AppLink(url: try #require(URL(string: "fuelstat://reset-password?token=abc&server=https%3A%2F%2Ftanken.1emc.de")))
        #expect(parsed == .resetPassword(token: "abc", server: "https://tanken.1emc.de"))
    }

    @Test func confirmedLinkAndMissingToken() throws {
        #expect(AppLink(url: try #require(URL(string: "fuelstat://email-bestaetigt?server=tanken.1emc.de")))
                == .emailConfirmed(server: "tanken.1emc.de"))
        #expect(AppLink(url: try #require(URL(string: "fuelstat://email-bestaetigt"))) == .emailConfirmed(server: nil))
        #expect(AppLink(url: try #require(URL(string: "fuelstat://reset-password"))) == nil, "a reset link needs a token")
        #expect(AppLink.emailConfirmed(server: nil).url.absoluteString == "fuelstat://email-bestaetigt")
    }

    @Test func serverIsComparedByHostAndPort() throws {
        let api = try #require(URL(string: "https://tanken.1emc.de/api/v1"))
        #expect(MailServer.matches(linkServer: "tanken.1emc.de", current: api))
        #expect(MailServer.matches(linkServer: "https://TANKEN.1emc.de/", current: api))
        #expect(MailServer.matches(linkServer: "https://tanken.1emc.de:443", current: api))
        #expect(MailServer.matches(linkServer: nil, current: api), "no server in the link: nothing to compare")
        #expect(MailServer.matches(linkServer: "", current: api))
        #expect(!MailServer.matches(linkServer: "other.example.org", current: api))
        #expect(!MailServer.matches(linkServer: "https://tanken.1emc.de:8443", current: api))
        let own = try #require(URL(string: "http://192.168.1.5:3000/api/v1"))
        #expect(MailServer.matches(linkServer: "http://192.168.1.5:3000", current: own))
        #expect(!MailServer.matches(linkServer: "http://192.168.1.5", current: own))
    }

    @Test func accountsAreComparedIgnoringCase() {
        #expect(MailAccount.compare(signedIn: "Max@Beispiel.de", affected: " max@beispiel.de ") == .own)
        #expect(MailAccount.compare(signedIn: "max@beispiel.de", affected: "anna@beispiel.de") == .other(email: "anna@beispiel.de"))
        #expect(MailAccount.compare(signedIn: nil, affected: "anna@beispiel.de") == .other(email: "anna@beispiel.de"))
        #expect(MailAccount.compare(signedIn: "max@beispiel.de", affected: nil) == .unknown)
        #expect(MailAccount.compare(signedIn: "max@beispiel.de", affected: "") == .unknown)
    }
}

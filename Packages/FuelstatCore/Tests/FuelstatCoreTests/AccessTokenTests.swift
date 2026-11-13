import Foundation
import Testing
@testable import FuelstatCore

struct AccessTokenTests {
    /// Builds an unsigned JWT with the given payload, base64url-encoded like the server's.
    private func token(_ payload: String) -> String {
        func encode(_ text: String) -> String {
            Data(text.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encode(#"{"alg":"HS256","typ":"JWT"}"#)).\(encode(payload)).signature"
    }

    @Test func readsTheExpiry() {
        let jwt = token(#"{"sub":"a","exp":1800000000,"sid":"s"}"#)
        #expect(AccessToken.expiry(of: jwt) == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func handlesPayloadsThatNeedPadding() {
        // 1, 2 and 3 padding characters after base64url decoding
        for payload in [#"{"exp":1800000000}"#, #"{"exp":1800000000,"a":1}"#, #"{"exp":1800000000,"ab":1}"#] {
            #expect(AccessToken.expiry(of: token(payload)) == Date(timeIntervalSince1970: 1_800_000_000))
        }
    }

    @Test func renewsShortlyBeforeTheEnd() {
        let jwt = token(#"{"exp":1000}"#)
        #expect(AccessToken.needsRenewal(jwt, now: Date(timeIntervalSince1970: 900)))
        #expect(AccessToken.needsRenewal(jwt, now: Date(timeIntervalSince1970: 1100)))
        #expect(!AccessToken.needsRenewal(jwt, now: Date(timeIntervalSince1970: 500)))
    }

    @Test func unreadableTokensCountAsValid() {
        #expect(AccessToken.expiry(of: "not-a-jwt") == nil)
        #expect(AccessToken.expiry(of: token(#"{"sub":"no-exp"}"#)) == nil)
        #expect(AccessToken.expiry(of: "a.%%%.c") == nil)
        #expect(!AccessToken.needsRenewal("not-a-jwt"))
    }
}

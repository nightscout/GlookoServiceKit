import XCTest
@testable import GlookoServiceKit

final class DomainTests: XCTestCase {

    func testRegionHostPrefix() {
        XCTAssertNil(GlookoClassicRegion.auto.hostPrefix)
        XCTAssertEqual(GlookoClassicRegion.eu.hostPrefix, "eu")
        XCTAssertEqual(GlookoClassicRegion.us.hostPrefix, "us")
    }

    func testRegionDisplayNames() {
        XCTAssertEqual(GlookoClassicRegion.auto.displayName, "Auto-detect")
        XCTAssertEqual(GlookoClassicRegion.eu.displayName, "Europe (eu)")
        XCTAssertEqual(GlookoClassicRegion.us.displayName, "United States (us)")
    }

    func testRegionCases() {
        XCTAssertEqual(GlookoClassicRegion.allCases.count, 3)
    }

    func testGlucoseUnitMgdl() {
        XCTAssertEqual(GlucoseUnitPreference.mgdl.encode(mgdl: 123.4), 123)
    }

    func testGlucoseUnitMmol() {
        XCTAssertEqual(GlucoseUnitPreference.mmol.encode(mgdl: 100), 5.6, accuracy: 0.01)
        XCTAssertEqual(GlucoseUnitPreference.mmol.encode(mgdl: 90), 5.0, accuracy: 0.01)
    }

    func testVariantTitles() {
        XCTAssertEqual(GlookoVariant.xt.localizedTitle, "Glooko XT")
        XCTAssertEqual(GlookoVariant.classic.localizedTitle, "Glooko")
        XCTAssertEqual(GlookoVariant.allCases.count, 2)
    }

    func testErrorDescriptions() {
        XCTAssertEqual(GlookoAPIError.http(404).errorDescription, "HTTP 404")
        XCTAssertEqual(GlookoAPIError.noToken.errorDescription, "Missing authentication")
        XCTAssertEqual(GlookoAPIError.server("x").errorDescription, "Server error: x")
        XCTAssertEqual(GlookoAPIError.notConnected.errorDescription, "Not connected")
        XCTAssertEqual(GlookoAPIError.encoding.errorDescription, "Encoding failure")
    }

    func testErrorEquatable() {
        XCTAssertEqual(GlookoAPIError.http(204), GlookoAPIError.http(204))
        XCTAssertNotEqual(GlookoAPIError.http(204), GlookoAPIError.http(422))
    }

    func testSignInMapsKnownCodes() {
        let badCode = GlookoAPIError.signIn(status: 500, body: Data(#"{"error":"CANNOT_UPDATE_USER"}"#.utf8))
        XCTAssertEqual(badCode.errorDescription, "Invalid or expired code. Please request a new one.")
        let badCreds = GlookoAPIError.signIn(status: 422, body: Data(#"{"error":"WRONG_INPUT"}"#.utf8))
        XCTAssertEqual(badCreds.errorDescription, "Sign-in failed: check your email and password.")
    }

    func testSignInMapsByStatus() {
        XCTAssertEqual(GlookoAPIError.signIn(status: 401, body: nil).errorDescription,
                       "Sign-in failed: check your email and password.")
        XCTAssertEqual(GlookoAPIError.signIn(status: 422, body: nil).errorDescription,
                       "Sign-in failed: this account or input wasn’t accepted by Glooko.")
        if case .auth(let m) = GlookoAPIError.signIn(status: 500, body: nil) {
            XCTAssertTrue(m.contains("server error"))
        } else { XCTFail("expected .auth") }
        if case .auth(let m) = GlookoAPIError.signIn(status: 418, body: nil) {
            XCTAssertTrue(m.contains("418"))
        } else { XCTFail("expected .auth") }
    }

    func testServerMessageExtraction() {
        XCTAssertEqual(GlookoSignInMessage.serverMessage(from: Data(#"{"message":"hi"}"#.utf8)), "hi")
        XCTAssertNil(GlookoSignInMessage.serverMessage(from: nil))
        XCTAssertNil(GlookoSignInMessage.serverMessage(from: Data("notjson".utf8)))
    }

    func testGlucoseUnitMmolUsesExactFactor() {
        XCTAssertEqual(GlucoseUnitPreference.mmol.encode(mgdl: 180), 10.0, accuracy: 0.001)
        XCTAssertEqual(GlucoseUnitPreference.mmol.encode(mgdl: 54), 3.0, accuracy: 0.001)
    }

    func testGUIDIsDeterministicAndVersioned() {
        let a = GlookoGUID.make("seed")
        XCTAssertEqual(a, GlookoGUID.make("seed"))
        XCTAssertNotEqual(a, GlookoGUID.make("seed2"))
        XCTAssertEqual(a, a.lowercased())
        XCTAssertNotNil(UUID(uuidString: a))
        let chars = Array(a)
        XCTAssertEqual(chars[14], "5")
        XCTAssertTrue("89ab".contains(chars[19]))
    }

    func testGUIDNamespacesDiffer() {
        let ids = [GlookoGUID.bolus("x"), GlookoGUID.food("x"), GlookoGUID.reading("x"),
                   GlookoGUID.basalHour(Date(timeIntervalSince1970: 3600))]
        XCTAssertEqual(Set(ids).count, 4)
        XCTAssertEqual(GlookoGUID.bolus("x"), GlookoGUID.make("trio-insulin-bolus|x"))
        XCTAssertEqual(GlookoGUID.basalHour(Date(timeIntervalSince1970: 7200)), GlookoGUID.make("trio-insulin-basal|7200"))
    }

    func testRedactionStripsSecrets() {
        let text = GlookoRedact.text(#"user Jane.Doe@Example.org failed, _logbook-web_session=abc123; "token":"t0k3n" eyJhbGciOiJIUzI1.eyJpZCI6MTIzNDU2.c2lnbmF0dXJlMTI"#)
        XCTAssertFalse(text.contains("Jane.Doe"))
        XCTAssertFalse(text.contains("abc123"))
        XCTAssertFalse(text.contains("t0k3n"))
        XCTAssertFalse(text.contains("eyJhbGciOiJIUzI1"))
        XCTAssertTrue(text.contains("<email>"))
    }

    func testClientIdentityIsHonest() {
        let identity = GlookoClientIdentity(hostIdentifier: "org.nightscout.Trio", hostVersion: "1.2.3")
        XCTAssertEqual(identity.sourceName, "Trio")
        XCTAssertTrue(identity.userAgent.hasPrefix("GlookoServiceKit (org.nightscout.Trio/1.2.3"))
        XCTAssertTrue(identity.userAgent.contains("github.com/nightscout/GlookoServiceKit"))
        XCTAssertFalse(identity.userAgent.contains("GlookoAndroid"))
    }

    func testUploadErrorIsNotASignInError() {
        let error = GlookoAPIError.upload("insulins", status: 422, body: Data(#"{"error":"bad for a@b.com"}"#.utf8))
        guard case let .upload(endpoint, status, message) = error else { return XCTFail("expected .upload") }
        XCTAssertEqual(endpoint, "insulins")
        XCTAssertEqual(status, 422)
        XCTAssertFalse(message?.contains("a@b.com") ?? true)
        XCTAssertFalse(error.errorDescription?.contains("password") ?? true)
        XCTAssertNil(GlookoAPIError.upload("x", status: 500, body: Data()).uploadMessage)
    }

    func testSignInGenericMessageIsRedacted() {
        let error = GlookoAPIError.signIn(status: 418, body: Data(#"{"message":"locked for a@b.com"}"#.utf8))
        XCTAssertFalse(error.errorDescription?.contains("a@b.com") ?? true)
    }
}

private extension GlookoAPIError {
    var uploadMessage: String? {
        guard case let .upload(_, _, message) = self else { return nil }
        return message
    }
}

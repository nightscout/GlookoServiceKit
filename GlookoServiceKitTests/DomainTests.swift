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

    func testDeflateProducesZlibStream() {
        let payload = Data((0 ..< 500).map { UInt8($0 % 251) })
        let out = try XCTUnwrap(GlookoDeflate.zlib(payload))
        XCTAssertEqual(Array(out.prefix(2)), [0x78, 0x9c])
        XCTAssertGreaterThan(out.count, 6)
        XCTAssertNil(GlookoDeflate.zlib(Data()))
    }
}

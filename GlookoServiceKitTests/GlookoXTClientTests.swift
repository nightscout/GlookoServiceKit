import XCTest
import LoopKit
@testable import GlookoServiceKit

final class GlookoXTClientTests: XCTestCase {

    private func jwt(id: Int) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: ["id": id])
        let b64 = payload.base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "h.\(b64).s"
    }

    func testRequestCodePostsCredentials() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req) }
        try await GlookoXTClient(transport: mock).requestCode(email: "a@b.co", password: "pw")
        XCTAssertEqual(mock.requests.last?.url?.absoluteString, "https://srv.glookoxt.com/api/users/patient-login/")
        XCTAssertEqual(mock.bodyJSON(at: 0)?["email"] as? String, "a@b.co")
        XCTAssertEqual(mock.bodyJSON(at: 0)?["password"] as? String, "pw")
    }

    func testAuthenticateReturnsTokenFromResponse() async throws {
        let token = jwt(id: 42)
        let body = try JSONSerialization.data(withJSONObject: ["token": token])
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req, body: body) }
        let client = GlookoXTClient(transport: mock)
        let returned = try await client.authenticate(email: "a@b.co", code: "1234")
        XCTAssertEqual(returned, token)
        XCTAssertEqual(client.token, token)
        XCTAssertEqual(client.patientId, "42")
    }

    func testAuthenticateThrowsWhenNoToken() async {
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req, body: Data("{}".utf8)) }
        do {
            _ = try await GlookoXTClient(transport: mock).authenticate(email: "a@b.co", code: "1234")
            XCTFail("expected noToken")
        } catch {
            XCTAssertEqual(error as? GlookoAPIError, .noToken)
        }
    }

    func testFailedSignInMapsToAuthError() async {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 401) }
        do {
            try await GlookoXTClient(transport: mock).requestCode(email: "a@b.co", password: "pw")
            XCTFail("expected auth error")
        } catch {
            guard case .auth = (error as? GlookoAPIError) else { return XCTFail("expected .auth, got \(error)") }
        }
    }

    func testPatientIdNilWithoutToken() {
        XCTAssertNil(GlookoXTClient().patientId)
    }

    func testUploadIBFPostsMultipartWithReferenceWindow() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req) }
        let client = GlookoXTClient(token: jwt(id: 7), transport: mock)
        try await client.uploadIBF(Data([1, 2, 3]), reference: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(mock.paths.last, "/api/upload/ibf")
        let req = try XCTUnwrap(mock.requests.last)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(jwt(id: 7))")
        let text = String(decoding: try XCTUnwrap(req.httpBody), as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"document\"; filename=\"trio.ibf\""))
        XCTAssertTrue(text.contains("1969-12-02"))
        XCTAssertTrue(text.contains("1970-01-02"))
    }

    func testUploadIBFThrowsWithoutToken() async {
        do {
            try await GlookoXTClient().uploadIBF(Data([1]))
            XCTFail("expected noToken")
        } catch {
            XCTAssertEqual(error as? GlookoAPIError, .noToken)
        }
    }

    func testRequestsCarryHonestUserAgent() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req) }
        let identity = GlookoClientIdentity(hostIdentifier: "org.nightscout.Trio", hostVersion: "1.0")
        try await GlookoXTClient(identity: identity, transport: mock).requestCode(email: "a@b.co", password: "pw")
        XCTAssertEqual(mock.requests.last?.value(forHTTPHeaderField: "User-Agent"), identity.userAgent)
    }

    func testMultipartFieldOrderIsStable() {
        let body = String(decoding: GlookoXTClient.multipartBody(boundary: "B", ibf: Data([9]),
                                                                fields: [("patient_id", "1"), ("startDate", "s"), ("endDate", "e")]),
                          as: UTF8.self)
        let order = ["patient_id", "startDate", "endDate", "document"].compactMap { body.range(of: "name=\"\($0)\"")?.lowerBound }
        XCTAssertEqual(order.count, 4)
        XCTAssertEqual(order, order.sorted())
    }

    func testUploadIBFFailureIsUploadError() async {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 500) }
        do {
            try await GlookoXTClient(token: jwt(id: 7), transport: mock).uploadIBF(Data([1]))
            XCTFail("expected upload error")
        } catch {
            guard case .upload(endpoint: "upload/ibf", status: 500, message: _) = error as? GlookoAPIError else {
                return XCTFail("expected .upload, got \(error)")
            }
        }
    }

    func testUploadIBFUnauthorizedNeedsSignIn() async {
        for status in [401, 403] {
            let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, status) }
            do {
                try await GlookoXTClient(token: jwt(id: 7), transport: mock).uploadIBF(Data([1]))
                XCTFail("expected authenticationRequired")
            } catch {
                XCTAssertEqual(error as? GlookoAPIError, .authenticationRequired)
            }
        }
    }

    func testXTUploadDosesSendsNothing() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req) }
        let backend = GlookoXTBackend(configuration: GlookoService.Configuration(), token: jwt(id: 7),
                                      api: GlookoXTClient(token: jwt(id: 7), transport: mock))
        let now = Date()
        try await backend.uploadDoses(created: [DoseEntry(type: .bolus, startDate: now, endDate: now, value: 2, unit: .units)],
                                      deleted: [DoseEntry(type: .bolus, startDate: now, endDate: now, value: 1, unit: .units)])
        // An unconnected socket throws on any moments send, so returning proves nothing was emitted.
        XCTAssertTrue(mock.requests.isEmpty)
    }
}

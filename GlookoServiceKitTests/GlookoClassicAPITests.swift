import XCTest
@testable import GlookoServiceKit

final class GlookoClassicAPITests: XCTestCase {

    private let cookie = "_logbook-web_session=abc; path=/; HttpOnly"

    func testEmailHashIsLowercasedTrimmedSHA256() {

        XCTAssertEqual(GlookoClassicAPI.emailHash("  A  "),
                       "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb")
        XCTAssertEqual(GlookoClassicAPI.emailHash("a").count, 64)
    }

    func testISOIsLocalAndRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let iso = GlookoClassicAPI.iso(date)
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(parser.date(from: iso), date)
        let offset = TimeZone.current.secondsFromGMT(for: date)
        XCTAssertEqual(iso.hasSuffix("Z"), offset == 0)
    }

    func testHasSession() {
        XCTAssertFalse(GlookoClassicAPI(region: .eu, transport: MockHTTPTransport { r, _ in try MockResponder.ok(r) }).hasSession)
        XCTAssertTrue(GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: MockHTTPTransport { r, _ in try MockResponder.ok(r) }).hasSession)
    }

    func testSignInCapturesCookie() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req, setCookie: self.cookie) }
        let api = GlookoClassicAPI(region: .eu, transport: mock)
        try await api.signIn(email: "USER@X.com", password: "pw")
        XCTAssertEqual(api.sessionCookie, "_logbook-web_session=abc")
        let request = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v2/users/sign_in")
        let login = try XCTUnwrap(mock.bodyJSON(at: 0)?["userLogin"] as? [String: Any])
        XCTAssertEqual(login["email"] as? String, "user@x.com")
    }

    func testSignInNoCookieThrows() async {
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req) }
        let api = GlookoClassicAPI(region: .eu, transport: mock)
        await XCTAssertThrowsErrorAsync(try await api.signIn(email: "a", password: "b"))
    }

    func testSignIn422Throws() async {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 422) }
        let api = GlookoClassicAPI(region: .eu, transport: mock)
        await XCTAssertThrowsErrorAsync(try await api.signIn(email: "a", password: "b"))
    }

    func testEnsureSessionNoCredentialsThrows() async {
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req) }
        let api = GlookoClassicAPI(region: .eu, transport: mock)
        await XCTAssertThrowsErrorAsync(try await api.ensureSession())
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testEnsureSessionSkipsWhenCookiePresent() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req) }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: mock)
        try await api.ensureSession()
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testEnsureSessionAutoResolvesThenSignsIn() async throws {
        let regionBody = Data(#"{"urls":{"apiBase":"https://us.patient-api.glooko.com"}}"#.utf8)
        let mock = MockHTTPTransport { req, _ in
            if req.url?.path == "/api/v2/users/region" { return (regionBody, try MockResponder.response(req, status: 200)) }
            return try MockResponder.ok(req, setCookie: self.cookie)
        }
        let api = GlookoClassicAPI(region: .auto, credentials: ("a@b.com", "pw"), transport: mock)
        try await api.ensureSession()
        XCTAssertEqual(mock.requests.first?.url?.path, "/api/v2/users/region")
        XCTAssertEqual(mock.requests.last?.url?.host, "us.patient-api.glooko.com")
        XCTAssertEqual(api.sessionCookie, "_logbook-web_session=abc")
    }

    func testPutBuildsEnvelopeAndSucceeds() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: mock)
        try await api.put(endpoint: "readings", jsonName: "readings",
                          items: [GKReading(guid: "g", syncTimestamp: "s", timestamp: "t", value: 5, userMealTag: 0)])
        let request = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v2/readings")
        XCTAssertNotNil(mock.bodyJSON(at: 0)?["readings"])
    }

    func testPutSyncEventsUsesPOST() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: mock)
        try await api.put(endpoint: "sync_events", jsonName: "syncEvents",
                          items: [GKNote(guid: "g", syncTimestamp: "s", timestamp: "t", value: "x")])
        XCTAssertEqual(mock.requests.first?.httpMethod, "POST")
    }

    func testPutEmptyItemsSendsNothing() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: mock)
        try await api.put(endpoint: "readings", jsonName: "readings", items: [GKReading]())
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testPutErrorThrows() async {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 422, body: Data(#"{"error":"bad"}"#.utf8)) }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: mock)
        await XCTAssertThrowsErrorAsync(
            try await api.put(endpoint: "readings", jsonName: "readings",
                              items: [GKReading(guid: "g", syncTimestamp: "s", timestamp: "t", value: 1, userMealTag: 0)]))
    }

    func testPutRetriesOnceAfter401() async throws {
        var readingsCalls = 0
        let mock = MockHTTPTransport { req, _ in
            switch req.url?.path {
            case "/api/v2/users/sign_in": return try MockResponder.ok(req, setCookie: self.cookie)
            case "/api/v2/readings":
                readingsCalls += 1
                return try MockResponder.status(req, readingsCalls == 1 ? 401 : 204)
            default: return try MockResponder.status(req, 204)
            }
        }
        let api = GlookoClassicAPI(region: .eu, credentials: ("a@b.com", "pw"), transport: mock)
        try await api.put(endpoint: "readings", jsonName: "readings",
                          items: [GKReading(guid: "g", syncTimestamp: "s", timestamp: "t", value: 1, userMealTag: 0)])
        XCTAssertEqual(readingsCalls, 2)
        XCTAssertEqual(mock.requests.map { $0.url?.path },
                       ["/api/v2/readings", "/api/v2/users/sign_in", "/api/v2/readings"])
    }

    func testUploadDeviceFileOctetStream() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 200) }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: mock)
        try await api.uploadDeviceFile(Data("CSV".utf8))
        let request = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v3/device/file/upload")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-type"), "application/octet-stream")
        XCTAssertTrue(request.url?.query?.contains("extractorName=LibreviewCSV") ?? false)
        XCTAssertEqual(request.httpBody, Data("CSV".utf8))
    }

    func testUploadDeviceFileErrorThrows() async {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 400) }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: mock)
        await XCTAssertThrowsErrorAsync(try await api.uploadDeviceFile(Data("x".utf8)))
    }

    func testInvalidateClearsCookie() {
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: MockHTTPTransport { r, _ in try MockResponder.ok(r) })
        api.invalidate()
        XCTAssertNil(api.sessionCookie)
    }
}

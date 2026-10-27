import XCTest
@testable import GlookoServiceKit

final class GlookoClassicAuthTests: XCTestCase {

    private let cookie = "_logbook-web_session=abc; path=/; HttpOnly"
    private let identity = GlookoClientIdentity(hostIdentifier: "org.nightscout.Trio", hostVersion: "1.0")

    private func reading() -> [GKReading] {
        [GKReading(guid: "g", syncTimestamp: "s", timestamp: "t", value: 1, userMealTag: 0)]
    }

    func testSignInFallsBackFromV3ToV2() async throws {
        let mock = MockHTTPTransport { req, _ in
            req.url?.path == "/api/v3/users/sign_in"
                ? try MockResponder.status(req, 404)
                : try MockResponder.ok(req, setCookie: self.cookie)
        }
        let api = GlookoClassicAPI(region: .eu, transport: mock)
        try await api.signIn(email: "a@b.c", password: "pw")
        XCTAssertEqual(mock.paths, ["/api/v3/users/sign_in", "/api/v2/users/sign_in"])
        XCTAssertNotNil(mock.bodyJSON(at: 1)?["userLogin"])
        XCTAssertEqual(api.sessionCookie, "_logbook-web_session=abc")
    }

    func testSignInRejectionDoesNotRotate() async {
        for status in [401, 403, 423, 429] {
            let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, status) }
            let api = GlookoClassicAPI(region: .eu, transport: mock)
            await XCTAssertThrowsErrorAsync(try await api.signIn(email: "a@b.c", password: "pw"))
            XCTAssertEqual(mock.requests.count, 1, "status \(status)")
        }
    }

    func testSignInWithoutCookieTriesBothThenFails() async {
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req) }
        let api = GlookoClassicAPI(region: .eu, transport: mock)
        await XCTAssertThrowsErrorAsync(try await api.signIn(email: "a@b.c", password: "pw"))
        XCTAssertEqual(mock.requests.count, 2)
    }

    func testTwoFactorFlagHoldsSessionBack() async throws {
        let body = Data(#"{"two_fa_required":true}"#.utf8)
        let mock = MockHTTPTransport { req, _ in try MockResponder.ok(req, body: body, setCookie: self.cookie) }
        let api = GlookoClassicAPI(region: .eu, credentials: ("a@b.c", "pw"), transport: mock)
        await XCTAssertThrowsErrorAsync(try await api.ensureSession()) {
            XCTAssertEqual($0 as? GlookoAPIError, .twoFactorRequired)
        }
        XCTAssertNil(api.sessionCookie)
        XCTAssertTrue(api.awaitingTwoFactor)
    }

    func testRequestsCarryHonestIdentityOnly() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", identity: identity, transport: mock)
        try await api.put(endpoint: "readings", jsonName: "readings", items: reading())
        let request = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), identity.userAgent)
        XCTAssertNil(request.value(forHTTPHeaderField: "DeviceInformation"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Glooko-API-Key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "c")
    }

    func testConcurrentExpiryShareOneSignIn() async throws {
        let lock = NSLock()
        var signIns = 0
        let mock = MockHTTPTransport { req, _ in
            if req.url?.path == "/api/v3/users/sign_in" {
                lock.lock(); signIns += 1; lock.unlock()
                return try MockResponder.ok(req, setCookie: "_logbook-web_session=new")
            }
            let fresh = req.value(forHTTPHeaderField: "Cookie") == "_logbook-web_session=new"
            return try MockResponder.status(req, fresh ? 204 : 401)
        }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "old", credentials: ("a@b.c", "pw"), transport: mock)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 5 {
                group.addTask { try await api.put(endpoint: "readings", jsonName: "readings", items: self.reading()) }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(signIns, 1)
    }

    func testReauthIsRateLimited() async throws {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        var signIns = 0
        let mock = MockHTTPTransport { req, _ in
            if req.url?.path == "/api/v3/users/sign_in" {
                signIns += 1
                return try MockResponder.ok(req, setCookie: "_logbook-web_session=s\(signIns)")
            }
            return try MockResponder.status(req, 401)
        }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "old", credentials: ("a@b.c", "pw"),
                                   transport: mock, now: { clock })
        await XCTAssertThrowsErrorAsync(try await api.put(endpoint: "readings", jsonName: "readings", items: reading())) {
            XCTAssertEqual($0 as? GlookoAPIError, .authenticationRequired)
        }
        XCTAssertEqual(signIns, 1)

        clock += 60
        await XCTAssertThrowsErrorAsync(try await api.put(endpoint: "readings", jsonName: "readings", items: reading())) {
            XCTAssertEqual($0 as? GlookoAPIError, .authenticationRequired)
        }
        XCTAssertEqual(signIns, 1)

        clock += GlookoClassicAPI.reauthInterval
        await XCTAssertThrowsErrorAsync(try await api.put(endpoint: "readings", jsonName: "readings", items: reading()))
        XCTAssertEqual(signIns, 2)
    }

    func testExpiryWithoutCredentialsIsAuthRequired() async {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 401) }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: mock)
        await XCTAssertThrowsErrorAsync(try await api.put(endpoint: "readings", jsonName: "readings", items: reading())) {
            XCTAssertEqual($0 as? GlookoAPIError, .authenticationRequired)
        }
        XCTAssertEqual(mock.requests.count, 1)
    }

    func testSyncCompletePostsUTCTimestamp() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: mock,
                                   now: { Date(timeIntervalSince1970: 0) })
        try await api.syncComplete()
        let request = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v3/users/activities_and_event_data_sync/complete")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
            .queryItems?.first?.value, "1970-01-01T00:00:00.000Z")
    }
}

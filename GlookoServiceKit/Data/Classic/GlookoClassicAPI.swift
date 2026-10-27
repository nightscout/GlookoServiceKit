import Foundation
import CryptoKit

public final class GlookoClassicAPI {
    public static let globalBaseString = GlookoConstants.Classic.globalBase
    static let reauthInterval: TimeInterval = 300
    static let rejectedStatuses: Set<Int> = [401, 403, 423, 429]
    static let expiredStatuses: Set<Int> = [401, 421]

    private let region: GlookoClassicRegion
    private let transport: GlookoHTTPTransport
    private let credentials: (email: String, password: String)?
    private let identity: GlookoClientIdentity
    private let now: () -> Date

    private let lock = NSLock()
    private var baseString: String
    private var cookie: String?
    private var twoFactorPending = false
    private var pendingEmail: String?
    private var signInTask: Task<Void, Error>?
    private var lastSignIn: Date?

    public init(region: GlookoClassicRegion = .eu,
                sessionCookie: String? = nil,
                credentials: (email: String, password: String)? = nil,
                identity: GlookoClientIdentity = GlookoClientIdentity(),
                transport: GlookoHTTPTransport = URLSessionTransport(),
                now: @escaping () -> Date = Date.init) {
        self.region = region
        self.cookie = sessionCookie
        self.credentials = credentials
        self.identity = identity
        self.transport = transport
        self.now = now
        self.baseString = GlookoConstants.Classic.patientApiBase(prefix: region.hostPrefix ?? "eu")
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    public var awaitingTwoFactor: Bool { locked { twoFactorPending } }
    public var hasSession: Bool { locked { (cookie != nil && !twoFactorPending) } || credentials != nil }
    public var sessionCookie: String? { locked { twoFactorPending ? nil : cookie } }
    public func invalidate() { locked { cookie = nil; twoFactorPending = false; pendingEmail = nil } }

    public static func emailHash(_ email: String) -> String {
        let digest = SHA256.hash(data: Data(email.lowercased().trimmingCharacters(in: .whitespaces).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func iso(_ date: Date) -> String { GlookoDate.iso(date, timeZone: .current) }
    public static func utc(_ date: Date) -> String { GlookoDate.iso(date) }

    private func url(base: String? = nil, path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: base ?? locked({ baseString })) else { throw GlookoAPIError.encoding }
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let made = components.url else { throw GlookoAPIError.encoding }
        return made
    }

    private func decorate(_ request: inout URLRequest, contentType: String = "application/json") {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-type")
        request.setValue(identity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US", forHTTPHeaderField: "GlookoOverrideLocale")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "x-timezone")
        guard let cookie = locked({ cookie }) else { return }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
    }

    public func resolveRegion(email: String) async throws {
        var request = URLRequest(url: try url(base: Self.globalBaseString, path: "/api/v2/users/region",
                                              query: [.init(name: "emailHash", value: Self.emailHash(email))]))
        decorate(&request)
        let (data, _) = try await transport.send(request)
        guard let region = try? JSONDecoder().decode(GlookoRegionResponse.self, from: data),
              let apiBase = region.urls?.apiBase, !apiBase.isEmpty else { return }
        locked { baseString = apiBase }
    }

    public func ensureSession() async throws {
        if locked({ cookie != nil && !twoFactorPending }) { return }
        guard credentials != nil else { throw GlookoAPIError.noToken }
        try await sharedSignIn(replacing: nil)
        if awaitingTwoFactor { throw GlookoAPIError.twoFactorRequired }
    }

    /// One sign-in at a time, shared by every caller; at most one per `reauthInterval`.
    private func sharedSignIn(replacing stale: String?) async throws {
        guard let credentials else { throw GlookoAPIError.authenticationRequired }
        let task: Task<Void, Error>? = try locked {
            if let signInTask { return signInTask }
            if let cookie, cookie != stale, !twoFactorPending { return nil }
            if let lastSignIn, now().timeIntervalSince(lastSignIn) < Self.reauthInterval {
                throw GlookoAPIError.authenticationRequired
            }
            lastSignIn = now()
            let task = Task { [self] in
                defer { locked { signInTask = nil } }
                if region == .auto { try? await resolveRegion(email: credentials.email) }
                try await signIn(email: credentials.email, password: credentials.password)
            }
            signInTask = task
            return task
        }
        try await task?.value
    }

    public func signIn(email: String, password: String) async throws {
        var failure = GlookoAPIError.signIn(status: 0, body: nil)
        for version in [GlookoSignInRequest.Version.v3, .v2] {
            var request = URLRequest(url: try url(path: version == .v3 ? "/api/v3/users/sign_in" : "/api/v2/users/sign_in"))
            request.httpMethod = "POST"
            locked { cookie = nil }
            decorate(&request)
            request.httpBody = try JSONEncoder().encode(GlookoSignInRequest(email: email, password: password, version: version))
            let (data, http) = try await transport.send(request)
            if Self.rejectedStatuses.contains(http.statusCode) {
                throw GlookoAPIError.signIn(status: http.statusCode, body: data)
            }
            let isHTML = http.value(forHTTPHeaderField: "Content-Type")?.contains("text/html") == true
            if (200...299).contains(http.statusCode), !isHTML, let session = Self.sessionCookie(http) {
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let twoFactor = ["twoFaRequired", "two_fa_required", "twoFactorRequired"].contains { object?[$0] as? Bool == true }
                locked { cookie = session; pendingEmail = email; twoFactorPending = twoFactor }
                return
            }
            failure = GlookoAPIError.signIn(status: http.statusCode, body: data)
        }
        throw failure
    }

    public func validateTwoFactor(code: String) async throws {
        guard let email = locked({ pendingEmail }) else { throw GlookoAPIError.noToken }
        var request = URLRequest(url: try url(path: "/api/v3/users/two_fa_validate_otp"))
        request.httpMethod = "POST"
        decorate(&request)
        request.httpBody = try JSONEncoder().encode(GlookoTwoFactorValidation(otpAttempt: code, email: email))
        let (data, http) = try await transport.send(request)
        guard (200...299).contains(http.statusCode) else {
            throw GlookoAPIError.signIn(status: http.statusCode, body: data)
        }
        locked {
            if let session = Self.sessionCookie(http) { cookie = session }
            twoFactorPending = false
        }
    }

    public func resendTwoFactor() async throws {
        var request = URLRequest(url: try url(path: "/api/v3/users/resend_2fa_otp_patient"))
        request.httpMethod = "POST"
        decorate(&request)
        request.httpBody = Data("{}".utf8)
        _ = try await transport.send(request)
    }

    static func sessionCookie(_ http: HTTPURLResponse) -> String? {
        guard let header = http.value(forHTTPHeaderField: "Set-Cookie"),
              let part = header.split(separator: ";").first(where: { $0.contains("_logbook-web_session=") })
        else { return nil }
        let value = part.trimmingCharacters(in: .whitespaces)
        return value.hasSuffix("=") ? nil : value
    }

    private func send(_ build: () throws -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        let used = locked { cookie }
        let (data, http) = try await transport.send(try build())
        guard Self.expiredStatuses.contains(http.statusCode) else { return (data, http) }
        guard credentials != nil else { throw GlookoAPIError.authenticationRequired }
        locked { if cookie == used { cookie = nil } }
        try await sharedSignIn(replacing: used)
        if awaitingTwoFactor { throw GlookoAPIError.twoFactorRequired }
        let retried = try await transport.send(try build())
        guard !Self.expiredStatuses.contains(retried.1.statusCode) else { throw GlookoAPIError.authenticationRequired }
        return retried
    }

    public func put<Item: Encodable>(endpoint: String, jsonName: String, items: [Item]) async throws {
        guard !items.isEmpty else { return }
        let body = try JSONEncoder().encode(SSv2Body(jsonName: jsonName, items: items))
        let (data, http) = try await send {
            var request = URLRequest(url: try url(path: "/api/v2/\(endpoint)"))
            request.httpMethod = (jsonName == "syncEvents") ? "POST" : "PUT"
            decorate(&request)
            request.httpBody = body
            return request
        }
        guard (200...299).contains(http.statusCode) else {
            throw GlookoAPIError.upload(endpoint, status: http.statusCode, body: data)
        }
    }

    public func syncComplete() async throws {
        let (data, http) = try await send {
            var request = URLRequest(url: try url(path: "/api/v3/users/activities_and_event_data_sync/complete",
                                                  query: [.init(name: "syncTimestamp", value: Self.utc(now()))]))
            request.httpMethod = "POST"
            decorate(&request)
            return request
        }
        guard (200...299).contains(http.statusCode) else {
            throw GlookoAPIError.upload("sync complete", status: http.statusCode, body: data)
        }
    }

    public func uploadDeviceFile(_ bytes: Data, extractorName: String = "LibreviewCSV") async throws {
        let (data, http) = try await send {
            var request = URLRequest(url: try url(path: "/api/v3/device/file/upload",
                                                  query: [.init(name: "extractorName", value: extractorName)]))
            request.httpMethod = "POST"
            decorate(&request, contentType: "application/octet-stream")
            request.httpBody = bytes
            return request
        }
        guard (200...299).contains(http.statusCode) else {
            throw GlookoAPIError.upload("device/file/upload", status: http.statusCode, body: data)
        }
    }
}

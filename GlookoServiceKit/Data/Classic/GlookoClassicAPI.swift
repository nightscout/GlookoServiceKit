import Foundation
import CryptoKit

public final class GlookoClassicAPI {
    public static let globalBaseString = GlookoConstants.Classic.globalBase

    private var baseString: String
    private let region: GlookoClassicRegion
    private let deviceId: String
    private let transport: GlookoHTTPTransport
    private var cookie: String?
    private let credentials: (email: String, password: String)?

    public private(set) var awaitingTwoFactor = false
    private var pendingEmail: String?

    public init(region: GlookoClassicRegion = .eu,
                sessionCookie: String? = nil,
                credentials: (email: String, password: String)? = nil,
                deviceId: String = UUID().uuidString,
                transport: GlookoHTTPTransport = URLSessionTransport()) {
        self.region = region
        self.deviceId = deviceId
        self.cookie = sessionCookie
        self.credentials = credentials
        self.transport = transport
        self.baseString = GlookoConstants.Classic.patientApiBase(prefix: region.hostPrefix ?? "eu")
    }

    public var hasSession: Bool { (cookie != nil && !awaitingTwoFactor) || credentials != nil }
    public var sessionCookie: String? { awaitingTwoFactor ? nil : cookie }
    public func invalidate() { cookie = nil; awaitingTwoFactor = false; pendingEmail = nil }

    public static func emailHash(_ email: String) -> String {
        let digest = SHA256.hash(data: Data(email.lowercased().trimmingCharacters(in: .whitespaces).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func iso(_ date: Date) -> String { GlookoDate.iso(date, timeZone: .current) }

    private var deviceInfo: GlookoDeviceInformation { GlookoDeviceInformation(deviceId: deviceId) }

    private func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    private func url(base: String, path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: base) else { throw GlookoAPIError.encoding }
        components.path = path
        guard !query.isEmpty else {
            guard let made = components.url else { throw GlookoAPIError.encoding }
            return made
        }
        components.queryItems = query
        guard let made = components.url else { throw GlookoAPIError.encoding }
        return made
    }

    private func decorate(_ request: inout URLRequest, contentType: String = "application/json") {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-type")
        request.setValue(GlookoConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(jsonString(deviceInfo), forHTTPHeaderField: "DeviceInformation")
        request.setValue("en-US", forHTTPHeaderField: "GlookoOverrideLocale")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "x-timezone")
        guard let cookie else { return }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
    }

    public func resolveRegion(email: String) async throws {
        let made = try url(base: Self.globalBaseString, path: "/api/v2/users/region",
                           query: [.init(name: "emailHash", value: Self.emailHash(email))])
        var request = URLRequest(url: made)
        decorate(&request)
        let (data, _) = try await transport.send(request)
        guard let region = try? JSONDecoder().decode(GlookoRegionResponse.self, from: data),
              let apiBase = region.urls?.apiBase, !apiBase.isEmpty else { return }
        baseString = apiBase
    }

    public func ensureSession() async throws {
        if cookie != nil, !awaitingTwoFactor { return }
        guard let credentials else { throw GlookoAPIError.noToken }
        if region == .auto { try? await resolveRegion(email: credentials.email) }
        try await signIn(email: credentials.email, password: credentials.password)
        if awaitingTwoFactor { throw GlookoAPIError.twoFactorRequired }
    }

    public func signIn(email: String, password: String) async throws {
        let made = try url(base: baseString, path: "/api/v2/users/sign_in")
        var request = URLRequest(url: made)
        request.httpMethod = "POST"
        decorate(&request)
        request.httpBody = try JSONEncoder().encode(
            GlookoSignInRequest(email: email, password: password, device: deviceInfo))
        let (data, http) = try await transport.send(request)
        captureCookie(http)
        guard (200...299).contains(http.statusCode), cookie != nil else {
            throw GlookoAPIError.signIn(status: http.statusCode, body: data)
        }
        pendingEmail = email
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        awaitingTwoFactor = (object?["twoFaRequired"] as? Bool) == true
    }

    public func validateTwoFactor(code: String) async throws {
        guard let email = pendingEmail else { throw GlookoAPIError.noToken }
        let made = try url(base: baseString, path: "/api/v3/users/two_fa_validate_otp")
        var request = URLRequest(url: made)
        request.httpMethod = "POST"
        decorate(&request)
        request.httpBody = try JSONEncoder().encode(
            GlookoTwoFactorValidation(otpAttempt: code, email: email, deviceInformation: deviceInfo))
        let (data, http) = try await transport.send(request)
        captureCookie(http)
        guard (200...299).contains(http.statusCode) else {
            throw GlookoAPIError.signIn(status: http.statusCode, body: data)
        }
        awaitingTwoFactor = false
    }

    public func resendTwoFactor() async throws {
        let made = try url(base: baseString, path: "/api/v3/users/resend_2fa_otp_patient")
        var request = URLRequest(url: made)
        request.httpMethod = "POST"
        decorate(&request)
        request.httpBody = Data("{}".utf8)
        _ = try await transport.send(request)
    }

    private func captureCookie(_ http: HTTPURLResponse) {
        guard let header = http.value(forHTTPHeaderField: "Set-Cookie"),
              let part = header.split(separator: ";").first(where: { $0.contains("_logbook-web_session") })
        else { return }
        cookie = part.trimmingCharacters(in: .whitespaces)
    }

    private func send(_ build: () throws -> URLRequest, retry: Bool = true) async throws -> (Data, HTTPURLResponse) {
        let (data, http) = try await transport.send(try build())
        guard http.statusCode == 401 || http.statusCode == 421, retry, let credentials else {
            return (data, http)
        }
        invalidate()
        try await signIn(email: credentials.email, password: credentials.password)
        return try await send(build, retry: false)
    }

    public func put<Item: Encodable>(endpoint: String, jsonName: String, items: [Item]) async throws {
        guard !items.isEmpty else { return }
        let body = try JSONEncoder().encode(SSv2Body(jsonName: jsonName, items: items))
        let (data, http) = try await send {
            let made = try url(base: baseString, path: "/api/v2/\(endpoint)")
            var request = URLRequest(url: made)
            request.httpMethod = (jsonName == "syncEvents") ? "POST" : "PUT"
            decorate(&request)
            request.httpBody = body
            return request
        }
        guard (200...299).contains(http.statusCode) else {
            throw GlookoAPIError.server("\(endpoint) \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
    }

    public func uploadDeviceFile(_ bytes: Data, extractorName: String = "LibreviewCSV") async throws {
        let (data, http) = try await send {
            let made = try url(base: baseString, path: "/api/v3/device/file/upload",
                               query: [.init(name: "extractorName", value: extractorName)])
            var request = URLRequest(url: made)
            request.httpMethod = "POST"
            decorate(&request, contentType: "application/octet-stream")
            request.httpBody = bytes
            return request
        }
        guard (200...299).contains(http.statusCode) else {
            throw GlookoAPIError.server("device/file/upload \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
    }

    public func uploadToAnalyzer(_ ibf: Data, extractor: String) async throws {
        guard let cookie else { throw GlookoAPIError.noToken }
        guard let body = GlookoDeflate.zlib(ibf) else { throw GlookoAPIError.encoding }
        guard let made = URL(string: GlookoConstants.Classic.analyzerBase(from: baseString) + "/device/data") else {
            throw GlookoAPIError.encoding
        }
        var request = URLRequest(url: made)
        request.httpMethod = "POST"
        request.setValue(GlookoConstants.Classic.analyzerApiKey, forHTTPHeaderField: "X-Glooko-API-Key")
        request.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        request.setValue(GlookoConstants.Classic.analyzerSwid, forHTTPHeaderField: "X-Glooko-SW-ID")
        request.setValue("TRIO-\(deviceId.prefix(12))", forHTTPHeaderField: "X-Glooko-Terminal-Serial")
        request.setValue(extractor, forHTTPHeaderField: "X-Glooko-Extractor")
        request.setValue("nfc", forHTTPHeaderField: "X-Glooko-Extractor-Interface")
        request.setValue(baseString, forHTTPHeaderField: "X-Glooko-Base-Url")
        request.setValue(Self.iso(Date()), forHTTPHeaderField: "X-Glooko-Synctime")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Glooko-Event-ID")
        request.setValue("deflate", forHTTPHeaderField: "Content-Encoding")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(GlookoConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        let (data, http) = try await transport.send(request)
        guard (200...299).contains(http.statusCode) else {
            throw GlookoAPIError.server("device/data \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
    }

}

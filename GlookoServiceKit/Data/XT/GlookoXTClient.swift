import Foundation

public final class GlookoXTClient {
    public private(set) var token: String?

    private let transport: GlookoHTTPTransport
    private let identity: GlookoClientIdentity
    private var socket: GlookoSocketIO?

    public init(token: String? = nil, identity: GlookoClientIdentity = GlookoClientIdentity(),
                transport: GlookoHTTPTransport = URLSessionTransport()) {
        self.token = token
        self.identity = identity
        self.transport = transport
    }

    public func requestCode(email: String, password: String) async throws {
        _ = try await post("/api/users/patient-login/", body: ["email": email, "password": password])
    }

    @discardableResult
    public func authenticate(email: String, code: String) async throws -> String {
        let json = try await post("/api/users/code-auth", body: ["email": email, "code": code])
        guard let token = json["token"] as? String else { throw GlookoAPIError.noToken }
        self.token = token
        return token
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: GlookoConstants.XT.restBase.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("", forHTTPHeaderField: "x-ab-token")
        request.setValue(identity.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, http) = try await transport.send(request)
        guard (200 ... 299).contains(http.statusCode) else {
            throw GlookoAPIError.signIn(status: http.statusCode, body: data)
        }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }

    public var patientId: String? {
        guard let token, token.split(separator: ".").count >= 2 else { return nil }
        var b64 = String(token.split(separator: ".")[1])
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let payload = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let id = json["id"] else { return nil }
        return String(describing: id)
    }

    public func uploadIBF(_ ibf: Data, reference: Date = Date()) async throws {
        guard let token, let patientId else { throw GlookoAPIError.noToken }
        GlookoLog.upload.info("uploadIBF: \(ibf.count) bytes")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let start = formatter.string(from: reference.addingTimeInterval(-30 * 86400))
        let end = formatter.string(from: reference.addingTimeInterval(86400))

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: GlookoConstants.XT.restBase.appendingPathComponent("/api/upload/ibf"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(GlookoConstants.XT.apiVersion, forHTTPHeaderField: "version")
        request.setValue(identity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(boundary: boundary, ibf: ibf,
                                              fields: [("patient_id", patientId), ("startDate", start), ("endDate", end)])

        let (data, http) = try await transport.send(request)
        guard (200 ... 299).contains(http.statusCode) else {
            GlookoLog.upload.error("uploadIBF failed: \(http.statusCode)")
            // XT has no refresh: an expired or revoked token needs a new emailed code
            if http.statusCode == 401 || http.statusCode == 403 { throw GlookoAPIError.authenticationRequired }
            throw GlookoAPIError.upload("upload/ibf", status: http.statusCode, body: data)
        }
    }

    static func multipartBody(boundary: String, ibf: Data, fields: [(String, String)]) -> Data {
        var body = Data()
        let dash = "--\(boundary)\r\n"
        for (name, value) in fields {
            body.append(Data(dash.utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data(dash.utf8))
        body.append(Data("Content-Disposition: form-data; name=\"document\"; filename=\"trio.ibf\"\r\n".utf8))
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(ibf)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    public var isConnected: Bool { socket?.isOpen ?? false }

    public func connect() async throws {
        guard let token else { throw GlookoAPIError.noToken }
        let socket = GlookoSocketIO(baseURL: GlookoConstants.XT.socketBase, token: token)
        socket.onClose = { [weak self] in self?.socket = nil }
        self.socket = socket
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            socket.connect { c.resume(with: $0) }
        }
    }

    public func disconnect() {
        socket?.onClose = nil
        socket?.disconnect()
        socket = nil
    }

    @discardableResult
    public func addRecords(_ records: [GlookoRecord]) async throws -> [Int] {
        guard let socket, socket.isOpen else { throw GlookoAPIError.notConnected }
        let dicts = try Self.jsonDicts(records)
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<[Int], Error>) in
            let once = Once()
            socket.emit("ADD_MANY_RECORDS", ["records": dicts]) { ack in
                once.run {
                    let obj = Self.parseAck(ack)
                    if let err = obj["error"] as? String { c.resume(throwing: GlookoAPIError.server(GlookoRedact.text(err))); return }
                    let ids = (obj["collected_data"] as? [[String: Any]])?.compactMap { $0["id"] as? Int } ?? []
                    c.resume(returning: ids)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                once.run { c.resume(throwing: GlookoAPIError.notConnected) }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func run(_ block: () -> Void) {
            lock.lock(); let go = !done; done = true; lock.unlock()
            if go { block() }
        }
    }

    private static func jsonDicts(_ records: [GlookoRecord]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(records)
        return (try JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    private static func parseAck(_ ack: Any?) -> [String: Any] {
        if let s = ack as? String, let d = s.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return o }
        return (ack as? [String: Any]) ?? [:]
    }
}

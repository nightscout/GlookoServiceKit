import Foundation

public enum GlookoAPIError: LocalizedError, Equatable {
    case http(Int)
    case noToken
    case server(String)
    case notConnected
    case encoding
    case auth(String)
    case twoFactorRequired
    case authenticationRequired
    case upload(endpoint: String, status: Int, message: String?)

    public var errorDescription: String? {
        switch self {
        case let .http(code): return "HTTP \(code)"
        case .noToken: return LocalizedString("Missing authentication", comment: "Glooko no token")
        case let .server(message): return LocalizedString("Server error: \(message)", comment: "Glooko server error")
        case .notConnected: return LocalizedString("Not connected", comment: "Glooko not connected")
        case .encoding: return LocalizedString("Encoding failure", comment: "Glooko encoding error")
        case let .auth(message): return message
        case .twoFactorRequired: return LocalizedString("Enter the verification code sent to you.", comment: "Glooko 2FA")
        case .authenticationRequired:
            return LocalizedString("Glooko needs you to sign in again.", comment: "Glooko session expired")
        case let .upload(endpoint, status, message):
            let detail = message.map { ": \($0)" } ?? ""
            return LocalizedString("Upload to Glooko failed (\(endpoint), HTTP \(status))\(detail)", comment: "Glooko upload error")
        }
    }

    public static func signIn(status: Int, body: Data?) -> GlookoAPIError {
        .auth(GlookoSignInMessage.make(status: status, body: body))
    }

    static func upload(_ endpoint: String, status: Int, body: Data?) -> GlookoAPIError {
        let text = body.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = text.flatMap { $0.isEmpty ? nil : GlookoRedact.text(String($0.prefix(200))) }
        return .upload(endpoint: endpoint, status: status, message: message)
    }
}

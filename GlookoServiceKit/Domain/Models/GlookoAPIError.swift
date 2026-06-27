import Foundation

public enum GlookoAPIError: LocalizedError, Equatable {
    case http(Int)
    case noToken
    case server(String)
    case notConnected
    case encoding
    case auth(String)
    case twoFactorRequired

    public var errorDescription: String? {
        switch self {
        case let .http(code): return "HTTP \(code)"
        case .noToken: return LocalizedString("Missing authentication", comment: "Glooko no token")
        case let .server(message): return LocalizedString("Server error: \(message)", comment: "Glooko server error")
        case .notConnected: return LocalizedString("Not connected", comment: "Glooko not connected")
        case .encoding: return LocalizedString("Encoding failure", comment: "Glooko encoding error")
        case let .auth(message): return message
        case .twoFactorRequired: return LocalizedString("Enter the verification code sent to you.", comment: "Glooko 2FA")
        }
    }

    public static func signIn(status: Int, body: Data?) -> GlookoAPIError {
        .auth(GlookoSignInMessage.make(status: status, body: body))
    }
}

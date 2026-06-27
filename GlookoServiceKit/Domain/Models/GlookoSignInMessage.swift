import Foundation

enum GlookoSignInMessage {

    static func make(status: Int, body: Data?) -> String {
        switch serverMessage(from: body) {
        case "CANNOT_UPDATE_USER", "WRONG_CODE", "INVALID_CODE":
            return LocalizedString("Invalid or expired code. Please request a new one.", comment: "Glooko bad OTP")
        case "WRONG_INPUT", "INVALID_CREDENTIALS", "Invalid email or password":
            return LocalizedString("Sign-in failed: check your email and password.", comment: "Glooko bad credentials")
        default:
            break
        }
        switch status {
        case 401, 403:
            return LocalizedString("Sign-in failed: check your email and password.", comment: "Glooko 401/403")
        case 400, 422:
            return LocalizedString("Sign-in failed: this account or input wasn’t accepted by Glooko.", comment: "Glooko 400/422")
        case 500 ... 599:
            return LocalizedString("Glooko had a server error during sign-in. Please try again later.", comment: "Glooko 5xx")
        default:
            let raw = serverMessage(from: body)
            return raw.map { LocalizedString("Sign-in failed: \($0)", comment: "Glooko generic") }
                ?? LocalizedString("Sign-in failed (HTTP \(status)).", comment: "Glooko generic http")
        }
    }

    static func serverMessage(from body: Data?) -> String? {
        guard let body, !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        if let error = object["error"] as? String, !error.isEmpty { return error }
        if let message = object["message"] as? String, !message.isEmpty { return message }
        return nil
    }
}

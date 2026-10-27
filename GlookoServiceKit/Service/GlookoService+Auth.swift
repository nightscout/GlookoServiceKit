import Foundation

public extension GlookoService {

    func requestLoginCode(email: String, password: String) async throws {
        switch configuration.variant {
        case .xt:
            try await GlookoXTClient(identity: identity).requestCode(email: email, password: password)
        case .classic:
            throw GlookoAPIError.server("Classic Glooko not yet supported")
        }
    }

    func authenticate(email: String, code: String) async throws {
        switch configuration.variant {
        case .xt:
            let jwt = try await GlookoXTClient(identity: identity).authenticate(email: email, code: code)
            configuration.email = email
            token = jwt
            reload()
            await recordSuccess()
        case .classic:
            throw GlookoAPIError.server("Classic uses email + password — call connectClassic(email:password:)")
        }
    }

    func connectClassic(email: String, password: String) async throws {
        let api = GlookoClassicAPI(region: configuration.classicRegion,
                                   credentials: (email: email, password: password),
                                   identity: identity)
        do {
            try await api.ensureSession()
        } catch GlookoAPIError.twoFactorRequired {
            pendingClassicAPI = api
            pendingClassicCredentials = (email, password)
            throw GlookoAPIError.twoFactorRequired
        }
        finalizeClassic(api: api, email: email, password: password)
    }

    func verifyClassicTwoFactor(code: String) async throws {
        guard let api = pendingClassicAPI, let creds = pendingClassicCredentials else {
            throw GlookoAPIError.noToken
        }
        try await api.validateTwoFactor(code: code)
        finalizeClassic(api: api, email: creds.email, password: creds.password)
        pendingClassicAPI = nil
        pendingClassicCredentials = nil
    }

    func resendClassicTwoFactor() async throws {
        try await pendingClassicAPI?.resendTwoFactor()
    }

    private func finalizeClassic(api: GlookoClassicAPI, email: String, password: String) {
        configuration.email = email
        credentials.classicPassword = password
        token = api.sessionCookie
        Task { @MainActor in recordSuccess() }
        reload()
    }

    func signOut() {
        Task { @MainActor in retractAlerts() }
        credentials.clear()
        configuration.email = nil
        stateDelegate?.pluginWantsDeletion(self)
    }

    var isAuthenticated: Bool {
        switch configuration.variant {
        case .xt:
            return token != nil
        case .classic:
            return configuration.email != nil && credentials.classicPassword != nil
        }
    }
}

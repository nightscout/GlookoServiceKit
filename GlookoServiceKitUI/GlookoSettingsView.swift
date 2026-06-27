import SwiftUI
import GlookoServiceKit

struct GlookoSettingsView: View {
    @ObservedObject var service: GlookoService
    let onCreated: () -> Void
    let dismiss: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var classicNeedsCode = false
    @State private var busy = false
    @State private var errorText: String?

    private var isClassic: Bool { service.configuration.variant == .classic }

    var body: some View {
        NavigationView {
            Form {
                if !service.isAuthenticated { platformSection }
                if service.isAuthenticated { statusSection } else { signInSection }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle(LocalizedString("Glooko", comment: "Glooko settings title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedString("Done", comment: "Done button")) { service.completeUpdate(); dismiss() }
                }
            }
        }
    }

    private var platformSection: some View {
        Section(LocalizedString("Platform", comment: "Glooko platform section")) {
            Picker(LocalizedString("Variant", comment: "Glooko variant picker"), selection: $service.configuration.variant) {
                ForEach(GlookoVariant.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
            }
            if isClassic {
                Picker(LocalizedString("Region", comment: "Glooko region picker"), selection: $service.configuration.classicRegion) {
                    ForEach(GlookoClassicRegion.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
        }
    }

    private var statusSection: some View {
        Section(LocalizedString("Account", comment: "Glooko account section")) {
            row(LocalizedString("Status", comment: "Status label"), LocalizedString("Connected", comment: "Connected status"))
            if let email = service.configuration.email { row(LocalizedString("Email", comment: "Email label"), email) }
            row(LocalizedString("Platform", comment: "Platform label"), service.configuration.variant.localizedTitle)
            if isClassic { row(LocalizedString("Region", comment: "Region label"), service.configuration.classicRegion.displayName) }
            row(LocalizedString("Last upload", comment: "Last upload label"), Self.format(service.stats.lastUploadDate))
            row(LocalizedString("Glucose sent", comment: "Glucose sent label"), "\(service.stats.glucose)")
            row(LocalizedString("Doses sent", comment: "Doses sent label"), "\(service.stats.doses)")
            row(LocalizedString("Carbs sent", comment: "Carbs sent label"), "\(service.stats.carbs)")
            row(LocalizedString("Pump events sent", comment: "Pump events sent label"), "\(service.stats.pumpEvents)")
            if let lastError = service.lastError {
                row(LocalizedString("Last error", comment: "Last error label"), lastError, valueColor: .red)
            }
            Button(LocalizedString("Sign out", comment: "Sign out button"), role: .destructive) { service.signOut(); dismiss() }
        }
    }

    @ViewBuilder private var signInSection: some View {
        Section(LocalizedString("Sign in", comment: "Sign in section")) {
            if classicNeedsCode {
                codeEntry(LocalizedString("Verification code", comment: "2FA code field"),
                          action: { await connect { try await service.verifyClassicTwoFactor(code: code) } },
                          resend: { try? await service.resendClassicTwoFactor() })
            } else if isClassic {
                credentialFields
                button(LocalizedString("Connect", comment: "Connect button"),
                       enabled: !email.isEmpty && !password.isEmpty) {
                    await connect { try await service.connectClassic(email: email, password: password) }
                }
            } else if codeSent {
                codeEntry(LocalizedString("Email code", comment: "Email code field"),
                          action: { await connect { try await service.authenticate(email: email, code: code) } })
            } else {
                credentialFields
                button(LocalizedString("Send code", comment: "Send code button"),
                       enabled: !email.isEmpty && !password.isEmpty) {
                    await run { try await service.requestLoginCode(email: email, password: password); codeSent = true }
                }
            }
        }
    }

    private var credentialFields: some View {
        Group {
            TextField(LocalizedString("Email", comment: "Email field"), text: $email)
                .textContentType(.username).keyboardType(.emailAddress).autocapitalization(.none)
            SecureField(LocalizedString("Password", comment: "Password field"), text: $password)
        }
    }

    @ViewBuilder private func codeEntry(_ placeholder: String,
                                        action: @escaping () async -> Void,
                                        resend: (() async -> Void)? = nil) -> some View {
        TextField(placeholder, text: $code).keyboardType(.numberPad)
        button(LocalizedString("Verify & connect", comment: "Verify button"), enabled: !code.isEmpty) { await action() }
        if let resend {
            button(LocalizedString("Resend code", comment: "Resend code button"), enabled: true) { await resend() }
        }
    }

    private func button(_ title: String, enabled: Bool, action: @escaping () async -> Void) -> some View {
        Button(title) { Task { await action() } }.disabled(busy || !enabled)
    }

    private func row(_ label: String, _ value: String, valueColor: Color = .secondary) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(valueColor) }
    }

    private static func format(_ date: Date?) -> String {
        guard let date else { return LocalizedString("Never", comment: "Never uploaded") }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @MainActor private func run(_ work: @escaping () async throws -> Void) async {
        busy = true; errorText = nil
        do { try await work() }
        catch GlookoAPIError.twoFactorRequired { classicNeedsCode = true }
        catch { errorText = error.localizedDescription }
        busy = false
    }

    @MainActor private func connect(_ work: @escaping () async throws -> Void) async {
        await run {
            try await work()
            service.completeOnboard()
            onCreated()
        }
    }
}

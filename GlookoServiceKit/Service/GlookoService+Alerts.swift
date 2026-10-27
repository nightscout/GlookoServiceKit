import Foundation
import LoopKit

extension GlookoAPIError {
    var needsSignIn: Bool {
        switch self {
        case .authenticationRequired, .noToken, .twoFactorRequired: return true
        case let .upload(_, status, _): return status == 401 || status == 403
        default: return false
        }
    }
}

extension GlookoService {

    public enum AlertKind: String, CaseIterable {
        case authenticationNeeded = "authentication-needed"
        case uploadsStalled = "uploads-stalled"
    }

    public static let stalledAlertDelay: TimeInterval = 60 * 60

    func alertIdentifier(_ kind: AlertKind) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: pluginIdentifier, alertIdentifier: kind.rawValue)
    }

    static func content(_ kind: AlertKind) -> Alert.Content {
        let ok = LocalizedString("OK", comment: "Alert acknowledgment OK button")
        switch kind {
        case .authenticationNeeded:
            return Alert.Content(
                title: LocalizedString("Glooko sign-in needed", comment: "Title of the alert when Glooko needs a new sign-in"),
                body: LocalizedString("Your data is not being sent to Glooko. Open the Glooko service settings and sign in again.",
                                      comment: "Body of the alert when Glooko needs a new sign-in"),
                acknowledgeActionButtonLabel: ok)
        case .uploadsStalled:
            return Alert.Content(
                title: LocalizedString("Glooko uploads not working", comment: "Title of the alert when Glooko uploads keep failing"),
                body: LocalizedString("Nothing has reached Glooko for over an hour. Check your internet connection and the Glooko service settings.",
                                      comment: "Body of the alert when Glooko uploads keep failing"),
                acknowledgeActionButtonLabel: ok)
        }
    }

    /// Kinds to raise after a failed upload at `now`. Stalled counts from the last success, or the first failure.
    static func alertsToIssue(for error: Error, stats: UploadStats, now: Date) -> [AlertKind] {
        var kinds: [AlertKind] = []
        if (error as? GlookoAPIError)?.needsSignIn == true { kinds.append(.authenticationNeeded) }
        if let since = stats.lastUploadDate ?? stats.failingSince, now.timeIntervalSince(since) >= stalledAlertDelay {
            kinds.append(.uploadsStalled)
        }
        return kinds
    }

    @MainActor func recordFailure(_ error: Error, now: Date = Date()) {
        if stats.failingSince == nil { stats.failingSince = now }
        for kind in Self.alertsToIssue(for: error, stats: stats, now: now) where !activeAlerts.contains(kind) {
            activeAlerts.insert(kind)
            let content = Self.content(kind)
            serviceDelegate?.issueAlert(Alert(identifier: alertIdentifier(kind), foregroundContent: content,
                                              backgroundContent: content, trigger: .immediate, interruptionLevel: .active))
        }
        persist()
    }

    @MainActor func recordSuccess() {
        stats.failingSince = nil
        retractAlerts()
    }

    @MainActor func retractAlerts() {
        for kind in activeAlerts {
            serviceDelegate?.retractAlert(identifier: alertIdentifier(kind))
        }
        activeAlerts.removeAll()
    }

    var activeAlerts: Set<AlertKind> {
        get { Set((stats.activeAlerts ?? []).compactMap(AlertKind.init(rawValue:))) }
        set { stats.activeAlerts = newValue.map(\.rawValue).sorted() }
    }
}

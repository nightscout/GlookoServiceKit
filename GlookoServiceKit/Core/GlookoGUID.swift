import Foundation
import CryptoKit

enum GlookoGUID {

    /// Name-based UUID (v5 layout over SHA-256), so a resend upserts the same Glooko record.
    static func make(_ seed: String) -> String {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return uuid.uuidString.lowercased()
    }

    static func bolus(_ syncIdentifier: String) -> String { make("trio-insulin-bolus|\(syncIdentifier)") }
    static func basalHour(_ hourStart: Date) -> String { make("trio-insulin-basal|\(Int(hourStart.timeIntervalSince1970))") }
    static func food(_ syncIdentifier: String) -> String { make("trio-carb-food|\(syncIdentifier)") }
    static func reading(_ syncIdentifier: String) -> String { make("trio-reading|\(syncIdentifier)") }
}

enum GlookoRedact {

    private static let patterns: [(NSRegularExpression, String)] = [
        (#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "<email>"),
        (#"_logbook-web_session=[^;\s"]+"#, "_logbook-web_session=<redacted>"),
        (#"[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, "<token>"),
        (#"(?i)(token|password|code)(["']?\s*[:=]\s*["']?)[^"'&,\s}]+"#, "$1$2<redacted>"),
    ].map { (try! NSRegularExpression(pattern: $0.0, options: .caseInsensitive), $0.1) }

    static func text(_ input: String) -> String {
        patterns.reduce(input) { text, rule in
            rule.0.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: rule.1)
        }
    }
}

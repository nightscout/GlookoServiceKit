import Foundation

enum GlookoDate {
    static func iso(_ date: Date, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

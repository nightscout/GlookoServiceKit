import Foundation
import LoopKit

/// Delivered basal per UTC clock hour, built from a contiguous timeline of basal, temp basal and suspend segments.
public enum GlookoHourlyBasal {

    public struct Hour: Equatable {
        public let start: Date
        public let units: Double
    }

    /// Delay after an hour ends before it is reported, so late pump history can still land in it.
    public static let settleInterval: TimeInterval = 15 * 60

    /// Only hours fully covered by the timeline and settled by `now`; overlapping segments are clipped to the earlier one.
    public static func hours(from timeline: [DoseEntry], now: Date) -> [Hour] {
        var spans: [(start: Date, end: Date, rate: Double)] = []
        for dose in timeline.sorted(by: { $0.startDate < $1.startDate }) {
            guard [.basal, .tempBasal, .suspend].contains(dose.type) else { continue }
            let start = max(dose.startDate, spans.last?.end ?? .distantPast)
            guard dose.endDate > start else { continue }
            spans.append((start, dose.endDate, dose.type == .suspend ? 0 : max(0, dose.unitsPerHour)))
        }
        guard let first = spans.first else { return [] }

        var hours: [Hour] = []
        var hourStart = Date(timeIntervalSince1970: (first.start.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        while hourStart.addingTimeInterval(3600 + settleInterval) <= now {
            let hourEnd = hourStart.addingTimeInterval(3600)
            var covered: TimeInterval = 0
            var units = 0.0
            for span in spans where span.end > hourStart && span.start < hourEnd {
                let overlap = min(span.end, hourEnd).timeIntervalSince(max(span.start, hourStart))
                covered += overlap
                units += span.rate * overlap / 3600
            }
            if covered >= 3600 - 0.5 {
                hours.append(Hour(start: hourStart, units: (units * 1000).rounded() / 1000))
            }
            hourStart = hourEnd
        }
        return hours
    }
}

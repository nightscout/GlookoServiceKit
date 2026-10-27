import XCTest
import LoopKit
@testable import GlookoServiceKit

final class GlookoHourlyBasalTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3600) }

    private func segment(_ type: DoseType, _ from: Double, _ to: Double, _ rate: Double) -> DoseEntry {
        DoseEntry(type: type, startDate: at(from), endDate: at(to), value: rate, unit: .unitsPerHour)
    }

    func testBaseIsHourAligned() {
        XCTAssertEqual(base.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600), 0)
    }

    func testScheduledBasalTotalsPerHour() {
        let hours = GlookoHourlyBasal.hours(from: [segment(.basal, 0, 3, 0.8)], now: at(4))
        XCTAssertEqual(hours.map(\.start), [at(0), at(1), at(2)])
        XCTAssertEqual(hours.map(\.units), [0.8, 0.8, 0.8])
    }

    func testTempBasalSpanningHoursSplitsByOverlap() {
        let timeline = [segment(.basal, 0, 0.5, 1.0), segment(.tempBasal, 0.5, 1.5, 2.0), segment(.basal, 1.5, 2, 1.0)]
        let hours = GlookoHourlyBasal.hours(from: timeline, now: at(3))
        XCTAssertEqual(hours.map(\.units), [1.5, 1.5])
    }

    func testSuspendDeliversNothing() {
        let timeline = [segment(.basal, 0, 0.25, 1.0), segment(.suspend, 0.25, 0.75, 0), segment(.basal, 0.75, 1, 1.0)]
        XCTAssertEqual(GlookoHourlyBasal.hours(from: timeline, now: at(2)).map(\.units), [0.5])
    }

    func testPartiallyCoveredHoursAreSkipped() {
        let hours = GlookoHourlyBasal.hours(from: [segment(.basal, 0.5, 2.5, 1.0)], now: at(4))
        XCTAssertEqual(hours.map(\.start), [at(1)])
    }

    func testGapInTimelineSkipsHour() {
        let timeline = [segment(.basal, 0, 1, 1.0), segment(.basal, 1.1, 3, 1.0)]
        XCTAssertEqual(GlookoHourlyBasal.hours(from: timeline, now: at(4)).map(\.start), [at(0), at(2)])
    }

    func testHourWaitsForSettleInterval() {
        let timeline = [segment(.basal, 0, 5, 1.0)]
        XCTAssertEqual(GlookoHourlyBasal.hours(from: timeline, now: at(1) + 14 * 60).count, 0)
        XCTAssertEqual(GlookoHourlyBasal.hours(from: timeline, now: at(1) + 15 * 60).count, 1)
    }

    func testOverlappingSegmentsAreNotDoubleCounted() {
        let timeline = [segment(.basal, 0, 1, 1.0), segment(.tempBasal, 0.5, 1, 3.0)]
        XCTAssertEqual(GlookoHourlyBasal.hours(from: timeline, now: at(2)).map(\.units), [1.0])
    }

    func testRoundsToThousandths() {
        XCTAssertEqual(GlookoHourlyBasal.hours(from: [segment(.basal, 0, 1, 0.12345)], now: at(2)).map(\.units), [0.123])
    }

    func testBolusesAndEmptyTimelineIgnored() {
        XCTAssertTrue(GlookoHourlyBasal.hours(from: [], now: at(5)).isEmpty)
        let bolus = DoseEntry(type: .bolus, startDate: at(0), endDate: at(0), value: 3, unit: .units)
        XCTAssertTrue(GlookoHourlyBasal.hours(from: [bolus], now: at(5)).isEmpty)
    }

    func testHoursAreUTCAlignedRegardlessOfTimeZone() {
        let offset = base.addingTimeInterval(1800)
        let timeline = [DoseEntry(type: .basal, startDate: offset, endDate: offset.addingTimeInterval(3 * 3600),
                                  value: 1, unit: .unitsPerHour)]
        let hours = GlookoHourlyBasal.hours(from: timeline, now: at(5))
        XCTAssertTrue(hours.allSatisfy { $0.start.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600) == 0 })
        XCTAssertEqual(hours.map(\.start), [at(1), at(2)])
    }
}

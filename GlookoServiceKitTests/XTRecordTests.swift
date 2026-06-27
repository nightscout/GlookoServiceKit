import XCTest
import HealthKit
import LoopKit
@testable import GlookoServiceKit

final class XTRecordTests: XCTestCase {

    private let iuhr = HKUnit(from: "IU/hr")

    private func encodeJSON(_ record: GlookoRecord) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testCGMSetsGlycemiaAndLibreProduct() {
        let record = GlookoRecordBuilder.cgm(Date(), mgdl: 120, unit: .mgdl)
        XCTAssertEqual(record.glycemia, 120)
        XCTAssertEqual(record.product_glycemia_id, 85)
    }

    func testManualGlucoseHasNoProduct() {
        let record = GlookoRecordBuilder.manualGlucose(Date(), mgdl: 99, unit: .mgdl)
        XCTAssertEqual(record.glycemia, 99)
        XCTAssertNil(record.product_glycemia_id)
    }

    func testBolusVsCorrection() {
        XCTAssertEqual(GlookoRecordBuilder.bolus(Date(), units: 2.5).fast_insulin, 2.5)
        XCTAssertNil(GlookoRecordBuilder.bolus(Date(), units: 2.5).correction_insulin)
        let correction = GlookoRecordBuilder.bolus(Date(), units: 1.0, correction: true)
        XCTAssertEqual(correction.correction_insulin, 1.0)
        XCTAssertNil(correction.fast_insulin)
    }

    func testSMBHasNote() {
        let smb = GlookoRecordBuilder.smb(Date(), units: 0.3)
        XCTAssertEqual(smb.fast_insulin, 0.3)
        XCTAssertEqual(smb.note, "SMB")
    }

    func testSlowInsulin() {
        XCTAssertEqual(GlookoRecordBuilder.slowInsulin(Date(), units: 12).slow_insulin, 12)
    }

    func testScheduledBasalAbsolute() {
        let record = GlookoRecordBuilder.scheduledBasal(Date(), rateUPerHour: 0.85, durationMin: 30)
        XCTAssertEqual(record.basal_rate, 0.85)
        XCTAssertEqual(record.duration, 30)
        XCTAssertNil(record.rate_percentage)
        XCTAssertEqual(record.product_pump_id, 96)
    }

    func testLoopBasalPercentage() {
        let record = GlookoRecordBuilder.loopBasal(Date(), percent: 150, durationMin: 30)
        XCTAssertEqual(record.rate_percentage, 150)
        XCTAssertNil(record.basal_rate)
    }

    func testSuspendAndPrimeAndCarbs() {
        XCTAssertEqual(GlookoRecordBuilder.suspend(Date()).pump_stop, true)
        XCTAssertEqual(GlookoRecordBuilder.prime(Date()).is_prime, true)
        let carbs = GlookoRecordBuilder.carbs(Date(), grams: 42.6, mealTag: "breakfast")
        XCTAssertEqual(carbs.carbs, 43)
        XCTAssertEqual(carbs.meal_tag, "breakfast")
    }

    func testEncodingOmitsNilFields() throws {
        let json = try encodeJSON(GlookoRecordBuilder.manualGlucose(Date(timeIntervalSince1970: 0), mgdl: 100, unit: .mgdl))
        XCTAssertNotNil(json["recorded_at"])
        XCTAssertNotNil(json["glycemia"])
        XCTAssertNil(json["fast_insulin"])
        XCTAssertNil(json["product_glycemia_id"])
    }

    func testISOFormat() {
        XCTAssertEqual(GlookoRecord.iso(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00.000Z")
    }

    func testMapManualBolus() {
        let dose = DoseEntry(type: .bolus, startDate: Date(), endDate: Date(), value: 3, unit: .units)
        let record = GlookoXTBackend.map(dose)
        XCTAssertEqual(record?.fast_insulin, 3)
        XCTAssertNil(record?.note)
    }

    func testMapAutomaticBolusIsSMB() {
        let dose = DoseEntry(type: .bolus, startDate: Date(), endDate: Date(), value: 0.4, unit: .units, automatic: true)
        XCTAssertEqual(GlookoXTBackend.map(dose)?.note, "SMB")
    }

    func testMapTempBasalWithScheduleIsPercentage() {
        let now = Date()
        let dose = DoseEntry(type: .tempBasal, startDate: now, endDate: now.addingTimeInterval(1800),
                             value: 2.0, unit: .unitsPerHour,
                             scheduledBasalRate: HKQuantity(unit: iuhr, doubleValue: 1.0))
        let record = GlookoXTBackend.map(dose)
        XCTAssertEqual(record?.rate_percentage, 200)
        XCTAssertEqual(record?.product_pump_id, 96)
    }

    func testMapTempBasalWithoutScheduleIsAbsolute() {
        let now = Date()
        let dose = DoseEntry(type: .tempBasal, startDate: now, endDate: now.addingTimeInterval(1800),
                             value: 1.2, unit: .unitsPerHour)
        let record = GlookoXTBackend.map(dose)
        XCTAssertEqual(record?.basal_rate, 1.2)
        XCTAssertNil(record?.rate_percentage)
    }

    func testMapBasalAndSuspendAndResume() {
        let now = Date()
        XCTAssertEqual(GlookoXTBackend.map(DoseEntry(type: .basal, startDate: now, endDate: now.addingTimeInterval(3600), value: 0.7, unit: .unitsPerHour))?.basal_rate, 0.7)
        XCTAssertEqual(GlookoXTBackend.map(DoseEntry(type: .suspend, startDate: now, endDate: now, value: 0, unit: .units))?.pump_stop, true)
        XCTAssertNil(GlookoXTBackend.map(DoseEntry(type: .resume, startDate: now, endDate: now, value: 0, unit: .units)))
    }
}

import XCTest
import LoopKit
import HealthKit
@testable import GlookoServiceKit

final class GlookoIBFGeneratorTests: XCTestCase {

    private func records(_ data: Data) -> [[UInt8]] {
        let bytes = [UInt8](data)
        var out: [[UInt8]] = []
        var pos = 0
        while pos + 2 <= bytes.count {
            let size = Int(bytes[pos]) << 8 | Int(bytes[pos + 1])
            if size < 2 { break }
            let payload = Array(bytes[(pos + 2) ..< (pos + size)])
            let stored = Int(bytes[pos + size]) << 8 | Int(bytes[pos + size + 1])
            let calc = payload.reduce(0) { $0 + Int($1) } & 0xFFFF
            XCTAssertEqual(stored, calc, "checksum mismatch at \(pos)")
            out.append(payload)
            pos += size + 2
        }
        return out
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testHeaderBlockHas17RecordsWithValidChecksums() {
        let recs = records(GlookoIBFHeaders.block(historyFirstIndex: 100, historyLastIndex: 200, alarmFirstIndex: 50, alarmLastIndex: 60))
        XCTAssertEqual(recs.count, 17)
        XCTAssertEqual(recs[2].count, 23)
        XCTAssertEqual(recs[16].count, 483)
    }

    func testManufacturingIsSyntheticTrioSerial() {
        let recs = records(GlookoIBFHeaders.block(historyFirstIndex: 0, historyLastIndex: 1, alarmFirstIndex: 0, alarmLastIndex: 1))
        let serial = String(bytes: recs[2].prefix(while: { $0 != 0 }), encoding: .utf8)
        XCTAssertEqual(serial, "TRIO000-VPOD0001-T0000")  // 23-byte field keeps a trailing NUL
    }

    func testVersionsAre017() {
        let recs = records(GlookoIBFHeaders.block(historyFirstIndex: 0, historyLastIndex: 1, alarmFirstIndex: 0, alarmLastIndex: 1))
        let v = recs[0]
        XCTAssertEqual(Int(v[0]) << 8 | Int(v[1]), 0)
        XCTAssertEqual(Int(v[2]) << 8 | Int(v[3]), 1)
        XCTAssertEqual(Int(v[4]) << 8 | Int(v[5]), 7)
    }

    func testLogDescriptionsCountAndHistoryRanges() {
        let first: Int32 = 28000, last: Int32 = 28596
        let recs = records(GlookoIBFHeaders.block(historyFirstIndex: first, historyLastIndex: last, alarmFirstIndex: 0, alarmLastIndex: 1))
        let ld = recs[16]
        XCTAssertEqual(Int(ld[13]) << 8 | Int(ld[14]), 26)
        var o = 15
        var found76 = 0
        for _ in 0 ..< 26 {
            let recSize = Int(ld[o + 8]) << 8 | Int(ld[o + 9])
            if recSize == 76 {
                let f = Int32(bitPattern: UInt32(ld[o + 10]) << 24 | UInt32(ld[o + 11]) << 16 | UInt32(ld[o + 12]) << 8 | UInt32(ld[o + 13]))
                let l = Int32(bitPattern: UInt32(ld[o + 14]) << 24 | UInt32(ld[o + 15]) << 16 | UInt32(ld[o + 16]) << 8 | UInt32(ld[o + 17]))
                XCTAssertEqual(f, first)
                XCTAssertEqual(l, last)
                found76 += 1
            }
            o += 18
        }
        XCTAssertEqual(found76, 3)
    }

    func testEepromBgGoalOffsets() {
        let recs = records(GlookoIBFHeaders.block(historyFirstIndex: 0, historyLastIndex: 1, alarmFirstIndex: 0, alarmLastIndex: 1))
        let e = recs[4]
        XCTAssertEqual(e.count, 120)
        XCTAssertEqual(Int(e[83]) | Int(e[84]) << 8, 70)
        XCTAssertEqual(Int(e[85]) | Int(e[86]) << 8, 80)
        XCTAssertEqual(Int(e[87]) | Int(e[88]) << 8, 140)
        XCTAssertEqual(Int(e[89]), 8)
    }

    func testGeneratedBasalRecordEncodesRateAndType() {
        let entries = [GlookoIBFGenerator.Entry(date: date(2026, 6, 20, 8, 0),
                                                kind: .basal(unitsPerHour: 1.25, durationMin: 30))]
        let recs = records(GlookoIBFGenerator(timeZone: TimeZone(identifier: "UTC")!).generate(entries))
        XCTAssertEqual(recs.count, 17 + 1 + 1)
        let r = recs[17]
        XCTAssertEqual(r.count, 85)
        XCTAssertEqual(r[0], 0x03)
        let histType = Int32(bitPattern: UInt32(r[21]) | UInt32(r[22]) << 8 | UInt32(r[23]) << 16 | UInt32(r[24]) << 24)
        XCTAssertEqual(histType, 0x0008)
        let rate = UInt32(r[29]) | UInt32(r[30]) << 8 | UInt32(r[31]) << 16 | UInt32(r[32]) << 24
        XCTAssertEqual(rate, 125)
        XCTAssertEqual(r[9], 20)
        XCTAssertEqual(r[10], 6)
        XCTAssertEqual(Int(r[11]) | Int(r[12]) << 8, 2026)
        XCTAssertEqual(r[15], 8)
    }

    func testAlarmRecordHasFullPumpAlarmStructure() {
        let entries = [GlookoIBFGenerator.Entry(date: date(2026, 6, 20, 9, 0),
                                                kind: .alarm(code: GlookoIBFGenerator.occlusionAlarmCode))]
        let recs = records(GlookoIBFGenerator(timeZone: TimeZone(identifier: "UTC")!).generate(entries))
        let alarm = recs.first { $0[0] == 0x05 }!
        XCTAssertEqual(alarm.count, 50)
        XCTAssertEqual(Int(alarm[5]) << 8 | Int(alarm[6]), 41)
        XCTAssertEqual(alarm[29], 17)
        let lot = UInt32(alarm[33]) | UInt32(alarm[34]) << 8 | UInt32(alarm[35]) << 16 | UInt32(alarm[36]) << 24
        XCTAssertEqual(lot, 41158)
        let seq = UInt32(alarm[37]) | UInt32(alarm[38]) << 8 | UInt32(alarm[39]) << 16 | UInt32(alarm[40]) << 24
        XCTAssertEqual(seq, 330461)
        XCTAssertEqual([alarm[41], alarm[42], alarm[43]], [2, 6, 0])
        XCTAssertEqual([alarm[44], alarm[45], alarm[46]], [2, 6, 0])
    }

    func testActivateRecordHasDetail() {
        let entries = [GlookoIBFGenerator.Entry(date: date(2026, 6, 20, 9, 0), kind: .podChange)]
        let recs = records(GlookoIBFGenerator(timeZone: TimeZone(identifier: "UTC")!).generate(entries))
        let activate = recs.first {
            $0[0] == 0x03 && (Int32(bitPattern: UInt32($0[21]) | UInt32($0[22]) << 8 | UInt32($0[23]) << 16 | UInt32($0[24]) << 24)) == 0x8000
        }!
        XCTAssertEqual(activate.count, 85)
        XCTAssertEqual(Int(activate[29]) | Int(activate[30]) << 8, 41158 & 0xFFFF)
        XCTAssertEqual([activate[33], activate[34], activate[35]], [2, 6, 0])
        XCTAssertEqual([activate[36], activate[37], activate[38]], [2, 6, 0])
    }

    func testEntriesMappingFromDoseAndCarb() {
        let bolus = DoseEntry(type: .bolus, startDate: date(2026, 6, 20, 12, 0), endDate: date(2026, 6, 20, 12, 0),
                              value: 4.0, unit: .units)
        let carb = SyncCarbObject(absorptionTime: nil, createdByCurrentApp: true, foodType: nil, grams: 30,
                                  startDate: date(2026, 6, 20, 12, 0), uuid: nil, provenanceIdentifier: "Trio",
                                  syncIdentifier: nil, syncVersion: nil, userCreatedDate: nil, userUpdatedDate: nil,
                                  userDeletedDate: nil, operation: .create, addedDate: nil, supercededDate: nil)
        let entries = GlookoIBFGenerator.entries(basal: [], boluses: [bolus], carbs: [carb])
        XCTAssertEqual(entries.count, 2)
    }
}

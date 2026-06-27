import Foundation
import LoopKit
import HealthKit

public struct GlookoIBFGenerator {

    public enum Kind {
        case basal(unitsPerHour: Double, durationMin: Int)
        case bolus(units: Double, durationMin: Int)
        case carbs(grams: Double)
        case glucose(mgdl: Double)
        case podChange
        case suspend
        case resume
        case alarm(code: Int)
    }

    public struct Entry {
        public let date: Date
        public let kind: Kind
        public init(date: Date, kind: Kind) { self.date = date; self.kind = kind }
    }

    private static let logTypeHistory: UInt8 = 0x03
    private static let logTypeAlarm: UInt8 = 0x05
    private static let histBasal: Int32 = 0x0008
    private static let histBolus: Int32 = 0x0004
    private static let histCarb: Int32 = 0x1000
    private static let histGlucose: Int32 = 0x0800
    private static let histSuspend: Int32 = 0x0010
    private static let histResume: Int32 = 0x10000
    private static let histActivate: Int32 = 0x8000
    private static let histEnd: Int32 = 0x0000
    private static let historyPayloadSize = 85
    private static let alarmPayloadSize = 50
    private static let historyRecordSize: UInt16 = 76
    private static let alarmRecordSize: UInt16 = 41
    private static let historyBaseIndex: Int32 = 28596
    private static let alarmBaseIndex: Int32 = 9000

    private static let podLotNumber: UInt32 = 41158
    private static let podSeqNumber: UInt32 = 330461
    private static let processorVersion: (UInt8, UInt8, UInt8) = (2, 6, 0)
    private static let interlockVersion: (UInt8, UInt8, UInt8) = (2, 6, 0)

    public static let occlusionAlarmCode = 17
    public static let emptyReservoirAlarmCode = 14
    public static let lowReservoirAlarmCode = 23
    public static let podExpiredAlarmCode = 16
    public static let autoOffAlarmCode = 15

    private let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        calendar = c
    }

    public static func entries(basal: [DoseEntry], boluses: [DoseEntry], carbs: [SyncCarbObject],
                               manualGlucose: [Double] = [], glucoseDates: [Date] = []) -> [Entry] {
        var result: [Entry] = []
        for dose in basal {
            let durationMin = max(0, Int(dose.endDate.timeIntervalSince(dose.startDate) / 60))
            result.append(Entry(date: dose.startDate, kind: .basal(unitsPerHour: dose.unitsPerHour, durationMin: durationMin)))
        }
        for dose in boluses {
            let durationMin = max(0, Int(dose.endDate.timeIntervalSince(dose.startDate) / 60))
            result.append(Entry(date: dose.startDate, kind: .bolus(units: dose.deliveredUnits ?? dose.programmedUnits, durationMin: durationMin)))
        }
        for carb in carbs {
            result.append(Entry(date: carb.startDate, kind: .carbs(grams: carb.quantity.doubleValue(for: .gram()))))
        }
        for (value, date) in zip(manualGlucose, glucoseDates) {
            result.append(Entry(date: date, kind: .glucose(mgdl: value)))
        }
        return result
    }

    /// Generates an .ibf from a full window of entries. The server MERGES uploads and
    /// dedups by date, so re-sending the same window is safe. Indices are position-based
    /// (newest = highest, capped at the base) to keep date↔index correlation; a basal
    /// renders as a segment closed by the next basal, so callers must send the whole
    /// series (not single deltas) for basals to appear.
    public func generate(_ entries: [Entry]) -> Data {
        let sorted = entries.sorted { $0.date > $1.date }
        var historyRecords: [[UInt8]] = []
        var alarmRecords: [[UInt8]] = []
        var hIndex = Self.historyBaseIndex
        var aIndex = Self.alarmBaseIndex

        for (i, entry) in sorted.enumerated() {
            switch entry.kind {
            case .alarm:
                alarmRecords.append(alarmRecord(logIndex: aIndex, entry: entry, secs: UInt32(1000 + i)))
                aIndex -= 1
            default:
                historyRecords.append(historyRecord(logIndex: hIndex, entry: entry, secs: UInt32(1000 + i)))
                hIndex -= 1
            }
        }
        historyRecords.append(endRecord(logIndex: hIndex, date: sorted.last?.date ?? Date(), secs: 999))

        var data = Data()
        data.append(GlookoIBFHeaders.block(historyFirstIndex: hIndex, historyLastIndex: Self.historyBaseIndex,
                                           alarmFirstIndex: aIndex + 1, alarmLastIndex: Self.alarmBaseIndex))
        for r in historyRecords { data.append(frame(r)) }
        for r in alarmRecords { data.append(frame(r)) }
        return data
    }

    private func frame(_ payload: [UInt8]) -> Data {
        let size = payload.count + 2
        var out = Data()
        out.append(UInt8((size >> 8) & 0xFF)); out.append(UInt8(size & 0xFF))
        out.append(contentsOf: payload)
        let sum = payload.reduce(0) { $0 + Int($1) } & 0xFFFF
        out.append(UInt8((sum >> 8) & 0xFF)); out.append(UInt8(sum & 0xFF))
        return out
    }

    private func writeDate(_ p: inout [UInt8], _ off: Int, _ date: Date) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        p[off] = UInt8(c.day ?? 1); p[off + 1] = UInt8(c.month ?? 1)
        let year = UInt16(c.year ?? 2026)
        p[off + 2] = UInt8(year & 0xFF); p[off + 3] = UInt8((year >> 8) & 0xFF)
        p[off + 4] = UInt8(c.second ?? 0); p[off + 5] = UInt8(c.minute ?? 0); p[off + 6] = UInt8(c.hour ?? 0)
    }

    private func setLE32(_ p: inout [UInt8], _ off: Int, _ v: UInt32) {
        p[off] = UInt8(v & 0xFF); p[off + 1] = UInt8((v >> 8) & 0xFF)
        p[off + 2] = UInt8((v >> 16) & 0xFF); p[off + 3] = UInt8((v >> 24) & 0xFF)
    }
    private func setLE16(_ p: inout [UInt8], _ off: Int, _ v: UInt16) {
        p[off] = UInt8(v & 0xFF); p[off + 1] = UInt8((v >> 8) & 0xFF)
    }
    private func setBE32(_ p: inout [UInt8], _ off: Int, _ v: Int32) {
        let u = UInt32(bitPattern: v)
        p[off] = UInt8((u >> 24) & 0xFF); p[off + 1] = UInt8((u >> 16) & 0xFF)
        p[off + 2] = UInt8((u >> 8) & 0xFF); p[off + 3] = UInt8(u & 0xFF)
    }

    private func historyHeader(logIndex: Int32, histType: Int32, date: Date, secs: UInt32) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: Self.historyPayloadSize)
        p[0] = Self.logTypeHistory
        setBE32(&p, 1, logIndex)
        p[5] = UInt8((Int(Self.historyRecordSize) >> 8) & 0xFF); p[6] = UInt8(Int(Self.historyRecordSize) & 0xFF)
        writeDate(&p, 9, date)
        setLE32(&p, 17, secs)
        setLE32(&p, 21, UInt32(bitPattern: histType))
        return p
    }

    private func historyRecord(logIndex: Int32, entry: Entry, secs: UInt32) -> [UInt8] {
        switch entry.kind {
        case let .basal(rate, durationMin):
            var p = historyHeader(logIndex: logIndex, histType: Self.histBasal, date: entry.date, secs: secs)
            setLE32(&p, 29, UInt32(max(0, (rate * 100).rounded())))
            setLE16(&p, 33, UInt16(max(0, min(65535, durationMin))))
            return p
        case let .bolus(units, durationMin):
            var p = historyHeader(logIndex: logIndex, histType: Self.histBolus, date: entry.date, secs: secs)
            setLE32(&p, 29, UInt32(max(0, (units * 100).rounded())))
            if durationMin > 0 { setLE16(&p, 33, UInt16(min(65535, durationMin))) }
            return p
        case let .carbs(grams):
            var p = historyHeader(logIndex: logIndex, histType: Self.histCarb, date: entry.date, secs: secs)
            setLE16(&p, 29, UInt16(max(0, min(65535, grams.rounded()))))
            return p
        case let .glucose(mgdl):
            var p = historyHeader(logIndex: logIndex, histType: Self.histGlucose, date: entry.date, secs: secs)
            setLE16(&p, 33, UInt16(max(0, min(65535, mgdl.rounded()))))
            return p
        case .podChange:
            var p = historyHeader(logIndex: logIndex, histType: Self.histActivate, date: entry.date, secs: secs)
            setLE16(&p, 29, UInt16(Self.podLotNumber & 0xFFFF))
            setLE16(&p, 31, 0)
            p[33] = Self.processorVersion.0; p[34] = Self.processorVersion.1; p[35] = Self.processorVersion.2
            p[36] = Self.interlockVersion.0; p[37] = Self.interlockVersion.1; p[38] = Self.interlockVersion.2
            return p
        case .suspend:
            return historyHeader(logIndex: logIndex, histType: Self.histSuspend, date: entry.date, secs: secs)
        case .resume:
            return historyHeader(logIndex: logIndex, histType: Self.histResume, date: entry.date, secs: secs)
        case .alarm:
            return historyHeader(logIndex: logIndex, histType: Self.histEnd, date: entry.date, secs: secs)
        }
    }

    private func alarmRecord(logIndex: Int32, entry: Entry, secs: UInt32) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: Self.alarmPayloadSize)
        p[0] = Self.logTypeAlarm
        setBE32(&p, 1, logIndex)
        p[5] = UInt8((Int(Self.alarmRecordSize) >> 8) & 0xFF); p[6] = UInt8(Int(Self.alarmRecordSize) & 0xFF)
        writeDate(&p, 9, entry.date)
        setLE32(&p, 17, secs)
        writeDate(&p, 21, entry.date)
        if case let .alarm(code) = entry.kind { p[29] = UInt8(max(0, min(255, code))) }
        setLE32(&p, 33, Self.podLotNumber)
        setLE32(&p, 37, Self.podSeqNumber)
        p[41] = Self.processorVersion.0; p[42] = Self.processorVersion.1; p[43] = Self.processorVersion.2
        p[44] = Self.interlockVersion.0; p[45] = Self.interlockVersion.1; p[46] = Self.interlockVersion.2
        return p
    }

    private func endRecord(logIndex: Int32, date: Date, secs: UInt32) -> [UInt8] {
        historyHeader(logIndex: logIndex, histType: Self.histEnd, date: date, secs: secs)
    }
}

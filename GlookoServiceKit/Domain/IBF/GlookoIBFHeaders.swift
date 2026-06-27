import Foundation

enum GlookoIBFHeaders {

    static func block(historyFirstIndex: Int32, historyLastIndex: Int32,
                      alarmFirstIndex: Int32, alarmLastIndex: Int32) -> Data {
        var records: [[UInt8]] = []
        records.append(versions())
        records.append(pdmVersion())
        records.append(manufacturing())
        records.append(basalPrograms())
        records.append(eepromSettings())
        for idx in [15, 16, 17, 18, 19, 20, 21, 12, 11, 13, 14] as [UInt8] {
            records.append(profile(index: idx))
        }
        records.append(logDescriptions(historyFirst: historyFirstIndex, historyLast: historyLastIndex,
                                        alarmFirst: alarmFirstIndex, alarmLast: alarmLastIndex))

        var out = Data()
        for r in records { out.append(frame(r)) }
        return out
    }

    private static func frame(_ payload: [UInt8]) -> Data {
        let size = payload.count + 2
        var out = Data()
        out.append(UInt8((size >> 8) & 0xFF)); out.append(UInt8(size & 0xFF))
        out.append(contentsOf: payload)
        let sum = payload.reduce(0) { $0 + Int($1) } & 0xFFFF
        out.append(UInt8((sum >> 8) & 0xFF)); out.append(UInt8(sum & 0xFF))
        return out
    }

    private static func beShort(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

    private static func zstr(_ s: String, _ length: Int) -> [UInt8] {
        var bytes = Array(s.utf8.prefix(length - 1))
        while bytes.count < length { bytes.append(0) }
        return bytes
    }

    private static func putLE32(_ p: inout [UInt8], _ off: Int, _ v: UInt32) {
        p[off] = UInt8(v & 0xFF); p[off + 1] = UInt8((v >> 8) & 0xFF)
        p[off + 2] = UInt8((v >> 16) & 0xFF); p[off + 3] = UInt8((v >> 24) & 0xFF)
    }
    private static func putLE16(_ p: inout [UInt8], _ off: Int, _ v: UInt16) {
        p[off] = UInt8(v & 0xFF); p[off + 1] = UInt8((v >> 8) & 0xFF)
    }
    private static func putBE32(_ p: inout [UInt8], _ off: Int, _ v: Int32) {
        let u = UInt32(bitPattern: v)
        p[off] = UInt8((u >> 24) & 0xFF); p[off + 1] = UInt8((u >> 16) & 0xFF)
        p[off + 2] = UInt8((u >> 8) & 0xFF); p[off + 3] = UInt8(u & 0xFF)
    }

    private static func versions() -> [UInt8] {
        var p = beShort(0) + beShort(1) + beShort(7)
        p += beShort(0) + beShort(1) + beShort(7)
        p += zstr("Insulet", 8) + zstr("OmniPod", 8)
        return p
    }

    private static func pdmVersion() -> [UInt8] {
        beShort(2) + beShort(5) + beShort(0) + [UInt8](repeating: 0, count: 9)
    }

    private static func manufacturing() -> [UInt8] {
        zstr("TRIO000-VPOD0001-T00001", 23)
    }

    private static func basalPrograms() -> [UInt8] {
        var p = beShort(7) + beShort(3) + beShort(32)
        for i in 0 ..< 7 { p += beShort(i) + zstr("Program\(i)", 32) }
        return p
    }

    private static func eepromSettings() -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 120)
        putLE32(&p, 13, 5)
        putLE32(&p, 17, 1500)
        putLE32(&p, 21, 3000)
        putLE32(&p, 25, 1000)
        putLE32(&p, 53, 1)
        p[79] = 1
        p[81] = 0
        putLE16(&p, 83, 70)
        putLE16(&p, 85, 80)
        putLE16(&p, 87, 140)
        p[89] = 8
        return p
    }

    private static func profile(index: UInt8) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 205)
        p[0] = index
        for k in 0 ..< 48 { putLE32(&p, 13 + 4 * k, 20) }
        return p
    }

    private static func logDescriptions(historyFirst: Int32, historyLast: Int32,
                                        alarmFirst: Int32, alarmLast: Int32) -> [UInt8] {
        var p: [UInt8] = [2, 1, 1, 1, 1]
        p += [20, 6]
        p += beShort(2026)
        p += [0, 0, 12, 0]
        p += beShort(26)
        let recSizes = [16, 76, 76, 76, 41, 41, 16, 10, 20, 20, 8,
                        196, 196, 196, 196, 196, 196, 196, 196, 196, 196, 196,
                        20, 12, 18, 22]
        for (i, rs) in recSizes.enumerated() {
            p += beShort(i) + beShort(0) + beShort(2) + beShort(0) + beShort(rs)
            var entry = [UInt8](repeating: 0, count: 8)
            if rs == 76 { putBE32(&entry, 0, historyFirst); putBE32(&entry, 4, historyLast) }
            if rs == 41 { putBE32(&entry, 0, alarmFirst); putBE32(&entry, 4, alarmLast) }
            p += entry
        }
        return p
    }
}

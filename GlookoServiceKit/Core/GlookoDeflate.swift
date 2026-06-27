import Foundation
import Compression

enum GlookoDeflate {

    static func zlib(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let dstCap = data.count + (data.count / 100) + 128
        var dst = Data(count: dstCap)
        let n = dst.withUnsafeMutableBytes { d in
            data.withUnsafeBytes { s in
                compression_encode_buffer(d.bindMemory(to: UInt8.self).baseAddress!, dstCap,
                                          s.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        var out = Data([0x78, 0x9c])
        out.append(dst.prefix(n))
        var adler = adler32(data).bigEndian
        out.append(Data(bytes: &adler, count: 4))
        return out
    }

    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }
}

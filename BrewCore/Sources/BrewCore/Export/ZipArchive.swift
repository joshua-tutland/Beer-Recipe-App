import Foundation

/// A minimal ZIP writer (stored entries, no compression) — enough to build .docx files
/// without third-party dependencies.
public struct ZipArchive {
    private struct Entry {
        var name: Data
        var crc: UInt32
        var size: UInt32
        var offset: UInt32
    }

    private var body = Data()
    private var entries: [Entry] = []
    private let dosTime: UInt16
    private let dosDate: UInt16

    public init(date: Date = Date()) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, c.year ?? 1980)
        dosTime = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        dosDate = UInt16(((year - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
    }

    public mutating func addFile(path: String, contents: Data) {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(contents)
        let entry = Entry(name: name, crc: crc, size: UInt32(contents.count), offset: UInt32(body.count))

        body.appendLE(UInt32(0x04034b50))  // local file header signature
        body.appendLE(UInt16(20))           // version needed
        body.appendLE(UInt16(0x0800))       // flags: UTF-8 names
        body.appendLE(UInt16(0))            // method: stored
        body.appendLE(dosTime)
        body.appendLE(dosDate)
        body.appendLE(crc)
        body.appendLE(entry.size)           // compressed size
        body.appendLE(entry.size)           // uncompressed size
        body.appendLE(UInt16(name.count))
        body.appendLE(UInt16(0))            // extra length
        body.append(name)
        body.append(contents)

        entries.append(entry)
    }

    public mutating func addFile(path: String, text: String) {
        addFile(path: path, contents: Data(text.utf8))
    }

    public func data() -> Data {
        var out = body
        let directoryOffset = UInt32(out.count)
        for e in entries {
            out.appendLE(UInt32(0x02014b50))  // central directory signature
            out.appendLE(UInt16(20))           // version made by
            out.appendLE(UInt16(20))           // version needed
            out.appendLE(UInt16(0x0800))
            out.appendLE(UInt16(0))
            out.appendLE(dosTime)
            out.appendLE(dosDate)
            out.appendLE(e.crc)
            out.appendLE(e.size)
            out.appendLE(e.size)
            out.appendLE(UInt16(e.name.count))
            out.appendLE(UInt16(0))            // extra
            out.appendLE(UInt16(0))            // comment
            out.appendLE(UInt16(0))            // disk number
            out.appendLE(UInt16(0))            // internal attributes
            out.appendLE(UInt32(0))            // external attributes
            out.appendLE(e.offset)
            out.append(e.name)
        }
        let directorySize = UInt32(out.count) - directoryOffset
        out.appendLE(UInt32(0x06054b50))      // end of central directory
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt16(entries.count))
        out.appendLE(directorySize)
        out.appendLE(directoryOffset)
        out.appendLE(UInt16(0))
        return out
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }
}

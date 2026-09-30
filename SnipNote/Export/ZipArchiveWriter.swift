//
//  ZipArchiveWriter.swift
//  SnipNote
//
//  Minimal ZIP writer using the "stored" (no compression) method.
//  That is all a .docx needs and it avoids any third-party dependency.
//  Entries are limited to 4 GiB / 65535 files (no ZIP64), far above export needs.
//

import Foundation

struct ZipArchiveWriter {

    private struct Entry {
        let name: [UInt8]
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var body = Data()
    private var entries: [Entry] = []

    // Fixed timestamp (1980-01-01 00:00:00) keeps output deterministic.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = 0x0021

    mutating func addFile(name: String, data: Data) {
        let nameBytes = Array(name.utf8)
        let crc = Self.crc32(data)
        let offset = UInt32(body.count)

        body.appendUInt32(0x04034B50)          // local file header signature
        body.appendUInt16(20)                  // version needed to extract
        body.appendUInt16(0x0800)              // flags: bit 11 = UTF-8 file names
        body.appendUInt16(0)                   // method 0 = stored
        body.appendUInt16(Self.dosTime)
        body.appendUInt16(Self.dosDate)
        body.appendUInt32(crc)
        body.appendUInt32(UInt32(data.count))  // compressed size
        body.appendUInt32(UInt32(data.count))  // uncompressed size
        body.appendUInt16(UInt16(nameBytes.count))
        body.appendUInt16(0)                   // extra field length
        body.append(contentsOf: nameBytes)
        body.append(data)

        entries.append(Entry(name: nameBytes, crc: crc, size: UInt32(data.count), offset: offset))
    }

    mutating func addFile(name: String, string: String) {
        addFile(name: name, data: Data(string.utf8))
    }

    /// Finishes the archive and returns its bytes.
    func finalized() -> Data {
        var output = body
        let centralStart = UInt32(output.count)

        for entry in entries {
            output.appendUInt32(0x02014B50)    // central directory header signature
            output.appendUInt16(20)            // version made by
            output.appendUInt16(20)            // version needed
            output.appendUInt16(0x0800)
            output.appendUInt16(0)
            output.appendUInt16(Self.dosTime)
            output.appendUInt16(Self.dosDate)
            output.appendUInt32(entry.crc)
            output.appendUInt32(entry.size)
            output.appendUInt32(entry.size)
            output.appendUInt16(UInt16(entry.name.count))
            output.appendUInt16(0)             // extra length
            output.appendUInt16(0)             // comment length
            output.appendUInt16(0)             // disk number start
            output.appendUInt16(0)             // internal attributes
            output.appendUInt32(0)             // external attributes
            output.appendUInt32(entry.offset)
            output.append(contentsOf: entry.name)
        }

        let centralSize = UInt32(output.count) - centralStart

        output.appendUInt32(0x06054B50)        // end of central directory
        output.appendUInt16(0)                 // this disk
        output.appendUInt16(0)                 // disk with central directory
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(centralSize)
        output.appendUInt32(centralStart)
        output.appendUInt16(0)                 // comment length
        return output
    }

    // MARK: - CRC-32 (IEEE 802.3, reflected, poly 0xEDB88320)

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer {
                crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

//
//  Backup.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import Compression
import CoreFoundation
import Foundation

struct Backup: Codable, Hashable, Identifiable, Sendable {
    var id: Int { hashValue }

    var library: [BackupLibraryManga]?
    var history: [BackupHistory]?
    var manga: [BackupManga]?
    var chapters: [BackupChapter]?
    var trackItems: [BackupTrackItem]?
    var readingSessions: [BackupReadingSession]?
    var updates: [BackupUpdate]?
    var categories: [BackupCategory]?
    var sources: [BackupSource]?
    var sourceLists: [String]?
    var settings: [String: JsonAnyValue]?
    var date: Date
    var name: String?
    var automatic: Bool?
    var version: String?

    static func load(from url: URL) -> Backup? {
        guard let json = try? Data(contentsOf: url) else { return nil }

        if let backup = try? BackupArchiveCodec.decode(json) {
            return backup
        }

        if let backup = try? PropertyListDecoder().decode(Backup.self, from: json) {
            return backup
        } else {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try? decoder.decode(Backup.self, from: json)
        }
    }
}

enum BackupArchiveCodec {
    private static let magic = Data("AIB2".utf8)
    private static let headerSize = 17
    private static let maxUncompressedSize = 1_073_741_824

    struct Summary: Codable {
        let name: String?
        let date: Date
        let automatic: Bool
        let version: String?
        let counts: BackupInfo.Counts

        init(backup: Backup) {
            name = backup.name
            date = backup.date
            automatic = backup.automatic ?? false
            version = backup.version
            counts = BackupInfo.Counts(backup: backup)
        }
    }

    static func encode(_ backup: Backup) throws -> Data {
        let summaryEncoder = PropertyListEncoder()
        summaryEncoder.outputFormat = .binary
        let summary = try summaryEncoder.encode(Summary(backup: backup))

        var uncompressedSize = 0
        let compressed = try autoreleasepool { () throws -> Data in
            let object = try autoreleasepool { () throws -> Any in
                let plist = try PropertyListEncoder().encode(backup)
                return try PropertyListSerialization.propertyList(from: plist, options: [], format: nil)
            }
            let sink = try LZFSESink()
            try CompactCBOR.encode(object, into: sink)
            uncompressedSize = sink.inputCount
            // refuse here rather than writing an archive that decode would later reject
            guard uncompressedSize > 0, uncompressedSize <= maxUncompressedSize else {
                throw CodecError.payloadTooLarge
            }
            return try sink.finish()
        }

        var result = magic
        result.append(1) // envelope version
        result.appendInteger(UInt64(uncompressedSize))
        result.appendInteger(UInt32(summary.count))
        result.append(summary)
        result.append(compressed)
        return result
    }

    static func decode(_ data: Data) throws -> Backup {
        guard data.starts(with: magic), data.count >= headerSize else {
            throw CodecError.invalidHeader
        }
        guard data[data.startIndex + 4] == 1 else { throw CodecError.unsupportedVersion }
        let uncompressedSize = try data.integer(at: 5, as: UInt64.self)
        let summarySize = try data.integer(at: 13, as: UInt32.self)
        guard
            uncompressedSize > 0,
            uncompressedSize <= maxUncompressedSize,
            let payloadOffset = Int(exactly: summarySize).map({ headerSize + $0 }),
            payloadOffset <= data.count
        else {
            throw CodecError.invalidHeader
        }
        let payloadStart = data.startIndex + payloadOffset
        let plist = try autoreleasepool { () throws -> Data in
            let object = try autoreleasepool { () throws -> Any in
                let cbor = try decompress(data[payloadStart...], size: Int(uncompressedSize))
                return try CompactCBOR.decode(cbor)
            }
            return try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        }
        return try PropertyListDecoder().decode(Backup.self, from: plist)
    }

    static func summary(from data: Data) -> Summary? {
        guard
            data.starts(with: magic),
            data.count >= headerSize,
            data[data.startIndex + 4] == 1,
            let summarySize = try? data.integer(at: 13, as: UInt32.self),
            let end = Int(exactly: summarySize).map({ headerSize + $0 }),
            end <= data.count
        else {
            return nil
        }
        let start = data.startIndex
        return try? PropertyListDecoder().decode(Summary.self, from: data[(start + headerSize)..<(start + end)])
    }

    /// Decompresses the payload without trusting the declared size to allocate up front.
    private static func decompress(_ data: Data.SubSequence, size: Int) throws -> Data {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard
            compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZFSE)
                == COMPRESSION_STATUS_OK
        else {
            throw CodecError.decompressionFailed
        }
        defer { compression_stream_destroy(stream) }

        let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { scratch.deallocate() }

        var output = Data()
        output.reserveCapacity(min(size, chunkSize))
        try data.withUnsafeBytes { raw in
            stream.pointee.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(scratch)
            stream.pointee.src_size = raw.count
            var status = COMPRESSION_STATUS_OK
            repeat {
                stream.pointee.dst_ptr = scratch
                stream.pointee.dst_size = chunkSize
                status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status != COMPRESSION_STATUS_ERROR else { throw CodecError.decompressionFailed }
                let produced = chunkSize - stream.pointee.dst_size
                guard output.count + produced <= size else { throw CodecError.decompressionFailed }
                if produced > 0 {
                    output.append(scratch, count: produced)
                } else if status == COMPRESSION_STATUS_OK && stream.pointee.src_size == 0 {
                    // no progress left to make, but the stream never reported the end
                    throw CodecError.decompressionFailed
                }
            } while status == COMPRESSION_STATUS_OK
        }
        guard output.count == size else { throw CodecError.decompressionFailed }
        return output
    }

    /// The staging buffer size used when streaming a payload through LZFSE in either direction.
    fileprivate static let chunkSize = 1 << 16

    enum CodecError: Error {
        case invalidHeader
        case unsupportedVersion
        case compressionFailed
        case decompressionFailed
        case invalidCBOR
        case unsupportedValue
        case payloadTooLarge
    }
}

/// An append-only byte sink that compresses with LZFSE as it is written.
private final class LZFSESink {
    private let stream: UnsafeMutablePointer<compression_stream>
    private let scratch: UnsafeMutablePointer<UInt8>
    private let chunkSize = BackupArchiveCodec.chunkSize
    private var buffer = Data()
    private var output = Data()

    /// The number of uncompressed bytes written so far.
    private(set) var inputCount = 0

    init() throws {
        stream = .allocate(capacity: 1)
        guard
            compression_stream_init(stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_LZFSE)
                == COMPRESSION_STATUS_OK
        else {
            stream.deallocate()
            throw BackupArchiveCodec.CodecError.compressionFailed
        }
        scratch = .allocate(capacity: chunkSize)
        buffer.reserveCapacity(chunkSize)
    }

    deinit {
        compression_stream_destroy(stream)
        stream.deallocate()
        scratch.deallocate()
    }

    func append(_ byte: UInt8) throws {
        buffer.append(byte)
        inputCount += 1
        if buffer.count >= chunkSize { try drain() }
    }

    func append(_ data: Data) throws {
        buffer.append(data)
        inputCount += data.count
        if buffer.count >= chunkSize { try drain() }
    }

    func appendInteger<T: FixedWidthInteger>(_ value: T) throws {
        for shift in stride(from: (MemoryLayout<T>.size - 1) * 8, through: 0, by: -8) {
            try append(UInt8(truncatingIfNeeded: value >> T(shift)))
        }
    }

    /// Flushes the remaining bytes and returns the complete compressed payload.
    func finish() throws -> Data {
        try process(buffer, flags: Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
        buffer = Data()
        return output
    }

    private func drain() throws {
        try process(buffer, flags: 0)
        buffer.removeAll(keepingCapacity: true)
    }

    private func process(_ data: Data, flags: Int32) throws {
        try data.withUnsafeBytes { raw in
            stream.pointee.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(scratch)
            stream.pointee.src_size = raw.count
            var status = COMPRESSION_STATUS_OK
            repeat {
                stream.pointee.dst_ptr = scratch
                stream.pointee.dst_size = chunkSize
                status = compression_stream_process(stream, flags)
                guard status != COMPRESSION_STATUS_ERROR else {
                    throw BackupArchiveCodec.CodecError.compressionFailed
                }
                let produced = chunkSize - stream.pointee.dst_size
                if produced > 0 { output.append(scratch, count: produced) }
            } while status == COMPRESSION_STATUS_OK && (stream.pointee.src_size > 0 || flags != 0)
        }
    }
}

private enum CompactCBOR {
    private static let stringReferenceNamespaceTag: UInt64 = 256
    private static let stringReferenceTag: UInt64 = 25
    /// A Foundation date stored as its native reference-date double, avoiding a lossy epoch conversion.
    private static let foundationDateTag: UInt64 = 1001
    /// The deepest container nesting accepted in either direction.
    private static let maxDepth = 64

    static func encode(_ object: Any, into sink: LZFSESink) throws {
        // the deduplicating set is dropped before the reference map is built, so the string table
        // never exists in three copies at once
        var table: [String] = []
        try autoreleasepool {
            var strings = Set<String>()
            try collectStrings(in: object, into: &strings, depth: 0)
            table = strings.sorted()
        }
        var references = [String: Int](minimumCapacity: table.count)
        for (index, string) in table.enumerated() { references[string] = index }

        try appendHeader(major: 6, value: stringReferenceNamespaceTag, to: sink)
        try appendHeader(major: 4, value: 2, to: sink)
        try appendHeader(major: 4, value: UInt64(table.count), to: sink)
        for string in table {
            try appendString(string, to: sink)
        }
        try append(object, references: references, to: sink, depth: 0)
    }

    static func decode(_ data: Data) throws -> Any {
        var reader = Reader(data: data)
        guard try reader.readTag() == stringReferenceNamespaceTag else {
            throw BackupArchiveCodec.CodecError.invalidCBOR
        }
        guard try reader.readArrayCount() == 2 else {
            throw BackupArchiveCodec.CodecError.invalidCBOR
        }
        // every table entry costs at least one byte, so a count past the end of the input is a lie
        let stringCount = try reader.readArrayCount()
        guard stringCount <= reader.remaining else { throw BackupArchiveCodec.CodecError.invalidCBOR }
        var strings: [String] = []
        strings.reserveCapacity(stringCount)
        for _ in 0..<stringCount {
            strings.append(try reader.readString())
        }
        let object = try reader.readValue(strings: strings)
        guard reader.isAtEnd else { throw BackupArchiveCodec.CodecError.invalidCBOR }
        return object
    }

    private static func collectStrings(in value: Any, into strings: inout Set<String>, depth: Int) throws {
        guard depth <= maxDepth else { throw BackupArchiveCodec.CodecError.unsupportedValue }
        if let value = value as? String {
            strings.insert(value)
        } else if let value = value as? [Any] {
            for item in value { try collectStrings(in: item, into: &strings, depth: depth + 1) }
        } else if let value = value as? [String: Any] {
            for (key, item) in value {
                strings.insert(key)
                try collectStrings(in: item, into: &strings, depth: depth + 1)
            }
        }
    }

    private static func append(_ value: Any, references: [String: Int], to output: LZFSESink, depth: Int) throws {
        guard depth <= maxDepth else { throw BackupArchiveCodec.CodecError.unsupportedValue }
        if let value = value as? String, let reference = references[value] {
            try appendHeader(major: 6, value: stringReferenceTag, to: output)
            try appendHeader(major: 0, value: UInt64(reference), to: output)
        } else if let value = value as? Date {
            try appendHeader(major: 6, value: foundationDateTag, to: output)
            try appendDouble(value.timeIntervalSinceReferenceDate, to: output)
        } else if let value = value as? Data {
            try appendHeader(major: 2, value: UInt64(value.count), to: output)
            try output.append(value)
        } else if let value = value as? [Any] {
            try appendHeader(major: 4, value: UInt64(value.count), to: output)
            for item in value { try append(item, references: references, to: output, depth: depth + 1) }
        } else if let value = value as? [String: Any] {
            try appendHeader(major: 5, value: UInt64(value.count), to: output)
            for key in value.keys.sorted() {
                try append(key, references: references, to: output, depth: depth + 1)
                try append(value[key]!, references: references, to: output, depth: depth + 1)
            }
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                try output.append(number.boolValue ? 0xf5 : 0xf4)
            } else if CFNumberIsFloatType(number) {
                try appendDouble(number.doubleValue, to: output)
            } else if number.int64Value >= 0 {
                try appendHeader(major: 0, value: UInt64(number.int64Value), to: output)
            } else {
                try appendHeader(major: 1, value: UInt64(-1 - number.int64Value), to: output)
            }
        } else {
            throw BackupArchiveCodec.CodecError.unsupportedValue
        }
    }

    private static func appendString(_ value: String, to output: LZFSESink) throws {
        guard let data = value.data(using: .utf8) else { throw BackupArchiveCodec.CodecError.unsupportedValue }
        try appendHeader(major: 3, value: UInt64(data.count), to: output)
        try output.append(data)
    }

    private static func appendDouble(_ value: Double, to output: LZFSESink) throws {
        try output.append(0xfb)
        try output.appendInteger(value.bitPattern)
    }

    private static func appendHeader(major: UInt8, value: UInt64, to output: LZFSESink) throws {
        switch value {
            case 0..<24: try output.append(major << 5 | UInt8(value))
            case 24...UInt64(UInt8.max):
                try output.append(major << 5 | 24)
                try output.append(UInt8(value))
            case 256...UInt64(UInt16.max):
                try output.append(major << 5 | 25)
                try output.appendInteger(UInt16(value))
            case 65_536...UInt64(UInt32.max):
                try output.append(major << 5 | 26)
                try output.appendInteger(UInt32(value))
            default:
                try output.append(major << 5 | 27)
                try output.appendInteger(value)
        }
    }

    private struct Reader {
        let data: Data
        var offset: Int
        var isAtEnd: Bool { offset == data.endIndex }
        var remaining: Int { data.endIndex - offset }

        private var depth = 0

        init(data: Data) {
            self.data = data
            self.offset = data.startIndex
        }

        mutating func readTag() throws -> UInt64 {
            let (major, value) = try readHeader()
            guard major == 6 else { throw BackupArchiveCodec.CodecError.invalidCBOR }
            return value
        }

        mutating func readArrayCount() throws -> Int {
            let (major, value) = try readHeader()
            guard major == 4, let count = Int(exactly: value) else {
                throw BackupArchiveCodec.CodecError.invalidCBOR
            }
            return count
        }

        mutating func readString() throws -> String {
            let (major, value) = try readHeader()
            guard major == 3, let count = Int(exactly: value), count <= remaining else {
                throw BackupArchiveCodec.CodecError.invalidCBOR
            }
            defer { offset += count }
            guard let string = String(data: data[offset..<(offset + count)], encoding: .utf8) else {
                throw BackupArchiveCodec.CodecError.invalidCBOR
            }
            return string
        }

        mutating func readValue(strings: [String]) throws -> Any {
            guard depth < maxDepth else { throw BackupArchiveCodec.CodecError.invalidCBOR }
            depth += 1
            defer { depth -= 1 }

            let initial = try readByte()
            let major = initial >> 5
            let additional = initial & 0x1f
            if major == 6 {
                let tag = try readArgument(additional)
                if tag == stringReferenceTag {
                    let (referenceMajor, reference) = try readHeader()
                    guard referenceMajor == 0, reference < strings.count else {
                        throw BackupArchiveCodec.CodecError.invalidCBOR
                    }
                    return strings[Int(reference)]
                }
                if tag == foundationDateTag {
                    return Date(timeIntervalSinceReferenceDate: try readDouble())
                }
                throw BackupArchiveCodec.CodecError.invalidCBOR
            }
            let argument = try readArgument(additional)
            switch major {
                case 0: return NSNumber(value: argument)
                case 1:
                    guard argument <= UInt64(Int64.max) else { throw BackupArchiveCodec.CodecError.invalidCBOR }
                    return NSNumber(value: -1 - Int64(argument))
                case 2:
                    guard let count = Int(exactly: argument), count <= remaining else {
                        throw BackupArchiveCodec.CodecError.invalidCBOR
                    }
                    defer { offset += count }
                    return Data(data[offset..<(offset + count)])
                case 4:
                    // one byte per element is the floor, so a longer array cannot fit in what is left
                    guard let count = Int(exactly: argument), count <= remaining else {
                        throw BackupArchiveCodec.CodecError.invalidCBOR
                    }
                    return try (0..<count).map { _ in try readValue(strings: strings) }
                case 5:
                    // two bytes per entry is the floor, since a key and a value each cost at least one
                    guard let count = Int(exactly: argument), count <= remaining / 2 else {
                        throw BackupArchiveCodec.CodecError.invalidCBOR
                    }
                    var dictionary: [String: Any] = [:]
                    dictionary.reserveCapacity(count)
                    for _ in 0..<count {
                        guard let key = try readValue(strings: strings) as? String else {
                            throw BackupArchiveCodec.CodecError.invalidCBOR
                        }
                        dictionary[key] = try readValue(strings: strings)
                    }
                    return dictionary
                case 7:
                    switch additional {
                        case 20: return NSNumber(value: false)
                        case 21: return NSNumber(value: true)
                        case 27:
                            offset -= 8 // readArgument consumed the double bits
                            return NSNumber(value: try readDoublePayload())
                        default: throw BackupArchiveCodec.CodecError.invalidCBOR
                    }
                default: throw BackupArchiveCodec.CodecError.invalidCBOR
            }
        }

        private mutating func readDouble() throws -> Double {
            guard try readByte() == 0xfb else { throw BackupArchiveCodec.CodecError.invalidCBOR }
            return try readDoublePayload()
        }

        private mutating func readDoublePayload() throws -> Double {
            Double(bitPattern: try readInteger(as: UInt64.self))
        }

        private mutating func readHeader() throws -> (UInt8, UInt64) {
            let initial = try readByte()
            return (initial >> 5, try readArgument(initial & 0x1f))
        }

        private mutating func readArgument(_ additional: UInt8) throws -> UInt64 {
            switch additional {
                case 0..<24: UInt64(additional)
                case 24: UInt64(try readByte())
                case 25: UInt64(try readInteger(as: UInt16.self))
                case 26: UInt64(try readInteger(as: UInt32.self))
                case 27: try readInteger(as: UInt64.self)
                default: throw BackupArchiveCodec.CodecError.invalidCBOR
            }
        }

        private mutating func readByte() throws -> UInt8 {
            guard offset < data.endIndex else { throw BackupArchiveCodec.CodecError.invalidCBOR }
            defer { offset += 1 }
            return data[offset]
        }

        private mutating func readInteger<T: FixedWidthInteger>(as type: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            guard size <= remaining else { throw BackupArchiveCodec.CodecError.invalidCBOR }
            var value: T = 0
            for byte in data[offset..<(offset + size)] {
                value = value << 8 | T(byte)
            }
            offset += size
            return value
        }
    }
}

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        for shift in stride(from: (MemoryLayout<T>.size - 1) * 8, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> T(shift)))
        }
    }

    func integer<T: FixedWidthInteger>(at offset: Int, as type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= count else { throw BackupArchiveCodec.CodecError.invalidHeader }
        // count is relative but subscripting is not, so the read has to be anchored to the start index
        let start = startIndex + offset
        var value: T = 0
        for byte in self[start..<(start + size)] {
            value = value << 8 | T(byte)
        }
        return value
    }
}

//
//  BackupArchiveTests.swift
//  AidokuTests
//
// Created by Amqx on 8/24/26.
//

import Compression
import Foundation
import Testing

@testable import Aidoku

struct BackupArchiveTests {
    // MARK: - Round trips

    @Test func roundTrip() throws {
        let backup = makeBackup()
        let data = try BackupArchiveCodec.encode(backup)

        #expect(data.starts(with: Data("AIB2".utf8)))
        #expect(try BackupArchiveCodec.decode(data) == backup)
    }

    /// Round trips a backup whose sections are all populated, with the value kinds the compact
    /// encoding has to special-case: nested dictionaries, dates, floats, booleans and raw data.
    @Test func populatedBackupRoundTrip() throws {
        let backup = try makeRichBackup()
        let data = try BackupArchiveCodec.encode(backup)
        let decoded = try BackupArchiveCodec.decode(data)

        #expect(decoded == backup)
        // called out individually so a failure names the value kind that drifted
        #expect(decoded.chapters?.map(\.chapter) == backup.chapters?.map(\.chapter))
        #expect(decoded.chapters?.map(\.dateUploaded) == backup.chapters?.map(\.dateUploaded))
        #expect(decoded.chapters?.map(\.locked) == backup.chapters?.map(\.locked))
        #expect(decoded.manga?.map(\.tags) == backup.manga?.map(\.tags))
        #expect(decoded.manga?.map(\.nextUpdateTime) == backup.manga?.map(\.nextUpdateTime))
        #expect(decoded.categories?.map(\.data) == backup.categories?.map(\.data))
        #expect(decoded.sources?.map(\.config) == backup.sources?.map(\.config))
        #expect(decoded.settings == backup.settings)
    }

    @Test func suppliedBackupRoundTrip() throws {
        // opt-in check against a real backup on disk; the generated fixtures above are what runs by default
        guard let path = ProcessInfo.processInfo.environment["AIDOKU_BACKUP_SAMPLE"] else { return }
        let source = try Data(contentsOf: URL(fileURLWithPath: path))
        let backup = try #require(try? PropertyListDecoder().decode(Backup.self, from: source))
        let encoded = try BackupArchiveCodec.encode(backup)

        let decoded = try BackupArchiveCodec.decode(encoded)
        let sections = [
            "library": backup.library == decoded.library,
            "history": backup.history == decoded.history,
            "manga": backup.manga == decoded.manga,
            "chapters": backup.chapters == decoded.chapters,
            "trackItems": backup.trackItems == decoded.trackItems,
            "readingSessions": backup.readingSessions == decoded.readingSessions,
            "updates": backup.updates == decoded.updates,
            "categories": backup.categories == decoded.categories,
            "sourceLists": backup.sourceLists == decoded.sourceLists,
            "sources": backup.sources == decoded.sources,
            "settings": backup.settings == decoded.settings
        ]
        let mismatches = sections.compactMap { $0.value ? nil : $0.key }
        if !mismatches.isEmpty {
            Issue.record("Mismatched sections: \(mismatches.sorted()) AIB2_SIZE=\(encoded.count)")
            return
        }
        #expect(decoded == backup)
        print("AIB2_SIZE=\(encoded.count) ORIGINAL_SIZE=\(source.count)")
    }

    @Test func legacyBinaryPlistStillLoads() throws {
        let backup = makeBackup()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(backup)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(Backup.load(from: url) == backup)
    }

    /// Payloads written before the encoder streamed its output were compressed in one shot; those
    /// archives are still out there and have to keep decoding.
    @Test func bufferCompressedPayloadStillDecodes() throws {
        let backup = try makeRichBackup()
        let original = try BackupArchiveCodec.encode(backup)

        #expect(try BackupArchiveCodec.decode(rebuilt(archive: original)) == backup)
    }

    // MARK: - Summary

    @Test func summaryDoesNotDecodePayload() throws {
        let backup = makeBackup()
        var data = try BackupArchiveCodec.encode(backup)
        data[data.index(before: data.endIndex)] ^= 0xff

        let summary = try #require(BackupArchiveCodec.summary(from: data))
        #expect(summary.name == backup.name)
        #expect(summary.date == backup.date)
        #expect(summary.counts.manga == 0)
        #expect(throws: (any Error).self) {
            try BackupArchiveCodec.decode(data)
        }
    }

    /// Each section is given a different length, so a summary that encoded counts positionally
    /// would report them against the wrong labels here.
    @Test func summaryCountsMatchTheirSections() throws {
        let backup = try makeRichBackup()
        let data = try BackupArchiveCodec.encode(backup)

        let counts = try #require(BackupArchiveCodec.summary(from: data)).counts
        #expect(counts.library == backup.library?.count)
        #expect(counts.history == backup.history?.count)
        #expect(counts.manga == backup.manga?.count)
        #expect(counts.chapters == backup.chapters?.count)
        #expect(counts.trackItems == backup.trackItems?.count)
        #expect(counts.readingSessions == backup.readingSessions?.count)
        #expect(counts.updates == backup.updates?.count)
        #expect(counts.categories == backup.categories?.count)
        #expect(counts.sources == backup.sources?.count)
        #expect(counts.sourceLists == backup.sourceLists?.count)
        #expect(counts.settings == backup.settings?.count)
    }

    // MARK: - Untrusted input
    //
    // Every case below aborted the process before the decoder bounded its length fields, so a
    // regression here fails the run by crashing it rather than by recording an issue.

    @Test func rejectsStringTableLongerThanTheInput() {
        let payload = cborPrefix + cborHeader(major: 4, value: 1 << 48)

        #expect(throws: (any Error).self) { try BackupArchiveCodec.decode(archive(cbor: payload)) }
    }

    @Test func rejectsArrayLongerThanTheInput() {
        let payload = cborPrefix + Data([0x80]) + cborHeader(major: 4, value: 1 << 48)

        #expect(throws: (any Error).self) { try BackupArchiveCodec.decode(archive(cbor: payload)) }
    }

    @Test func rejectsMapLongerThanTheInput() {
        let payload = cborPrefix + Data([0x80]) + cborHeader(major: 5, value: 1 << 48)

        #expect(throws: (any Error).self) { try BackupArchiveCodec.decode(archive(cbor: payload)) }
    }

    @Test func rejectsByteStringLongerThanTheInput() {
        let payload = cborPrefix + Data([0x80]) + cborHeader(major: 2, value: 1 << 48)

        #expect(throws: (any Error).self) { try BackupArchiveCodec.decode(archive(cbor: payload)) }
    }

    @Test func rejectsDeeplyNestedArrays() {
        // a few hundred kilobytes of nesting, which compresses down to well under a kilobyte
        let payload = cborPrefix + Data([0x80]) + Data(repeating: 0x81, count: 500_000) + Data([0x00])

        #expect(throws: (any Error).self) { try BackupArchiveCodec.decode(archive(cbor: payload)) }
    }

    @Test func rejectsPayloadLargerThanItsDeclaredSize() throws {
        let payload = Data(repeating: 0, count: 4 << 20)

        #expect(throws: (any Error).self) {
            try BackupArchiveCodec.decode(archive(cbor: payload, declaredSize: 1024))
        }
    }

    @Test func rejectsDeclaredSizePastTheCap() throws {
        let backup = makeBackup()
        let original = try BackupArchiveCodec.encode(backup)

        #expect(throws: (any Error).self) {
            try BackupArchiveCodec.decode(rebuilt(archive: original, declaredSize: 2_000_000_000))
        }
    }

    @Test func decodesArchiveStoredAtANonZeroOffset() throws {
        let backup = try makeRichBackup()
        var padded = Data(repeating: 0x7f, count: 100)
        padded.append(try BackupArchiveCodec.encode(backup))
        let slice = padded[100...]

        #expect(try BackupArchiveCodec.decode(slice) == backup)
        #expect(BackupArchiveCodec.summary(from: slice)?.counts.manga == backup.manga?.count)
    }

    @Test func truncationAndCorruptionAreRejectedNotTrapped() throws {
        let data = try BackupArchiveCodec.encode(makeBackup())

        for length in stride(from: 0, to: data.count, by: 3) {
            _ = try? BackupArchiveCodec.decode(data.prefix(length))
        }
        for index in data.indices {
            var corrupt = data
            corrupt[index] ^= 0xa5
            _ = try? BackupArchiveCodec.decode(corrupt)
        }
    }

    // MARK: - Fixtures

    private func makeBackup() -> Backup {
        Backup(
            library: [],
            history: [],
            manga: [],
            chapters: [],
            trackItems: [],
            readingSessions: [],
            updates: [],
            categories: [],
            sources: [],
            sourceLists: ["https://example.com/list.json"],
            settings: ["Reader.readingMode": .int(2)],
            date: Date(timeIntervalSince1970: 1_700_000_000),
            name: "Test Backup",
            automatic: true,
            version: "1.2.3"
        )
    }

    /// A backup with every section filled and a different number of items in each.
    ///
    /// Most of the item types declare their own initializer, so the fixture is built as a property
    /// list and decoded, which is also the shape a real backup arrives in.
    private func makeRichBackup() throws -> Backup {
        func date(_ offset: Double) -> Date {
            Date(timeIntervalSince1970: 1_700_000_000 + offset)
        }

        let library: [[String: Any]] = (0..<3).map { index in
            [
                "mangaId": "manga-\(index)",
                "sourceId": "source-\(index % 2)",
                "lastOpened": date(Double(index) + 0.25),
                "lastUpdated": date(Double(index) + 0.5),
                "dateAdded": date(Double(index)),
                "categories": ["reading", "favourites"]
            ]
        }
        let history: [[String: Any]] = (0..<4).map { index in
            [
                "dateRead": date(Double(index) + 0.125),
                "sourceId": "source-0",
                "chapterId": "chapter-\(index)",
                "mangaId": "manga-0",
                "progress": index,
                "total": 20,
                "completed": index % 2 == 0
            ]
        }
        let manga: [[String: Any]] = (0..<2).map { index in
            [
                "id": "manga-\(index)",
                "sourceId": "source-\(index)",
                "title": "Some Title \(index) — ünïcödé 日本語",
                "desc": String(repeating: "long description ", count: 20),
                "tags": ["action", "adventure"],
                "status": index,
                "nsfw": 0,
                "viewer": 2,
                "neverUpdate": index == 1,
                "nextUpdateTime": date(86_400 + Double(index)),
                "scanlatorFilter": ["group a", "group b"]
            ]
        }
        // widened from Float, since a property list number that does not fit in Float is rejected
        let chapterNumbers: [Double] = [12.5, Double(Float(1) / 3), -0.125, Double(Float(1e-8)), 4]
        let chapters: [[String: Any]] = chapterNumbers.enumerated().map { index, number in
            [
                "sourceId": "source-0",
                "mangaId": "manga-0",
                "id": "chapter-\(index)",
                "lang": "en",
                "chapter": number,
                "volume": Double(index) + 0.5,
                "dateUploaded": date(Double(index) * 3600 + 0.75),
                "locked": index % 2 == 0,
                "sourceOrder": index
            ]
        }
        let trackItems: [[String: Any]] = [
            ["id": "track-0", "trackerId": "anilist", "mangaId": "manga-0", "sourceId": "source-0", "chapterOffset": -3]
        ]
        let readingSessions: [[String: Any]] = (0..<6).map { index in
            [
                "pagesRead": index * 5,
                "startDate": date(Double(index) * 60),
                "endDate": date(Double(index) * 60 + 45),
                "sourceId": "source-0",
                "mangaId": "manga-0",
                "chapterId": "chapter-\(index % 5)"
            ]
        }
        let updates: [[String: Any]] = (0..<7).map { index in
            [
                "date": date(Double(index) * 120),
                "viewed": index % 3 == 0,
                "sourceId": "source-0",
                "mangaId": "manga-0",
                "chapterId": "chapter-\(index % 5)"
            ]
        }
        let categories: [[String: Any]] = (0..<8).map { index in
            [
                "title": "category-\(index)",
                "sort": index,
                "group": index % 2 == 0,
                "data": Data((0...UInt8(index)).map { $0 &* 37 })
            ]
        }
        let sources: [[String: Any]] = (0..<9).map { index in
            var source: [String: Any] = ["id": "source-\(index)"]
            // BackupSource only writes its other fields when a config is present
            if index % 3 == 0 {
                source["apiVersion"] = "0.\(index)"
                source["config"] = Data(repeating: UInt8(index), count: 300)
            }
            return source
        }
        let settings: [String: Any] = Dictionary(
            uniqueKeysWithValues: (0..<11).map { index -> (String, Any) in
                switch index % 4 {
                    case 0: ("Reader.setting\(index)", index)
                    case 1: ("Reader.setting\(index)", "value-\(index)")
                    case 2: ("Reader.setting\(index)", index % 2 == 0)
                    default: ("Reader.setting\(index)", Double(index) + 0.5)
                }
            }
        )

        let plist: [String: Any] = [
            "library": library,
            "history": history,
            "manga": manga,
            "chapters": chapters,
            "trackItems": trackItems,
            "readingSessions": readingSessions,
            "updates": updates,
            "categories": categories,
            "sources": sources,
            "sourceLists": (0..<10).map { "https://example.com/list-\($0).json" },
            "settings": settings,
            "date": date(0),
            "name": "Rich Backup",
            "automatic": true,
            "version": "1.2.3"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        return try PropertyListDecoder().decode(Backup.self, from: data)
    }

    // MARK: - Archive construction
    //
    // The envelope is `AIB2`, a version byte, the uncompressed payload size, the summary size, the
    // summary, and the LZFSE payload. Building it here is what lets a crafted payload reach the
    // decoder without going through the encoder first.

    private let cborPrefix = Data([0xd9, 0x01, 0x00, 0x82]) // tag(256), array(2)

    private func cborHeader(major: UInt8, value: UInt64) -> Data {
        var data = Data([major << 5 | 27])
        appendBigEndian(value, to: &data)
        return data
    }

    private func archive(cbor: Data, declaredSize: Int? = nil) -> Data {
        var data = Data("AIB2".utf8)
        data.append(1)
        appendBigEndian(UInt64(declaredSize ?? cbor.count), to: &data)
        appendBigEndian(UInt32(0), to: &data) // no summary block
        data.append(compress(cbor))
        return data
    }

    /// Rebuilds an archive around its own payload, compressed in one shot rather than streamed.
    private func rebuilt(archive original: Data, declaredSize: Int? = nil) throws -> Data {
        var size = 0
        for index in 5..<13 { size = size << 8 | Int(original[index]) }
        var summarySize = 0
        for index in 13..<17 { summarySize = summarySize << 8 | Int(original[index]) }

        var payload = Data(count: size)
        let produced = payload.withUnsafeMutableBytes { output in
            original[(17 + summarySize)...].withUnsafeBytes { input in
                compression_decode_buffer(
                    output.bindMemory(to: UInt8.self).baseAddress!,
                    size,
                    input.bindMemory(to: UInt8.self).baseAddress!,
                    input.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        try #require(produced == size)
        return archive(cbor: payload, declaredSize: declaredSize)
    }

    private func compress(_ data: Data) -> Data {
        var destination = Data(count: data.count + 65_536)
        let count = destination.withUnsafeMutableBytes { output in
            data.withUnsafeBytes { input in
                compression_encode_buffer(
                    output.bindMemory(to: UInt8.self).baseAddress!,
                    output.count,
                    input.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        destination.count = count
        return destination
    }

    private func appendBigEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }
}

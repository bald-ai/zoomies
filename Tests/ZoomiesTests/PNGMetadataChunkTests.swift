import XCTest
import AppKit
@testable import Zoomies

/// Chunk-level checks for `PNGMetadata`: CRC correctness against an
/// independent reference, slice-safe iTXt parsing, and Zoomies chunk stripping.
final class PNGMetadataChunkTests: XCTestCase {
    // MARK: - Independent PNG helpers

    private struct Chunk {
        let type: String
        let payload: Data
        let storedCRC: UInt32
        let raw: Data
    }

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = (crc & 1) != 0 ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    /// Reference CRC-32 (ISO-HDLC), deliberately independent of the app's
    /// zlib-backed implementation.
    private static func referenceCRC32<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func readBigEndian(_ bytes: [UInt8], at index: Int) -> UInt32 {
        (UInt32(bytes[index]) << 24) | (UInt32(bytes[index + 1]) << 16)
            | (UInt32(bytes[index + 2]) << 8) | UInt32(bytes[index + 3])
    }

    private func chunks(of png: Data, file: StaticString = #filePath, line: UInt = #line) throws -> [Chunk] {
        let bytes = [UInt8](png)
        XCTAssertTrue(PNGMetadata.isPNG(png), file: file, line: line)
        var result: [Chunk] = []
        var index = 8
        while index + 12 <= bytes.count {
            let length = Int(Self.readBigEndian(bytes, at: index))
            let end = index + 12 + length
            guard end <= bytes.count else {
                XCTFail("Truncated chunk at \(index)", file: file, line: line)
                break
            }
            let type = String(decoding: bytes[(index + 4)..<(index + 8)], as: UTF8.self)
            result.append(Chunk(type: type,
                                payload: Data(bytes[(index + 8)..<(index + 8 + length)]),
                                storedCRC: Self.readBigEndian(bytes, at: end - 4),
                                raw: Data(bytes[index..<end])))
            index = end
            if type == "IEND" { break }
        }
        XCTAssertEqual(index, bytes.count, "No trailing bytes after IEND", file: file, line: line)
        return result
    }

    private static func makeChunk(type: String, payload: [UInt8]) -> Data {
        let typeAndPayload = Array(type.utf8) + payload
        return Data(bigEndian(UInt32(payload.count)) + typeAndPayload + bigEndian(referenceCRC32(typeAndPayload)))
    }

    private static func iTXtPayload(keyword: String, compressed: Bool = false, text: String) -> [UInt8] {
        Array(keyword.utf8) + [0x00, compressed ? 0x01 : 0x00, 0x00, 0x00, 0x00] + Array(text.utf8)
    }

    private func inserting(_ extraChunks: [Data], beforeIENDOf png: Data) throws -> Data {
        let parsed = try chunks(of: png)
        var result = Data(png.prefix(8))
        for chunk in parsed {
            if chunk.type == "IEND" { extraChunks.forEach { result.append($0) } }
            result.append(chunk.raw)
        }
        return result
    }

    private func iTXtKeywords(in png: Data) throws -> [String] {
        try chunks(of: png).filter { $0.type == "iTXt" }.map { chunk in
            let keywordEnd = chunk.payload.firstIndex(of: 0) ?? chunk.payload.endIndex
            return String(decoding: chunk.payload[chunk.payload.startIndex..<keywordEnd], as: UTF8.self)
        }
    }

    private func assertAllCRCsValid(_ png: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let parsed = try chunks(of: png, file: file, line: line)
        XCTAssertFalse(parsed.isEmpty, file: file, line: line)
        for chunk in parsed {
            let expected = Self.referenceCRC32(Array(chunk.type.utf8) + [UInt8](chunk.payload))
            XCTAssertEqual(chunk.storedCRC, expected, "Bad CRC on \(chunk.type) chunk", file: file, line: line)
        }
    }

    // MARK: - CRC

    func testReferenceCRCMatchesStandardCheckValue() {
        XCTAssertEqual(Self.referenceCRC32(Array("123456789".utf8)), 0xCBF4_3926)
    }

    func testEveryChunkWrittenByEmbedHasAValidCRC() throws {
        let burned = try TestSupport.solidImagePNGData(width: 40, height: 20, color: .systemRed)
        let original = try TestSupport.solidImagePNGData(width: 30, height: 15, color: .systemBlue)
        let state = EditorCanvasState(baseImagePNG: original,
                                      items: [.rect(rect: .init(NSRect(x: 1, y: 2, width: 10, height: 8)),
                                                    color: .init(.systemRed), lineWidth: 4)])

        let full = try XCTUnwrap(PNGMetadata.embed(intoPNG: burned, originalPNG: original,
                                                   prompt: "Prompt ünicode 🚀", editorState: state))
        try assertAllCRCsValid(full)
        XCTAssertEqual(try iTXtKeywords(in: full),
                       [PNGMetadata.originalPNGKeyword, PNGMetadata.promptKeyword, PNGMetadata.editorStateKeyword])

        let stateOnly = try XCTUnwrap(PNGMetadata.embed(intoPNG: burned, editorState: state))
        try assertAllCRCsValid(stateOnly)

        let stub = try XCTUnwrap(TestSupport.stubPNGDeclaringSize(width: 7, height: 9))
        try assertAllCRCsValid(stub)
    }

    // MARK: - Slice-safe iTXt parsing

    /// Places `payload` after junk bytes so the slice's startIndex is nonzero.
    private func offsetSlice(_ payload: [UInt8], offset: Int = 5) -> ArraySlice<UInt8> {
        let backing = [UInt8](repeating: 0xAB, count: offset) + payload + [0xCD, 0xEF]
        let slice = backing[offset..<(offset + payload.count)]
        XCTAssertEqual(slice.startIndex, offset)
        return slice
    }

    func testParseITXtReadsTextFromSliceWithNonzeroStartIndex() {
        let payload = Self.iTXtPayload(keyword: "Zoomies-Prompt-v1", text: "héllo 🚀")
        XCTAssertEqual(PNGMetadata.parseITXt(offsetSlice(payload)), "héllo 🚀")
        XCTAssertEqual(PNGMetadata.parseITXt(offsetSlice(payload, offset: 0)), "héllo 🚀")
        XCTAssertEqual(PNGMetadata.parseITXt(offsetSlice(Self.iTXtPayload(keyword: "K", text: ""))), "")
    }

    func testParseITXtRejectsEmptyTruncatedAndCompressedPayloadsInSlices() {
        let keyword = Array("Zoomies-Prompt-v1".utf8)
        let cases: [(String, [UInt8])] = [
            ("empty", []),
            ("keyword without terminator", keyword),
            ("ends after keyword terminator", keyword + [0x00]),
            ("ends after compression flag", keyword + [0x00, 0x00]),
            ("missing language terminator", keyword + [0x00, 0x00, 0x00] + Array("en".utf8)),
            ("missing translated-keyword terminator", keyword + [0x00, 0x00, 0x00, 0x00] + Array("Prompt".utf8)),
            ("compressed", Self.iTXtPayload(keyword: "Zoomies-Prompt-v1", compressed: true, text: "x")),
            ("invalid UTF-8 text", keyword + [0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFE])
        ]
        for (name, payload) in cases {
            XCTAssertNil(PNGMetadata.parseITXt(offsetSlice(payload)), name)
        }
    }

    // MARK: - Stripping

    func testEmbedStripsCompressedAndMalformedZoomiesChunksButKeepsOtherTextChunks() throws {
        let burned = try TestSupport.solidImagePNGData(width: 40, height: 20, color: .systemRed)
        let original = try TestSupport.solidImagePNGData(width: 30, height: 15, color: .systemBlue)
        let foreignText = Self.makeChunk(type: "iTXt", payload: Self.iTXtPayload(keyword: "Comment", text: "keep me"))
        let polluted = try inserting([
            Self.makeChunk(type: "iTXt", payload: Self.iTXtPayload(keyword: PNGMetadata.promptKeyword,
                                                                  compressed: true, text: "stale")),
            Self.makeChunk(type: "iTXt", payload: Array(PNGMetadata.editorStateKeyword.utf8) + [0x00]),
            Self.makeChunk(type: "iTXt", payload: Self.iTXtPayload(keyword: PNGMetadata.originalPNGKeyword,
                                                                  text: "not base64")),
            foreignText
        ], beforeIENDOf: burned)

        let embedded = try XCTUnwrap(PNGMetadata.embed(intoPNG: polluted, originalPNG: original, prompt: "fresh"))

        XCTAssertEqual(try iTXtKeywords(in: embedded),
                       ["Comment", PNGMetadata.originalPNGKeyword, PNGMetadata.promptKeyword],
                       "Stale Zoomies chunks are removed whatever their encoding; foreign text survives")
        XCTAssertTrue(try chunks(of: embedded).contains { $0.raw == foreignText })
        let extracted = try XCTUnwrap(PNGMetadata.extract(fromPNG: embedded))
        XCTAssertEqual(extracted.prompt, "fresh")
        XCTAssertEqual(extracted.originalPNG, original)
        try assertAllCRCsValid(embedded)
    }

    func testReEmbeddingIsIdempotent() throws {
        let burned = try TestSupport.solidImagePNGData(width: 40, height: 20, color: .systemRed)
        let original = try TestSupport.solidImagePNGData(width: 30, height: 15, color: .systemBlue)
        let state = EditorCanvasState(baseImagePNG: original, items: [])

        // JSONEncoder key order is unspecified, so compare everything except the
        // editor-state JSON bytes, and compare that chunk by decoded content.
        func structure(_ png: Data) throws -> [Data] {
            try chunks(of: png).map { chunk in
                chunk.type == "iTXt" && chunk.payload.starts(with: Array(PNGMetadata.editorStateKeyword.utf8))
                    ? Data(PNGMetadata.editorStateKeyword.utf8)
                    : chunk.raw
            }
        }

        let once = try XCTUnwrap(PNGMetadata.embed(intoPNG: burned, originalPNG: original, prompt: "p", editorState: state))
        let twice = try XCTUnwrap(PNGMetadata.embed(intoPNG: once, originalPNG: original, prompt: "p", editorState: state))
        XCTAssertEqual(try structure(once), try structure(twice))
        XCTAssertEqual(PNGMetadata.extractEditorState(fromPNG: twice)?.baseImagePNG, original)

        let stateOnce = try XCTUnwrap(PNGMetadata.embed(intoPNG: once, editorState: state))
        let stateTwice = try XCTUnwrap(PNGMetadata.embed(intoPNG: stateOnce, editorState: state))
        XCTAssertEqual(try structure(stateOnce), try structure(stateTwice))
        XCTAssertEqual(try iTXtKeywords(in: stateTwice), [PNGMetadata.editorStateKeyword])
    }

    func testEmbedPreservesEveryImageChunkOfAManyChunkPNG() throws {
        let png = try TestSupport.noiseImagePNGData(width: 400, height: 300)
        let originalChunks = try chunks(of: png)
        XCTAssertGreaterThan(originalChunks.filter { $0.type == "IDAT" }.count, 20,
                             "Fixture must span many IDAT chunks to exercise the chunk walk")

        let embedded = try XCTUnwrap(PNGMetadata.embed(intoPNG: png, originalPNG: png, prompt: "many"))
        let reEmbedded = try XCTUnwrap(PNGMetadata.embed(intoPNG: embedded, originalPNG: png, prompt: "many again"))

        for output in [embedded, reEmbedded] {
            let nonZoomies = try chunks(of: output).filter { $0.type != "iTXt" }.map(\.raw)
            XCTAssertEqual(nonZoomies, originalChunks.map(\.raw), "Image chunks must be copied byte-for-byte, in order")
            try assertAllCRCsValid(output)
        }
        XCTAssertEqual(PNGMetadata.extract(fromPNG: reEmbedded)?.prompt, "many again")
        XCTAssertEqual(PNGMetadata.extract(fromPNG: reEmbedded)?.originalPNG, png)
    }

    func testPixelDimensionsOnlyNeedsTheHeader() throws {
        let png = try TestSupport.noiseImagePNGData(width: 33, height: 21)
        let dims = try XCTUnwrap(PNGMetadata.pixelDimensions(ofPNG: png.prefix(24)))
        XCTAssertEqual(dims.width, 33)
        XCTAssertEqual(dims.height, 21)
        XCTAssertNil(PNGMetadata.pixelDimensions(ofPNG: png.prefix(23)))
        // A Data slice with a nonzero start index still reads correctly.
        let sliced = (Data([0, 1, 2]) + png).dropFirst(3)
        XCTAssertEqual(PNGMetadata.pixelDimensions(ofPNG: sliced)?.width, 33)
        XCTAssertEqual(PNGMetadata.pixelDimensions(ofPNG: sliced)?.height, 21)
    }
}

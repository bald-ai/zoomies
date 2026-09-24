import Foundation
import zlib

/// Embeds and extracts Zoomies round-trip metadata in PNG text chunks so a
/// saved screenshot can carry its clean (pre-note) original plus the prompt
/// text that was burned onto it.
///
/// We manipulate PNG chunks directly instead of going through ImageIO's
/// `kCGImagePropertyPNGDictionary`: that dictionary only round-trips a fixed set
/// of standard tEXt keywords (Title, Author, Description, ...) and cannot write
/// the custom keywords this feature needs. The payloads are stored in
/// uncompressed `iTXt` chunks, which are UTF-8 safe.
enum PNGMetadata {
    /// Keyword for the base64-encoded clean original PNG.
    static let originalPNGKeyword = "Zoomies-OriginalPNG-v1"
    /// Keyword for the UTF-8 prompt text.
    static let promptKeyword = "Zoomies-Prompt-v1"
    /// Keyword for the JSON-encoded editable canvas state.
    static let editorStateKeyword = "Zoomies-EditorState-v1"

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let iTXtType = Array("iTXt".utf8)
    private static let zoomiesKeywords = [originalPNGKeyword, promptKeyword, editorStateKeyword]

    /// Inserts the original PNG bytes and prompt as `iTXt` chunks just before
    /// `IEND`. Returns nil if either input is not a PNG, or the input PNG is
    /// malformed.
    static func embed(intoPNG pngData: Data,
                      originalPNG: Data,
                      prompt: String,
                      editorState: EditorCanvasState? = nil) -> Data? {
        let bytes = [UInt8](pngData)
        guard hasPNGSignature(bytes), isPNG(originalPNG) else { return nil }
        guard let iendStart = indexOfChunk(named: "IEND", in: bytes) else { return nil }

        let originalChunk = makeITXtChunk(keyword: originalPNGKeyword, text: originalPNG.base64EncodedData())
        let promptChunk = makeITXtChunk(keyword: promptKeyword, text: Data(prompt.utf8))
        let editorStateChunk = encodeEditorState(editorState).map { makeITXtChunk(keyword: editorStateKeyword, text: $0) }

        var result = Data()
        result.reserveCapacity(bytes.count + originalChunk.count + promptChunk.count + (editorStateChunk?.count ?? 0))
        result.append(stripZoomiesChunks(from: bytes[0..<iendStart]))
        result.append(originalChunk)
        result.append(promptChunk)
        if let editorStateChunk {
            result.append(editorStateChunk)
        }
        result.append(contentsOf: bytes[iendStart...])
        return result
    }

    static func embed(intoPNG pngData: Data, editorState: EditorCanvasState) -> Data? {
        let bytes = [UInt8](pngData)
        guard hasPNGSignature(bytes) else { return nil }
        guard let iendStart = indexOfChunk(named: "IEND", in: bytes),
              let editorStateText = encodeEditorState(editorState) else { return nil }

        let editorStateChunk = makeITXtChunk(keyword: editorStateKeyword, text: editorStateText)
        var result = Data()
        result.reserveCapacity(bytes.count + editorStateChunk.count)
        result.append(stripZoomiesChunks(from: bytes[0..<iendStart]))
        result.append(editorStateChunk)
        result.append(contentsOf: bytes[iendStart...])
        return result
    }

    /// Extracts the embedded clean original and prompt. Returns nil for non-PNG
    /// input, when either chunk is missing, or when a chunk/original image
    /// exceeds safety limits.
    static func extract(fromPNG pngData: Data,
                        limits: ImageSafetyLimits = .runtime) -> (originalPNG: Data, prompt: String)? {
        let bytes = [UInt8](pngData)
        guard hasPNGSignature(bytes) else { return nil }

        var original: Data?
        var prompt: String?
        var index = 8
        while index + 8 <= bytes.count {
            guard let length = readUInt32(bytes, at: index) else { break }
            let typeStart = index + 4
            let dataStart = typeStart + 4
            let len = Int(length)
            guard dataStart + len + 4 <= bytes.count else { break }

            let type = String(bytes: bytes[typeStart..<dataStart], encoding: .ascii) ?? ""
            if type == "iTXt" {
                if isKeyword(originalPNGKeyword, in: bytes, dataStart: dataStart, length: len) {
                    if len > limits.maxOriginalPNGChunkBytes {
                        return nil
                    }
                    if let text = parseITXt(bytes[dataStart..<dataStart + len]),
                       let decoded = Data(base64Encoded: text),
                       ImageSafety.isSafePNG(decoded, limits: limits),
                       decoded.count <= limits.maxEmbeddedImageBytes {
                        original = decoded
                    } else {
                        return nil
                    }
                } else if isKeyword(promptKeyword, in: bytes, dataStart: dataStart, length: len) {
                    if len > limits.maxPromptChunkBytes {
                        return nil
                    }
                    if let text = parseITXt(bytes[dataStart..<dataStart + len]),
                       text.count <= limits.maxPromptLength {
                        prompt = text
                    } else {
                        return nil
                    }
                }
            }
            if type == "IEND" { break }
            index = dataStart + len + 4
        }

        guard let original, let prompt else { return nil }
        return (original, prompt)
    }

    static func extractEditorState(fromPNG pngData: Data,
                                   limits: EditorCanvasState.SafetyLimits = .runtime) -> EditorCanvasState? {
        let bytes = [UInt8](pngData)
        guard hasPNGSignature(bytes) else { return nil }

        var editorState: EditorCanvasState?
        var index = 8
        while index + 8 <= bytes.count {
            guard let length = readUInt32(bytes, at: index) else { break }
            let typeStart = index + 4
            let dataStart = typeStart + 4
            let len = Int(length)
            guard dataStart + len + 4 <= bytes.count else { break }

            let type = String(bytes: bytes[typeStart..<dataStart], encoding: .ascii) ?? ""
            if type == "iTXt",
               isKeyword(editorStateKeyword, in: bytes, dataStart: dataStart, length: len) {
                if len > limits.maxEditorStateChunkBytes {
                    return nil
                }
                if let text = parseITXt(bytes[dataStart..<dataStart + len]) {
                    editorState = decodeEditorState(text, limits: limits)
                }
            }
            if type == "IEND" { break }
            index = dataStart + len + 4
        }

        return editorState
    }

    /// True when the data starts with the 8-byte PNG signature.
    static func isPNG(_ data: Data) -> Bool {
        hasPNGSignature([UInt8](data.prefix(8)))
    }

    // MARK: - Chunk building

    /// `text` must already be UTF-8 bytes (base64 and JSON output both are).
    private static func makeITXtChunk(keyword: String, text: Data) -> Data {
        var payload = Data()
        payload.reserveCapacity(keyword.utf8.count + 5 + text.count)
        payload.append(contentsOf: keyword.utf8)
        payload.append(0x00) // keyword null separator
        payload.append(0x00) // compression flag: uncompressed
        payload.append(0x00) // compression method
        payload.append(0x00) // empty language tag, terminated
        payload.append(0x00) // empty translated keyword, terminated
        payload.append(text)
        return assembleChunk(type: "iTXt", payload: payload)
    }

    /// JSON-encoded state; `JSONEncoder` always produces UTF-8.
    private static func encodeEditorState(_ editorState: EditorCanvasState?) -> Data? {
        guard let editorState else { return nil }
        return try? JSONEncoder().encode(editorState)
    }

    private static func decodeEditorState(_ text: String,
                                          limits: EditorCanvasState.SafetyLimits = .runtime) -> EditorCanvasState? {
        guard let data = text.data(using: .utf8),
              let state = try? JSONDecoder().decode(EditorCanvasState.self, from: data),
              state.isSafeToRestore(limits: limits) else {
            return nil
        }
        return state
    }

    /// Reads width/height from the IHDR chunk without allocating a bitmap.
    static func pixelDimensions(ofPNG data: Data) -> (width: Int, height: Int)? {
        // Signature + IHDR length/type + width/height fit in the first 24 bytes.
        let bytes = [UInt8](data.prefix(24))
        guard hasPNGSignature(bytes), bytes.count >= 24 else { return nil }
        let type = String(bytes: bytes[12..<16], encoding: .ascii)
        guard type == "IHDR",
              let width = readUInt32(bytes, at: 16),
              let height = readUInt32(bytes, at: 20),
              width > 0,
              height > 0 else {
            return nil
        }
        return (Int(width), Int(height))
    }

    /// Minimal PNG with a declared IHDR size and no pixel payload. Used to
    /// inspect dimensions without allocating a decoded bitmap.
    static func stubPNGDeclaringSize(width: Int, height: Int) -> Data? {
        guard width > 0, height > 0,
              width <= Int(UInt32.max), height <= Int(UInt32.max) else {
            return nil
        }
        var ihdr = Data()
        ihdr.append(contentsOf: bigEndianBytes(UInt32(width)))
        ihdr.append(contentsOf: bigEndianBytes(UInt32(height)))
        ihdr.append(contentsOf: [8, 2, 0, 0, 0]) // 8-bit truecolor, no interlace
        let ihdrChunk = assembleChunk(type: "IHDR", payload: ihdr)
        let iendChunk = assembleChunk(type: "IEND", payload: Data())

        var png = Data(signature)
        png.append(ihdrChunk)
        png.append(iendChunk)
        return png
    }

    /// Indexes are absolute positions in `bytes`, so slices work unchanged.
    private static func isKeyword<Bytes: RandomAccessCollection>(_ keyword: String,
                                                                 in bytes: Bytes,
                                                                 dataStart: Int,
                                                                 length: Int) -> Bool
        where Bytes.Element == UInt8, Bytes.Index == Int {
        let keywordBytes = keyword.utf8
        let keywordEnd = dataStart + keywordBytes.count
        guard length > keywordBytes.count,
              dataStart >= bytes.startIndex,
              keywordEnd < bytes.endIndex else { return false }
        return bytes[dataStart..<keywordEnd].elementsEqual(keywordBytes) && bytes[keywordEnd] == 0
    }

    private static func assembleChunk(type: String, payload: Data) -> Data {
        var chunk = Data()
        chunk.reserveCapacity(payload.count + 12)
        chunk.append(contentsOf: bigEndianBytes(UInt32(payload.count)))
        chunk.append(contentsOf: type.utf8)
        chunk.append(payload)
        // The CRC covers the chunk type and payload, not the length.
        let crc = crc32(chunk[(chunk.startIndex + 4)...])
        chunk.append(contentsOf: bigEndianBytes(crc))
        return chunk
    }

    // MARK: - Chunk parsing

    /// Parses an uncompressed `iTXt` chunk payload and returns its text.
    /// Accepts a slice with any start index; returns nil for compressed,
    /// empty, or truncated payloads.
    static func parseITXt(_ data: ArraySlice<UInt8>) -> String? {
        guard let keywordNull = data.firstIndex(of: 0x00),
              String(bytes: data[data.startIndex..<keywordNull], encoding: .utf8) != nil else {
            return nil
        }

        var cursor = keywordNull + 1
        guard cursor + 2 <= data.endIndex else { return nil }
        let compressionFlag = data[cursor]
        cursor += 2 // skip compression flag + method
        guard compressionFlag == 0 else { return nil } // we only write uncompressed

        guard let languageNull = data[cursor..<data.endIndex].firstIndex(of: 0x00) else { return nil }
        cursor = languageNull + 1
        guard let translatedNull = data[cursor..<data.endIndex].firstIndex(of: 0x00) else { return nil }
        cursor = translatedNull + 1

        return String(bytes: data[cursor..<data.endIndex], encoding: .utf8)
    }

    private static func indexOfChunk(named name: String, in bytes: [UInt8]) -> Int? {
        let nameBytes = name.utf8
        var index = 8
        while index + 8 <= bytes.count {
            guard let length = readUInt32(bytes, at: index) else { return nil }
            let typeStart = index + 4
            let dataStart = typeStart + 4
            let len = Int(length)
            guard dataStart + len + 4 <= bytes.count else { return nil }
            if bytes[typeStart..<dataStart].elementsEqual(nameBytes) {
                return index
            }
            index = dataStart + len + 4
        }
        return nil
    }

    /// Drops every `iTXt` chunk whose keyword is a Zoomies keyword. Matching is
    /// on the keyword alone, so compressed or malformed Zoomies chunks are
    /// stripped too rather than left behind next to the fresh ones.
    private static func stripZoomiesChunks(from bytes: ArraySlice<UInt8>) -> Data {
        guard bytes.count >= 8 else { return Data(bytes) }

        var result = Data()
        result.reserveCapacity(bytes.count)
        result.append(contentsOf: bytes.prefix(8))

        var index = bytes.startIndex + 8
        while index + 8 <= bytes.endIndex {
            guard let length = readUInt32(bytes, at: index) else { break }
            let typeStart = index + 4
            let dataStart = typeStart + 4
            let len = Int(length)
            let chunkEnd = dataStart + len + 4
            guard chunkEnd <= bytes.endIndex else { break }

            let shouldSkip = bytes[typeStart..<dataStart].elementsEqual(iTXtType)
                && zoomiesKeywords.contains { isKeyword($0, in: bytes, dataStart: dataStart, length: len) }

            if !shouldSkip {
                result.append(contentsOf: bytes[index..<chunkEnd])
            }
            index = chunkEnd
        }

        return result
    }

    // MARK: - Bytes & CRC

    private static func hasPNGSignature(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 8 && Array(bytes[0..<8]) == signature
    }

    /// Big-endian read at an absolute index; works on arrays and slices.
    private static func readUInt32<Bytes: RandomAccessCollection>(_ bytes: Bytes, at index: Int) -> UInt32?
        where Bytes.Element == UInt8, Bytes.Index == Int {
        guard index >= bytes.startIndex, index + 4 <= bytes.endIndex else { return nil }
        return (UInt32(bytes[index]) << 24)
            | (UInt32(bytes[index + 1]) << 16)
            | (UInt32(bytes[index + 2]) << 8)
            | UInt32(bytes[index + 3])
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            UInt32(zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
        }
    }
}

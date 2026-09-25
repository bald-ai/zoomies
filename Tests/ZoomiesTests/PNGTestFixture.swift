import Foundation
import zlib

extension TestSupport {
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

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(ihdrChunk)
        png.append(iendChunk)
        return png
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func assembleChunk(type: String, payload: Data) -> Data {
        var chunk = Data(bigEndianBytes(UInt32(payload.count)))
        let contents = Data(type.utf8) + payload
        chunk.append(contents)
        let crc = contents.withUnsafeBytes { buffer in
            UInt32(zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
        }
        chunk.append(contentsOf: bigEndianBytes(crc))
        return chunk
    }
}

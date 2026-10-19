import Foundation

/// Edits only the demo's display/input chunks. Unknown chunks, including account
/// and network settings, survive byte for byte. No external GBX library is needed.
enum TrackManiaSettings {
    struct Chunk { var id: UInt32; var bytes: [UInt8] }
    static let limit = 1_048_576
    static let invalid = CrossedOverError.message("TrackMania's settings format was not recognized. The original file has been preserved.")

    static func word(_ bytes: [UInt8], _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= bytes.count - 4 else { throw invalid }
        return (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
    static func words(_ values: UInt32...) -> [UInt8] { values.flatMap { value in (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } } }
    static func chunks(_ bytes: [UInt8]) throws -> [Chunk] {
        var cursor = 0, result: [Chunk] = []
        while cursor < bytes.count {
            let id = try word(bytes, cursor); cursor += 4
            if id == 0xfacade01 { guard cursor == bytes.count else { throw invalid }; return result }
            guard try word(bytes, cursor) == 0x534b4950 else { throw invalid }
            let count = Int(try word(bytes, cursor + 4)); cursor += 8
            guard count <= bytes.count - cursor else { throw invalid }
            result.append(Chunk(id: id, bytes: Array(bytes[cursor..<cursor + count]))); cursor += count
        }
        throw invalid
    }
    static func encode(_ chunks: [Chunk]) -> [UInt8] {
        chunks.flatMap { words($0.id, 0x534b4950, UInt32($0.bytes.count)) + $0.bytes } + words(0xfacade01)
    }

    /// Original bounded LZO1X v0 decoder following the documented stream format:
    /// https://www.kernel.org/doc/Documentation/lzo.txt (no Linux/LZO code copied).
    static func decompress(_ input: [UInt8], count: Int) throws -> [UInt8] {
        guard count > 0, count <= limit, !input.isEmpty, input.count <= limit else { throw invalid }
        var cursor = 0, output: [UInt8] = [], state = 0
        output.reserveCapacity(count)
        func byte() throws -> Int {
            guard cursor < input.count else { throw invalid }
            defer { cursor += 1 }; return Int(input[cursor])
        }
        func length(_ value: Int, mask: Int) throws -> Int {
            if value != 0 { return value }
            var n = mask
            while true {
                let b = try byte(); n += b == 0 ? 255 : b
                guard n <= count else { throw invalid }
                if b != 0 { return n }
            }
        }
        func literals(_ n: Int) throws {
            guard n >= 0, n <= input.count - cursor, n <= count - output.count else { throw invalid }
            output.append(contentsOf: input[cursor..<cursor + n]); cursor += n
        }
        func match(distance: Int, length: Int) throws {
            guard distance > 0, distance <= output.count, length <= count - output.count else { throw invalid }
            for _ in 0..<length { output.append(output[output.count - distance]) }
        }
        if input[0] > 17 {
            let n = try byte() - 17; try literals(n); state = min(n, 4)
        }
        while true {
            let op = try byte()
            var n: Int, distance: Int, next: Int
            if op < 16 {
                if state == 0 {
                    n = try length(op, mask: 15) + 3; try literals(n); state = 4; continue
                }
                n = state == 4 ? 3 : 2
                distance = try (byte() << 2) + (op >> 2) + (state == 4 ? 2049 : 1)
                next = op & 3
            } else if op < 32 {
                n = try length(op & 7, mask: 7) + 2
                let lo = try byte(), hi = try byte(), operand = lo | hi << 8
                distance = 16384 + ((op & 8) << 11) + (operand >> 2); next = operand & 3
                if distance == 16384 {
                    guard n == 3, next == 0, cursor == input.count, output.count == count else { throw invalid }
                    return output
                }
            } else if op < 64 {
                n = try length(op & 31, mask: 31) + 2
                let lo = try byte(), hi = try byte(), operand = lo | hi << 8
                distance = (operand >> 2) + 1; next = operand & 3
            } else {
                n = (op >> 5) + 1
                distance = try (byte() << 3) + ((op >> 2) & 7) + 1; next = op & 3
            }
            try match(distance: distance, length: n); try literals(next); state = next
        }
    }

    static func windowed(_ data: Data, performance: Bool = false) throws -> Data {
        let b = Array(data)
        guard b.count >= 25, b.count <= limit, Array(b[0..<7]) == [71, 66, 88, 6, 0, 66, 85],
              b[8] == 82, try word(b, 9) == 0x0b005000, try word(b, 13) == 0,
              try word(b, 17) == 1, try word(b, 21) == 0 else { throw invalid }
        let body: [UInt8]
        if b[7] == 67 {
            let count = Int(try word(b, 25)), packed = Int(try word(b, 29))
            guard packed == b.count - 33 else { throw invalid }
            body = try decompress(Array(b[33...]), count: count)
        } else {
            guard b[7] == 85 else { throw invalid }; body = Array(b[25...])
        }
        var root = try chunks(body), found = false
        for i in root.indices {
            if root[i].id == 0x0b005020 {
                guard root[i].bytes.count >= 4 else { throw invalid }
                var display = try chunks(Array(root[i].bytes.dropFirst(4)))
                for j in display.indices where display[j].id == 0x0b013001 {
                    guard display[j].bytes.count == 32, !found else { throw invalid }
                    // TMF stores exclusive fullscreen in the final word. Keep
                    // its own window/client coordinate calculations in control.
                    display[j].bytes.replaceSubrange(28..<32, with: words(0)); found = true
                }
                root[i].bytes = Array(root[i].bytes.prefix(4)) + encode(display)
            }
            if root[i].id == 0x0b005045 {
                guard root[i].bytes.count == 16 else { throw invalid }
                // InputsCaptureKeyboard. macOS keeps Command-Tab/Command-M.
                root[i].bytes.replaceSubrange(12..<16, with: words(0))
            }
            if performance && root[i].id == 0x0b005034 {
                guard root[i].bytes.count == 28 else { throw invalid }
                // Apply the demo preset once. Users can subsequently change
                // car/ghost/detail preferences without each launch resetting them.
                let quality = min(try word(root[i].bytes, 0), 1)
                root[i].bytes.replaceSubrange(0..<4, with: words(quality))
                root[i].bytes.replaceSubrange(16..<20, with: words(0)) // TmMaxOpponents
                root[i].bytes.replaceSubrange(24..<28, with: words(0)) // TmBackgroundQuality
            }
        }
        guard found else { throw invalid }
        if encode(root) == body { return data }
        var header = Array(b.prefix(25)); header[7] = 85
        return Data(header + encode(root))
    }

    static func prepare(prefix: URL, performance: Bool = false) throws {
        let users = try FileSafety.containedURL("drive_c/users", in: prefix)
        for user in try FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil) {
            let relative = "drive_c/users/\(user.lastPathComponent)/Documents/TrackMania/Config/Default.SystemConfig.Gbx"
            let file = try FileSafety.containedURL(relative, in: prefix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.size] as? Int ?? limit + 1) <= limit else { throw invalid }
            let marker = try FileSafety.containedURL(relative + ".crossedover-performance-v1", in: prefix)
            let applyPreset = performance && !FileManager.default.fileExists(atPath: marker.path)
            let original = try Data(contentsOf: file), updated = try windowed(original, performance: applyPreset)
            if updated != original {
                let backup = file.deletingLastPathComponent().appendingPathComponent("Default.SystemConfig.before-crossedover-windowing.Gbx")
                if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: .withoutOverwriting) }
                try updated.write(to: file, options: .atomic)
            }
            if applyPreset { try Data("TrackMania demo preset v1\n".utf8).write(to: marker, options: .atomic) }
        }
    }
}

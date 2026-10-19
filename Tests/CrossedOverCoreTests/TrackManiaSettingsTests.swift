import Foundation
import Testing
@testable import CrossedOverCore

struct TrackManiaSettingsTests {
    @Test func observerAcceptsRuntimeStartupDiagnosticsWithoutAcceptingGarbage() {
        let output = "msync: up and running.\n[rosettax87] cache reset\n[{\"pid\":42,\"executable\":\"TmForever.exe\"}]\r\n"
        #expect(SupervisorEngine.decodeObservation(output)?.first?.executable == "TmForever.exe")
        #expect(SupervisorEngine.decodeObservation("[rosettax87] cache reset\n") == nil)
    }
    let compressed = "R0JYBgBCVUNSAFAACwAAAAABAAAAAAAAAOQAAACDAAAAByBQAAtQSUtTrACgAAYBMAELUElLUyB4AQkFAADQAgAAAgAAAAF8ASkMAH0BCc0FEClcAOkBEM0DBIMCgD8c3QEIzAl9AiHMAmwBeQQi3QEczARsDHwCfA98APwBBAHeyvo0UACcFC6sAAACAQAAAAAAAAAAAAAAAAAAAAHeyvoRAAA="
    @Test func compressedSettingsPreserveAllOtherChunksAndAreIdempotent() throws {
        let original = Data(base64Encoded: compressed)!, bytes = Array(original)
        let body = try TrackManiaSettings.decompress(Array(bytes[33...]), count: Int(TrackManiaSettings.word(bytes, 25)))
        let before = try TrackManiaSettings.chunks(body)
        let updated = try TrackManiaSettings.windowed(original)
        #expect(updated[7] == 85)
        let after = try TrackManiaSettings.chunks(Array(updated.dropFirst(25)))
        #expect(before.map(\.id) == after.map(\.id))
        for (old, new) in zip(before, after) {
            if old.id == 0x0b005020 {
                let a = try TrackManiaSettings.chunks(Array(old.bytes.dropFirst(4)))
                let b = try TrackManiaSettings.chunks(Array(new.bytes.dropFirst(4)))
                for (x, y) in zip(a, b) {
                    if x.id == 0x0b013001 {
                        #expect(x.bytes.prefix(28) == y.bytes.prefix(28))
                        #expect(try TrackManiaSettings.word(x.bytes, 28) == 1)
                        #expect(try TrackManiaSettings.word(y.bytes, 28) == 0)
                    } else { #expect(x.bytes == y.bytes) }
                }
            } else { #expect(old.bytes == new.bytes) }
        }
        #expect(try TrackManiaSettings.windowed(updated) == updated)
    }
    @Test func malformedLengthsReferencesAndTruncationAreRejected() throws {
        let original = Data(base64Encoded: compressed)!
        for length in 0..<original.count {
            #expect(throws: (any Error).self) { try TrackManiaSettings.windowed(original.prefix(length)) }
        }
        #expect(throws: (any Error).self) { try TrackManiaSettings.decompress([64, 255, 17, 0, 0], count: 32) }
        #expect(throws: (any Error).self) { try TrackManiaSettings.decompress([18, 65, 17, 0, 0, 0], count: 1) }
        #expect(throws: (any Error).self) { try TrackManiaSettings.decompress([18, 65, 17, 0, 0], count: TrackManiaSettings.limit + 1) }
    }
    @Test func keyboardCaptureIsReleasedAndTheOriginalBackupSurvivesRepeatedPreparation() throws {
        let compressedBytes = Array(Data(base64Encoded: compressed)!)
        let body = try TrackManiaSettings.decompress(Array(compressedBytes[33...]), count: Int(TrackManiaSettings.word(compressedBytes, 25)))
        var chunks = try TrackManiaSettings.chunks(body)
        chunks.append(.init(id: 0x0b005045, bytes: TrackManiaSettings.words(1, 0, 1, 1)))
        chunks.append(.init(id: 0x0b005fff, bytes: [9, 8, 7, 6, 5]))
        var header = Array(compressedBytes.prefix(25)); header[7] = 85
        let original = Data(header + TrackManiaSettings.encode(chunks))
        let prefix = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: prefix) }
        let folder = prefix.appendingPathComponent("drive_c/users/demo/Documents/TrackMania/Config")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Default.SystemConfig.Gbx")
        try original.write(to: file)
        try TrackManiaSettings.prepare(prefix: prefix)
        let updated = try Data(contentsOf: file)
        let result = try TrackManiaSettings.chunks(Array(updated.dropFirst(25)))
        #expect(result.first { $0.id == 0x0b005045 }?.bytes == TrackManiaSettings.words(1, 0, 1, 0))
        #expect(result.last?.bytes == [9, 8, 7, 6, 5])
        let backup = folder.appendingPathComponent("Default.SystemConfig.before-crossedover-windowing.Gbx")
        #expect(try Data(contentsOf: backup) == original)
        try TrackManiaSettings.prepare(prefix: prefix)
        #expect(try Data(contentsOf: file) == updated)
        #expect(try Data(contentsOf: backup) == original)
    }
    @Test func overlappingAndLongDistanceMatchesDecodeCorrectly() throws {
        #expect(try TrackManiaSettings.decompress([18, 65, 224, 0, 17, 0, 0], count: 9) == Array(repeating: 65, count: 9))
        for distance in [2050, 16385, 32769] {
            let prefix = (0..<distance).map { UInt8(truncatingIfNeeded: $0) }
            var input: [UInt8] = [0]
            var extended = distance - 18
            while extended > 255 { input.append(0); extended -= 255 }
            input.append(UInt8(extended)); input += prefix
            if distance == 2050 { input += [4, 0] }
            else {
                let operand = (distance - (distance == 16385 ? 16384 : 32768)) << 2
                input += [distance == 16385 ? 17 : 25, UInt8(operand & 255), UInt8(operand >> 8)]
            }
            input += [17, 0, 0]
            #expect(try TrackManiaSettings.decompress(input, count: distance + 3) == prefix + Array(prefix.prefix(3)))
        }
    }
    @Test func demoPresetPreservesUnknownFieldsAndRespectsLaterUserChanges() throws {
        let decoded = try TrackManiaSettings.windowed(Data(base64Encoded: compressed)!)
        var chunks = try TrackManiaSettings.chunks(Array(decoded.dropFirst(25)))
        let index = try #require(chunks.firstIndex { $0.id == 0x0b005034 })
        chunks[index].bytes = TrackManiaSettings.words(2, 22, 33, 1, 16, 44, 2)
        let original = Data(decoded.prefix(25)) + Data(TrackManiaSettings.encode(chunks))
        let updated = try TrackManiaSettings.windowed(original, performance: true)
        let result = try TrackManiaSettings.chunks(Array(updated.dropFirst(25)))
        #expect(result[index].bytes == TrackManiaSettings.words(1, 22, 33, 1, 0, 44, 0))
        let prefix = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: prefix) }
        let file = prefix.appendingPathComponent("drive_c/users/demo/Documents/TrackMania/Config/Default.SystemConfig.Gbx")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: file)
        try TrackManiaSettings.prepare(prefix: prefix, performance: true)
        #expect(try Data(contentsOf: file) == updated)
        try original.write(to: file) // Later choices made in the game's settings.
        try TrackManiaSettings.prepare(prefix: prefix, performance: true)
        #expect(try Data(contentsOf: file) == original)
    }
}

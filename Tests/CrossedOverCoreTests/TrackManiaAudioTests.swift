import Foundation
import Testing
@testable import CrossedOverCore

struct TrackManiaAudioTests {
    @Test func replacementPreservesEverySteamVersionAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let relative = "drive_c/Games/TrackMania/OpenAL32.dll"
        let target = root.appendingPathComponent(relative), source = root.appendingPathComponent("replacement.dll")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let replacement = Data("verified replacement".utf8)
        try replacement.write(to: source)
        let hash = try FileSafety.sha256(source)
        for original in [Data("original Steam library".utf8), Data("Steam repaired library v2".utf8)] {
            try original.write(to: target)
            let before = try FileSafety.sha256(target)
            try TrackManiaAudio.install(source: source, hash: hash, relativeDestination: relative, prefix: root)
            #expect(try Data(contentsOf: target) == replacement)
            let backup = root.appendingPathComponent("drive_c/crossedover/backups/trackmania-audio/\(before).dll")
            #expect(try Data(contentsOf: backup) == original)
            try TrackManiaAudio.install(source: source, hash: hash, relativeDestination: relative, prefix: root)
            #expect(try Data(contentsOf: backup) == original)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("drive_c/crossedover/backups/trackmania-audio").path).count == 2)
    }
    @Test func tamperedReplacementCannotChangeTheGameOrCreateABackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("replacement.dll"), target = root.appendingPathComponent("original.dll")
        try Data("replacement".utf8).write(to: source)
        let expected = try FileSafety.sha256(source)
        try Data("tampered".utf8).write(to: source)
        let original = Data("game library".utf8); try original.write(to: target)
        #expect(throws: (any Error).self) { try TrackManiaAudio.install(source: source, hash: expected, relativeDestination: "original.dll", prefix: root) }
        #expect(try Data(contentsOf: target) == original)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("drive_c/crossedover/backups").path))
    }
}

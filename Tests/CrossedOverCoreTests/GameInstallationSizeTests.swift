import Foundation
import Testing
@testable import CrossedOverCore

struct GameInstallationSizeTests {
    @Test func countsNestedAndHiddenFilesWithoutFollowingLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("crossedover-size-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = root.appendingPathComponent("game")
        try FileManager.default.createDirectory(at: game.appendingPathComponent("data"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 11).write(to: game.appendingPathComponent("game.exe"))
        try Data(repeating: 2, count: 23).write(to: game.appendingPathComponent("data/level.bin"))
        try Data(repeating: 3, count: 7).write(to: game.appendingPathComponent(".manifest"))
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 512).write(to: outside.appendingPathComponent("unrelated.bin"))
        try FileManager.default.createSymbolicLink(at: game.appendingPathComponent("linked-folder"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: game.appendingPathComponent("linked-file"), withDestinationURL: outside.appendingPathComponent("unrelated.bin"))
        try FileManager.default.createSymbolicLink(at: game.appendingPathComponent("loop"), withDestinationURL: game)
        let cache = GameInstallationSize()
        #expect(cache.size(in: game) == 41)
        #expect(cache.size(in: root.appendingPathComponent("missing")) == nil)
        #expect(cache.size(in: game.appendingPathComponent("game.exe")) == nil)
        #expect(cache.size(in: game.appendingPathComponent("linked-folder")) == nil)
    }

    @Test func cachesBackgroundRefreshesButRecountsOnRequestAndAfterExpiry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("crossedover-size-cache-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("level.bin")
        try Data(repeating: 1, count: 100).write(to: file)
        let cache = GameInstallationSize()
        #expect(cache.size(in: root, now: 0) == 100)
        try Data(repeating: 2, count: 200).write(to: file)
        #expect(cache.size(in: root, now: 8) == 100)
        #expect(cache.size(in: root, refresh: true, now: 9) == 200)
        try Data(repeating: 3, count: 300).write(to: file)
        #expect(cache.size(in: root, now: 10) == 200)
        #expect(cache.size(in: root, now: 310) == 300)
    }
}

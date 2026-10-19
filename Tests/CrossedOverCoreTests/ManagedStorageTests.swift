import Foundation
import Testing
@testable import CrossedOverCore

struct ManagedStorageTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("crossedover-removal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func removalRejectsCustomRootsAndLinksOutsideOwnedStorage() throws {
        let base = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let owned = base.appendingPathComponent("CrossedOver"), other = base.appendingPathComponent("OtherApp")
        for directory in [owned, other] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        #expect(try ManagedStorage.dataRoot(owned, expected: owned).path == owned.path)
        #expect(throws: (any Error).self) { try ManagedStorage.dataRoot(other, expected: owned) }
        let linked = base.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: owned)
        #expect(throws: (any Error).self) { try ManagedStorage.dataRoot(linked, expected: linked) }
        try FileManager.default.createSymbolicLink(at: owned.appendingPathComponent("Backups"), withDestinationURL: other)
        #expect(throws: (any Error).self) { try ManagedStorage.backups(in: owned, expected: owned) }
        #expect(FileManager.default.fileExists(atPath: other.path))
        try FileManager.default.removeItem(at: owned.appendingPathComponent("Backups"))
        let games = owned.appendingPathComponent("Environments")
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: owned.appendingPathComponent("Backups"), withDestinationURL: games)
        #expect(throws: (any Error).self) { try ManagedStorage.backups(in: owned, expected: owned) }
        #expect(FileManager.default.fileExists(atPath: games.path))
    }
    @Test func removalRequiresThePackagedApplication() throws {
        let base = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let app = base.appendingPathComponent("crossedover.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        #expect(try ManagedStorage.application(app, identifier: "org.crossedover.CrossedOver").path == app.path)
        #expect(throws: (any Error).self) { try ManagedStorage.application(app, identifier: "other.app") }
        #expect(throws: (any Error).self) { try ManagedStorage.application(base, identifier: "org.crossedover.CrossedOver") }
    }
    @Test func gamesFolderUsesManagedSteamAndRejectsEscapingLibraries() throws {
        let base = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let steam = base.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        try FileManager.default.createDirectory(at: steam, withIntermediateDirectories: true)
        try Data().write(to: steam.appendingPathComponent("steam.exe"))
        let actual = try SteamService.gamesFolder(prefix: base).path
        let pointer = try #require(realpath(base.path, nil))
        let canonicalRoot = String(cString: pointer); free(pointer)
        let expected = canonicalRoot + "/drive_c/Program Files (x86)/Steam/steamapps/common"
        #expect(actual == expected)
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: steam.appendingPathComponent("steamapps"), withDestinationURL: FileManager.default.temporaryDirectory)
        #expect(throws: (any Error).self) { try SteamService.gamesFolder(prefix: base) }
    }
}

import Foundation
import Testing
@testable import CrossedOverCore

struct GameFilesTests {
    @Test func documentsFindsTheWineUserAndRejectsExternalLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("crossedover-mods-" + UUID().uuidString)
        let documents = root.appendingPathComponent("drive_c/users/player/Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try GameFiles.documents(prefix: root, userName: "player").lastPathComponent == "Documents")
        #expect(try GameFiles.documents(prefix: root, userName: "missing").lastPathComponent == "Documents")
        try FileManager.default.removeItem(at: documents)
        try FileManager.default.createSymbolicLink(at: documents, withDestinationURL: FileManager.default.homeDirectoryForCurrentUser)
        #expect(throws: (any Error).self) { try GameFiles.documents(prefix: root, userName: "player") }
    }
    @Test func missingDocumentsAndTraversalDoNotCreateFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("crossedover-mods-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) { try GameFiles.documents(prefix: root, userName: "player") }
        #expect(throws: (any Error).self) { try GameFiles.documents(prefix: root, userName: "../../escape") }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

import Foundation
import Testing
@testable import CrossedOverCore

struct CoreTests {
    func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CrossedOver-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func vdfSupportsEscapesCommentsAndUnknownFields() throws {
        let value = try VDF.parse("""
        // Steam updates these files in place.
        "AppState" { "appid" "11020" "installdir" "Track\\\\Mania" "unknown" { "x" "y" } }
        "path" "C:\\\\Program Files (x86)\\\\Steam"
        "quote" "A \\"game\\""
        """)
        #expect(value["appstate"]?.object?["appid"]?.string == "11020")
        #expect(value["path"]?.string == "C:\\Program Files (x86)\\Steam")
        #expect(value["quote"]?.string == "A \"game\"")
    }
    @Test func vdfRejectsIncompleteAndDeepDocuments() {
        for text in ["\"AppState\" { \"name\"", "\"x\" \"unterminated", "}", String(repeating: "x {", count: 40)] {
            #expect(throws: (any Error).self) { try VDF.parse(text) }
        }
    }
    @Test func pathsRejectTraversalAndEscapingSymlinks() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        for path in ["../outside", "/etc/passwd", "a/../../outside", "a\\b", ""] {
            #expect(throws: (any Error).self) { try FileSafety.containedURL(path, in: root) }
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
        #expect(throws: (any Error).self) { try FileSafety.containedURL("escape/file", in: root) }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("chain").path, withDestinationPath: "escape/not-created")
        #expect(throws: (any Error).self) { try FileSafety.containedURL("chain/file", in: root) }
        #expect(try FileSafety.containedURL("safe/file", in: root).path.hasSuffix(root.lastPathComponent + "/safe/file"))
    }
    @Test func hashesVerifyRealBytes() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("data"); try Data("abc".utf8).write(to: file)
        try FileSafety.verify(file, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(throws: (any Error).self) { try FileSafety.verify(file, sha256: String(repeating: "0", count: 64)) }
    }
    @Test func redactionRemovesSecretsAndUsernames() {
        let output = Redaction.apply("hello /Users/example/file\nCookie: abc def\npassword=123\nsteamid=7654321\nordinary message", home: "/Users/example")
        #expect(!output.contains("123")); #expect(!output.contains("abc def")); #expect(!output.contains("7654321"))
        #expect(output.contains("~/file")); #expect(output.contains("ordinary message"))
    }
    @Test func discoveryPreservesWindowsPathsAndExcludesIncompleteInstalls() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let environment = ManagedEnvironment(runtimeID: "test")
        let steam = root.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps")
        try FileManager.default.createDirectory(at: steam.appendingPathComponent("common/Example"), withIntermediateDirectories: true)
        let content = "\"AppState\" { \"appid\" \"11020\" \"name\" \"Example Game\" \"installdir\" \"Example\" \"StateFlags\" \"4\" \"SizeOnDisk\" \"12345\" }"
        try content.write(to: steam.appendingPathComponent("appmanifest_11020.acf"), atomically: true, encoding: .utf8)
        let discovery = SteamDiscovery()
        let games = try discovery.discover(environment: environment, prefix: root)
        #expect(games.count == 1); #expect(games[0].name == "Example Game"); #expect(games[0].sizeBytes == 12345)
        try content.replacingOccurrences(of: "\"StateFlags\" \"4\"", with: "\"StateFlags\" \"2\"").write(to: steam.appendingPathComponent("appmanifest_11020.acf"), atomically: true, encoding: .utf8)
        #expect(try discovery.discover(environment: environment, prefix: root).isEmpty)
        try "\"AppState\" {".write(to: steam.appendingPathComponent("appmanifest_11020.acf"), atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try discovery.discover(environment: environment, prefix: root) }
    }
    @Test func databaseReplacesOnlyTheSpecifiedEnvironment() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(url: root.appendingPathComponent("test.sqlite"))
        let a = UUID(), b = UUID()
        let gameA = GameInstallation(appID: "1", environmentID: a, name: "A", directory: "a", sizeBytes: 1)
        let gameB = GameInstallation(appID: "2", environmentID: b, name: "B", directory: "b", sizeBytes: 1)
        try store.replaceGames([gameA], environmentID: a); try store.replaceGames([gameB], environmentID: b)
        try store.replaceGames([], environmentID: a)
        #expect(try store.all(GameInstallation.self, kind: "game") == [gameB])
        let operation = OperationRecord(kind: "setup", state: "interrupted", detail: "retry")
        try store.put(operation, kind: "operation", id: operation.id.uuidString)
        #expect(try store.all(OperationRecord.self, kind: "operation").first?.state == "interrupted")
    }
    @Test func environmentLocksSerializeDifferentOwners() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appendingPathComponent("prefix")
        let lock = try EnvironmentLock(prefix: prefix)
        #expect(throws: (any Error).self) { try EnvironmentLock(prefix: prefix) }
        withExtendedLifetime(lock) {}
    }
    @Test func appIDsDoNotAcceptCommandsOrMalformedValues() {
        for id in ["", "0", "../1", "1;touch /tmp/a", "$(id)", "-1", "4294967296"] { #expect(!SteamDiscovery.validAppID(id)) }
        #expect(SteamDiscovery.validAppID("1985690"))
    }
    @Test func structuredArgumentsDoNotInvokeAShell() async throws {
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["$(id); `whoami`", "a b"])
        #expect(result.status == 0); #expect(result.output == "$(id); `whoami` a b\n")
    }
    @Test func processTimeoutReturnsAnActionableFailure() async {
        await #expect(throws: (any Error).self) { try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.15) }
    }
    @Test func tarExtractionRejectsTraversalAndEscapingLinks() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        for (index, tuple) in [("../escape", "0", ""), ("/tmp/escape", "0", ""), ("link", "2", "../../tmp")].enumerated() {
            let archive = root.appendingPathComponent("\(index).tar")
            try tar(name: tuple.0, type: tuple.1, link: tuple.2).write(to: archive)
            #expect(throws: (any Error).self) { try ArchiveExtractor.extract(archive, to: root.appendingPathComponent("output-\(index)")) }
        }
        let valid = root.appendingPathComponent("valid.tar")
        try tar(name: "file", type: "0", link: "").write(to: valid)
        let output = root.appendingPathComponent("valid")
        try ArchiveExtractor.extract(valid, to: output)
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("file").path))
    }
    private func tar(name: String, type: String, link: String) -> Data {
        var bytes = [UInt8](repeating: 0, count: 512)
        func put(_ string: String, _ offset: Int) { for (i, b) in string.utf8.enumerated() { bytes[offset + i] = b } }
        put(name, 0); put("0000644\0", 100); put("0000000\0", 108); put("0000000\0", 116)
        put("00000000000\0", 124); put("00000000000\0", 136); put("        ", 148)
        put(type, 156); put(link, 157); put("ustar\0", 257); put("00", 263)
        let checksum = bytes.reduce(0) { $0 + Int($1) }; put(String(format: "%06o\0 ", checksum), 148)
        return Data(bytes + [UInt8](repeating: 0, count: 1024))
    }
}

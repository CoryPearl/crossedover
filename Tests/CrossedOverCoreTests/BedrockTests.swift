import Foundation
import Testing
import Darwin
@testable import CrossedOverCore

struct BedrockTests {
    func fixture(script: String = "echo '{\"state\":\"new\",\"title\":\"Minecraft\"}'\n") throws -> (URL, URL, BedrockBackend) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("crossedover-bedrock-test-" + UUID().uuidString)
        let backend = root.appendingPathComponent("backend"), data = root.appendingPathComponent("data")
        let required = ["worker/BedrockWorker", "standalone_helper", "runtime/wine/bin/wine", "runtime/wine/bin/wineserver",
                        "runtime/wine/build-manifest.json", "runtime/dxmt/manifest.json", "runtime/dxmt/x86_64-unix/winemetal.so",
                        "scripts/standalone.py", "scripts/standalone-setup.py", "scripts/standalone-gameinput.py", "scripts/winrt.reg"]
        var hashes: [String: String] = [:]
        for name in required {
            let path = backend.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((name == "worker/BedrockWorker" ? "#!/bin/sh\n" + script : "fixture only").utf8).write(to: path)
            if name == "worker/BedrockWorker" { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path) }
            hashes[name] = try FileSafety.sha256(path)
        }
        let manifest: [String: Any] = ["schemaVersion": 1, "sourceRevision": BedrockBackend.sourceRevision,
                                     "downloadPolicy": "https-only", "minimumMacOS": 26, "previewOnly": true,
                                     "fileHashes": hashes, "symlinks": [String: String]()]
        try JSONSerialization.data(withJSONObject: manifest).write(to: backend.appendingPathComponent("backend.json"))
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        return (root, data, try BedrockBackend.load(at: backend))
    }

    @Test func backendRequiresVerifiedBytesAndExactInventory() throws {
        let (root, _, backend) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let unexpected = backend.directory.appendingPathComponent("unreviewed.py")
        try Data().write(to: unexpected)
        #expect(throws: (any Error).self) { try BedrockBackend.load(at: backend.directory) }
        try FileManager.default.removeItem(at: unexpected)
        try Data("changed helper".utf8).write(to: backend.directory.appendingPathComponent("standalone_helper"))
        #expect(throws: (any Error).self) { try BedrockBackend.load(at: backend.directory) }
    }

    @Test func backendAndDataSymlinksCannotEscapeTheirRoots() throws {
        let (root, data, backend) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = backend.directory.appendingPathComponent("standalone_helper")
        try FileManager.default.removeItem(at: helper)
        try FileManager.default.createSymbolicLink(at: helper, withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
        #expect(throws: (any Error).self) { try BedrockBackend.load(at: backend.directory) }
        try FileManager.default.createSymbolicLink(at: data.appendingPathComponent("Bedrock"), withDestinationURL: root)
        #expect(throws: (any Error).self) { try BedrockService.home(in: data) }
    }

    @Test func statusIsOfflineAndSessionEnvironmentIsIndependent() async throws {
        let (root, data, backend) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let env = try backend.environment(dataRoot: data)
        let canonicalData = realpath(data.path, nil)!
        defer { free(canonicalData) }
        #expect(env["BEDROCK_HOME"] == String(cString: canonicalData) + "/Bedrock")
        #expect(env["WINEPREFIX"] == nil && env["WINEDLLOVERRIDES"] == nil && env["DYLD_LIBRARY_PATH"] == nil)
        #expect(env["PYTHONPATH"] == nil && env["RUST_LOG"] == "off")
        let status = try await backend.status(dataRoot: data)
        #expect(status.phase == .new)
        #expect(!FileManager.default.fileExists(atPath: data.appendingPathComponent("Bedrock").path))
    }

    @Test func onlyReviewedStatusTextReachesTheUser() throws {
        let event = try BedrockEvent.decode(Data(#"{"state":"busy","title":"token=private-sentinel","detail":"https://secret.invalid/?code=private-sentinel","progress":0.4}"#.utf8))
        #expect(event.title == "Preparing Minecraft…")
        #expect(!event.detail.contains("private-sentinel"))
        #expect(event.progress == 0.4)
        let failure = try BedrockEvent.decode(Data(#"{"state":"error","title":"package_transport"}"#.utf8))
        #expect(failure.detail.contains("no secure download"))
        let connection = try BedrockEvent.decode(Data(#"{"state":"error","title":"package_connection"}"#.utf8))
        #expect(connection.detail.contains("sign-in is saved"))
        let license = try BedrockEvent.decode(Data(#"{"state":"error","title":"content_license"}"#.utf8))
        #expect(license.detail.contains("license"))
        let unknown = try BedrockEvent.decode(Data(#"{"state":"error","title":"private-sentinel","detail":"private-sentinel"}"#.utf8))
        #expect(!unknown.detail.contains("private-sentinel"))
        for line in [#"{"state":"completed","title":"x"}"#, #"{"state":"busy","title":"x","progress":2}"#, String(repeating: "x", count: 16_385)] {
            #expect(throws: (any Error).self) { try BedrockEvent.decode(Data(line.utf8)) }
        }
    }

    @Test func streamedProgressArrivesBeforeWorkerExitAndOverlapIsRejected() async throws {
        let script = "echo '{\"state\":\"busy\",\"title\":\"Downloading Minecraft\",\"progress\":0.3}'\nsleep 2\necho '{\"state\":\"ready\",\"title\":\"Ready\"}'\n"
        let (root, data, backend) = try fixture(script: script)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BedrockService(), started = Date()
        let events = try await service.events(backend: backend, dataRoot: data)
        var count = 0
        for try await event in events {
            count += 1
            if count == 1 {
                #expect(event.phase == .busy)
                #expect(Date().timeIntervalSince(started) < 1.5)
                await #expect(throws: (any Error).self) { try await service.events(backend: backend, dataRoot: data) }
            }
        }
        #expect(count == 2)
    }

    @Test func zeroExitWithoutTerminalStatusDoesNotMeanSuccess() async throws {
        let (root, data, backend) = try fixture(script: "echo '{\"state\":\"starting\",\"title\":\"Opening Minecraft\"}'\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BedrockService()
        let events = try await service.events(backend: backend, dataRoot: data)
        await #expect(throws: (any Error).self) { for try await _ in events {} }
    }

    @Test func cancellationStopsOnlyTheOwnedWorker() async throws {
        let script = "trap 'exit 0' TERM\necho '{\"state\":\"busy\",\"title\":\"Preparing Minecraft\"}'\nwhile :; do sleep 1; done\n"
        let (root, data, backend) = try fixture(script: script)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BedrockService()
        let events = try await service.events(backend: backend, dataRoot: data)
        await #expect(throws: CancellationError.self) {
            for try await _ in events { await service.cancel() }
        }
    }

    @Test func uninstallRefusesAnActiveBedrockLock() throws {
        let (root, data, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let lock = data.appendingPathComponent("Bedrock/logs/standalone/onboarding.lock")
        try FileManager.default.createDirectory(at: lock.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lock.path, O_CREAT | O_RDWR, 0o600)
        #expect(fd >= 0)
        defer { close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        #expect(throws: (any Error).self) { try BedrockService.requireStopped(dataRoot: data) }
        flock(fd, LOCK_UN)
        try BedrockService.requireStopped(dataRoot: data)
        do {
            let lease = try BedrockService.acquireIdleData(dataRoot: data)
            #expect(throws: (any Error).self) { try BedrockService.requireStopped(dataRoot: data) }
            withExtendedLifetime(lease) {}
        }
        try BedrockService.requireStopped(dataRoot: data)
    }
}

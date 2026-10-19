import Foundation
import Darwin

/// Bedrock uses a separate WineGDK backend and data directory. It never shares
/// Steam/Epic's Wine server, renderer, account, or launch supervisor.
public struct BedrockBackend: Sendable {
    public static let sourceRevision = "99fc9aa7d79b34aaee25a447b964e5d8235a2cec"
    public let directory: URL
    public var worker: URL { directory.appendingPathComponent("worker/BedrockWorker") }

    private struct Manifest: Decodable {
        var schemaVersion: Int
        var sourceRevision: String
        var downloadPolicy: String
        var minimumMacOS: Int
        var previewOnly: Bool
        var fileHashes: [String: String]
        var symlinks: [String: String]
    }

    /// Run off the UI actor: this verifies actual runtime bytes, not a marker.
    public static func load(at directory: URL) throws -> BedrockBackend {
        // Foundation normalizes /private/var back to /var on macOS, while its
        // directory enumerator returns /private/var. Use realpath consistently.
        guard let canonical = realpath(directory.path, nil) else {
            throw CrossedOverError.message("Minecraft's separate backend is not installed.")
        }
        let directory = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
        free(canonical)
        let file = try FileSafety.containedURL("backend.json", in: directory)
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4_000_000 else {
            throw CrossedOverError.message("Minecraft's backend manifest is invalid.")
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: file))
        guard manifest.schemaVersion == 1, manifest.sourceRevision == sourceRevision,
              manifest.downloadPolicy == "https-only", manifest.minimumMacOS == 26, manifest.previewOnly,
              !manifest.fileHashes.isEmpty, manifest.fileHashes.count <= 100_000 else {
            throw CrossedOverError.message("This Minecraft backend is incompatible. Use a matching crossedover preview build.")
        }
        let required = ["worker/BedrockWorker", "standalone_helper", "runtime/wine/bin/wine",
                        "runtime/wine/bin/wineserver", "runtime/wine/build-manifest.json",
                        "runtime/dxmt/manifest.json", "runtime/dxmt/x86_64-unix/winemetal.so",
                        "scripts/standalone.py", "scripts/standalone-setup.py", "scripts/standalone-gameinput.py", "scripts/winrt.reg"]
        for name in required {
            let path = try FileSafety.containedURL(name, in: directory)
            guard let resolved = realpath(path.path, nil) else {
                throw CrossedOverError.message("Minecraft's separate runtime is incomplete.")
            }
            let actual = String(cString: resolved); free(resolved)
            let relative = String(actual.dropFirst(directory.path.count + 1))
            guard FileManager.default.fileExists(atPath: path.path), manifest.fileHashes[relative] != nil else {
                throw CrossedOverError.message("Minecraft's separate runtime is incomplete. Reinstall the preview backend.")
            }
        }
        var files = Set<String>(), links: [String: String] = [:]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            throw CrossedOverError.message("Minecraft's backend could not be inspected.")
        }
        for case let path as URL in enumerator {
            let name = String(path.path.dropFirst(directory.path.count + 1))
            let values = try path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                _ = try FileSafety.containedURL(name, in: directory)
                links[name] = try FileManager.default.destinationOfSymbolicLink(atPath: path.path)
            } else if values.isRegularFile == true && name != "backend.json" { files.insert(name) }
            guard files.count + links.count <= 100_000 else { throw CrossedOverError.message("Minecraft's backend is unexpectedly large.") }
        }
        guard files == Set(manifest.fileHashes.keys), links == manifest.symlinks else {
            throw CrossedOverError.message("Minecraft's backend contents differ from its build inventory.")
        }
        // Check every inventoried file. Symlink targets must remain in the backend.
        for (name, hash) in manifest.fileHashes {
            let path = try FileSafety.containedURL(name, in: directory)
            guard try path.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw CrossedOverError.message("Minecraft's backend contains an invalid file.")
            }
            try FileSafety.verify(path, sha256: hash)
        }
        guard FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("worker/BedrockWorker").path) else {
            throw CrossedOverError.message("Minecraft's setup worker cannot run.")
        }
        return BedrockBackend(directory: directory)
    }

    public func environment(dataRoot: URL) throws -> [String: String] {
        let home = try BedrockService.home(in: dataRoot)
        // Do not inherit Wine overrides, tracing, Python import hooks, or auth
        // variables from the other launcher environment.
        var env = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                   "BEDROCK_HOME": home.path, "BEDROCK_BUNDLE": directory.path,
                   "XODUS_LOG": "off", "RUST_LOG": "off", "PYTHONUNBUFFERED": "1", "LC_ALL": "en_US.UTF-8"]
        if let temporary = ProcessInfo.processInfo.environment["TMPDIR"] { env["TMPDIR"] = temporary }
        return env
    }

    public func status(dataRoot: URL) async throws -> BedrockEvent {
        let result = try await ProcessRunner.run(worker, arguments: ["--status"], workingDirectory: directory,
                                                  environment: environment(dataRoot: dataRoot), timeout: 20)
        guard result.status == 0 else { throw CrossedOverError.message("Minecraft's setup worker could not check the installation.") }
        let lines = result.output.split(separator: "\n")
        guard lines.count == 1, let line = lines.first else { throw CrossedOverError.message("Minecraft returned an invalid installation status.") }
        let event = try BedrockEvent.decode(Data(line.utf8))
        guard event.phase == .new || event.phase == .ready else { throw CrossedOverError.message("Minecraft returned an unexpected installation status.") }
        return event
    }
}

public struct BedrockEvent: Sendable, Equatable {
    public enum Phase: String, Decodable, Sendable { case new, ready, busy, starting, playing, cancelled, error }
    public let phase: Phase
    public let title: String
    public let detail: String
    public let progress: Double?
    public var active: Bool { [.busy, .starting, .playing].contains(phase) }

    /// Arbitrary helper strings never enter the UI, journal, or diagnostics.
    /// Account responses and signed URLs are not a status-message protocol.
    public static func decode(_ data: Data) throws -> BedrockEvent {
        struct Wire: Decodable { var state: Phase; var title: String; var progress: Double? }
        guard data.count <= 16_384 else { throw CrossedOverError.message("Minecraft returned an oversized status message.") }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        if let progress = wire.progress, !progress.isFinite || !(0...1).contains(progress) {
            throw CrossedOverError.message("Minecraft returned invalid download progress.")
        }
        let title: String
        let detail: String
        switch wire.state {
        case .new: title = "Install Minecraft Bedrock"; detail = "Sign in with the Microsoft account that owns Minecraft for Windows."
        case .ready: title = "Minecraft is installed"; detail = "Choose Play to sign in and start your game."
        case .starting: title = "Opening Minecraft…"; detail = "Waiting for the game process."
        case .playing: title = "Minecraft is running"; detail = "Quit Minecraft to end the session."
        case .cancelled: title = "Minecraft stopped"; detail = "Your completed installation and worlds have been kept."
        case .error:
            title = "Minecraft needs attention"
            let errors = [
                "package_transport": "Microsoft supplied no secure download for this package. Installation stopped before downloading the game.",
                "package_connection": "Minecraft’s download server could not provide the game package. Your sign-in is saved; you can retry.",
                "content_license": "Microsoft could not verify a Minecraft for Windows license for this account. Check that you signed in with the account that owns it.",
                "keychain_access": "Allow access to your saved Microsoft sign-in in the macOS Keychain prompt, then retry.",
                "signin_cancelled": "Microsoft sign-in was closed. You can retry when you’re ready.",
                "account_timeout": "Microsoft sign-in took too long. Check your connection and retry.",
                "catalog_lookup": "Minecraft’s Windows catalog is unavailable. You can retry shortly.",
                "package_size": "Minecraft’s download size differs from Microsoft’s catalog. Installation stopped; you can retry shortly."
            ]
            detail = errors[wire.title] ?? "Setup or the game stopped. You can retry; existing worlds are kept. Microsoft sign-in and macOS permission prompts must be completed in their own windows."
        case .busy:
            let known = ["Signing you in", "Sign in to Microsoft", "Checking your Minecraft purchase", "Downloading Minecraft", "Preparing Minecraft", "Finishing setup", "Signing out"]
            title = known.contains(wire.title) ? wire.title : "Preparing Minecraft…"
            detail = wire.title == "Sign in to Microsoft" || wire.title == "Signing you in"
                ? "Complete Microsoft sign-in or Keychain access in its own window." : "You can cancel this session below."
        }
        return BedrockEvent(phase: wire.state, title: title, detail: detail, progress: wire.progress)
    }
}

public actor BedrockService {
    private var session: BedrockWorkerSession?
    public init() {}

    public nonisolated static func home(in dataRoot: URL) throws -> URL {
        try FileSafety.containedURL("Bedrock", in: dataRoot)
    }

    public nonisolated static func requireStopped(dataRoot: URL) throws {
        let root = try home(in: dataRoot)
        let lock = try FileSafety.containedURL("logs/standalone/onboarding.lock", in: root)
        guard FileManager.default.fileExists(atPath: lock.path) else { return }
        let held = try BedrockDataLock(file: lock)
        withExtendedLifetime(held) {}
    }

    public nonisolated static func acquireIdleData(dataRoot: URL) throws -> BedrockDataLock {
        let root = try home(in: dataRoot)
        let folder = try FileSafety.containedURL("logs/standalone", in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return try BedrockDataLock(file: FileSafety.containedURL("onboarding.lock", in: folder))
    }

    public func events(backend: BedrockBackend, dataRoot: URL, signOut: Bool = false) throws -> AsyncThrowingStream<BedrockEvent, Error> {
        guard session?.isRunning != true else { throw CrossedOverError.message("A Minecraft session is already open.") }
        let next = BedrockWorkerSession()
        let stream = try next.start(backend: backend, dataRoot: dataRoot, signOut: signOut)
        session = next
        return stream
    }

    public func cancel() { session?.cancel() }
    public func waitUntilStopped() async {
        while session?.isRunning == true { try? await Task.sleep(for: .milliseconds(100)) }
    }
}

public final class BedrockDataLock: @unchecked Sendable {
    private let descriptor: Int32
    fileprivate init(file: URL) throws {
        let fd = open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CrossedOverError.message("Minecraft's session status cannot be checked. Quit Minecraft before continuing.") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw CrossedOverError.message("Stop Minecraft's session before changing its files.")
        }
        descriptor = fd
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

private final class BedrockWorkerSession: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    var isRunning: Bool { lock.withLock { process.isRunning } }

    func cancel() {
        lock.withLock {
            cancelled = true
            // The patched worker handles TERM and unwinds only its owned helper,
            // setup process group, and dedicated Bedrock Wine prefix.
            if process.isRunning { process.terminate() }
        }
    }

    func start(backend: BedrockBackend, dataRoot: URL, signOut: Bool) throws -> AsyncThrowingStream<BedrockEvent, Error> {
        let pipe = Pipe()
        process.executableURL = backend.worker
        process.arguments = signOut ? ["--sign-out"] : []
        process.environment = try backend.environment(dataRoot: dataRoot)
        process.currentDirectoryURL = backend.directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            continuation.onTermination = { @Sendable [self] _ in cancel() }
            Task.detached(priority: .utility) { [self] in
                let reader = pipe.fileHandleForReading
                defer { try? reader.close() }
                do {
                    var pending = Data()
                    var finalPhase: BedrockEvent.Phase?
                    while true {
                        // read(upToCount:) can wait to fill its buffer on a pipe.
                        // availableData blocks only until the next available chunk.
                        let chunk = reader.availableData
                        if chunk.isEmpty { break }
                        pending.append(chunk)
                        while let newline = pending.firstIndex(of: 10) {
                            let line = Data(pending[..<newline])
                            pending.removeSubrange(...newline)
                            let event = try BedrockEvent.decode(line)
                            finalPhase = event.phase
                            continuation.yield(event)
                        }
                        guard pending.count <= 16_384 else { throw CrossedOverError.message("Minecraft returned an oversized status message.") }
                    }
                    process.waitUntilExit()
                    if lock.withLock({ cancelled }) { throw CancellationError() }
                    guard pending.isEmpty, let finalPhase,
                          [.ready, .cancelled, .error].contains(finalPhase),
                          process.terminationStatus == 0 || finalPhase == .error else {
                        throw CrossedOverError.message("Minecraft's session ended unexpectedly. Existing files were kept.")
                    }
                    continuation.finish()
                } catch {
                    cancel()
                    process.waitUntilExit()
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

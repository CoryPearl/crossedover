import Foundation

public struct SupervisorRequest: Codable, Sendable {
    public var version: Int = 1
    public var root: URL
    public var environmentID: UUID
    public var command: Command
    public var appID: String?
    public enum Command: String, Codable, Sendable {
        case openSteam, installGame, launchGame, uninstallGame, gameProperties, verifyGame, openDownloads, shutdown, forceStop, observe
        var requiresGameID: Bool { [.installGame, .launchGame, .uninstallGame, .gameProperties, .verifyGame].contains(self) }
    }
    public init(root: URL, environmentID: UUID, command: Command, appID: String? = nil) {
        self.root = root; self.environmentID = environmentID; self.command = command; self.appID = appID
    }
}

public struct SupervisorReply: Codable, Sendable {
    public var version: Int = 1
    public var success: Bool
    public var message: String
    public var processes: [ProcessObservation]?
    public init(success: Bool, message: String, processes: [ProcessObservation]? = nil) {
        self.success = success; self.message = message; self.processes = processes
    }
}

public enum SupervisorEngine {
    static func decodeObservation(_ output: String) -> [ProcessObservation]? {
        // Wine's MSync/x87 startup diagnostics share the child's output stream.
        // The observer emits exactly one JSON array on its own line.
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.first == "[", let data = String(line).data(using: .utf8),
                  let processes = try? JSONDecoder().decode([ProcessObservation].self, from: data) else { continue }
            return processes
        }
        return nil
    }
    public static func execute(_ request: SupervisorRequest) async throws -> SupervisorReply {
        guard request.version == 1 else { throw CrossedOverError.message("Supervisor protocol version mismatch.") }
        let paths = AppPaths(root: request.root)
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        guard let environment = try store.all(ManagedEnvironment.self, kind: "environment").first(where: { $0.id == request.environmentID }) else { throw CrossedOverError.message("Environment not found.") }
        let runtime = try await RuntimeManager(paths: paths).resolve(environment.runtimeID)
        let prefix = paths.prefix(environment)
        let variables = WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: environment.profile)
        let lock = try EnvironmentLock(prefix: prefix); defer { withExtendedLifetime(lock) {} }
        if request.command == .forceStop {
            _ = try await ProcessRunner.run(runtime.wineserver, arguments: ["-k"], environment: variables, timeout: 15)
            // -k returns nonzero when the server has already exited. A stopped
            // environment is a successful outcome, including repeated requests.
            let result = try await ProcessRunner.run(runtime.wineserver, arguments: ["-w"], environment: variables, timeout: 15)
            guard result.status == 0 else { throw CrossedOverError.message("Could not confirm environment shutdown: \(Redaction.apply(result.output).suffix(800))") }
            return SupervisorReply(success: true, message: "This Windows environment is stopped.")
        }
        if request.command == .observe {
            guard let observer = runtime.manifest.observerRelativePath else { return SupervisorReply(success: true, message: "This runtime does not provide process observation.", processes: nil) }
            // The helper must live inside the prefix because broad Z: access is disabled.
            let source = try FileSafety.containedURL(observer, in: runtime.root)
            let destination = try FileSafety.containedURL("drive_c/crossedover/process-observer.exe", in: prefix)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: source, to: destination) }
            let result = try await ProcessRunner.run(runtime.wine, arguments: [destination.path], workingDirectory: prefix.appendingPathComponent("drive_c"), environment: variables, timeout: 15)
            guard result.status == 0, let processes = decodeObservation(result.output) else { throw CrossedOverError.message("Windows process observation failed.") }
            return SupervisorReply(success: true, message: "Observed Windows processes.", processes: processes)
        }
        guard environment.state == "ready" || request.command == .shutdown else {
            throw CrossedOverError.message("Repair the Windows environment in Settings → Advanced before opening Steam.")
        }
        _ = try SteamService.steamExecutable(prefix: prefix)
        if request.command.requiresGameID {
            guard let appID = request.appID, SteamDiscovery.validAppID(appID) else { throw CrossedOverError.message("Invalid Steam App ID.") }
        }
        if [.uninstallGame, .verifyGame].contains(request.command) {
            guard let game = try SteamDiscovery().discover(environment: environment, prefix: prefix).first(where: { $0.appID == request.appID }) else { throw CrossedOverError.message("This game is no longer installed. Refresh your library.") }
            let recipe = try ResourceCatalog.recipes().first(where: { $0.appID == game.appID })
            let executables = try GameProcessDetection.executableNames(for: game, recipe: recipe)
            guard !executables.isEmpty, let observer = runtime.manifest.observerRelativePath else { throw CrossedOverError.message("Could not confirm this game is closed. Use Windows Steam to manage its files.") }
            let source = try FileSafety.containedURL(observer, in: runtime.root)
            let destination = try FileSafety.containedURL("drive_c/crossedover/process-observer.exe", in: prefix)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: source, to: destination) }
            let observation = try await ProcessRunner.run(runtime.wine, arguments: [destination.path], environment: variables, timeout: 15)
            guard observation.status == 0, let processes = decodeObservation(observation.output) else { throw CrossedOverError.message("Could not confirm the game is closed. Close it and retry.") }
            guard !processes.contains(where: { executables.contains($0.executable.lowercased()) }) else { throw CrossedOverError.message("Close \(game.name) before uninstalling or verifying its files.") }
        }
        if request.command == .launchGame, let appID = request.appID, let registry = GameWindowingPolicy.registry(for: appID) {
            // Never rewrite settings beneath an already running game.
            let recipe = try ResourceCatalog.recipes().first { $0.appID == appID }
            let name = recipe?.name ?? "This game"
            guard let observer = runtime.manifest.observerRelativePath else { throw CrossedOverError.message("Update the runtime before launching \(name).") }
            let source = try FileSafety.containedURL(observer, in: runtime.root)
            let destination = try FileSafety.containedURL("drive_c/crossedover/process-observer.exe", in: prefix)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: source, to: destination) }
            let observation = try await ProcessRunner.run(runtime.wine, arguments: [destination.path], environment: variables, timeout: 15)
            guard observation.status == 0, let processes = decodeObservation(observation.output) else { throw CrossedOverError.message("Could not check whether \(name) is already running.") }
            let executables = recipe?.executableNames.map { $0.lowercased() } ?? []
            guard !executables.isEmpty, !processes.contains(where: { executables.contains($0.executable.lowercased()) }) else { throw CrossedOverError.message("\(name) is already running or cannot be tracked.") }
            if appID == "11020" {
                try TrackManiaSettings.prepare(prefix: prefix, performance: environment.profile == .performance)
                if let game = try SteamDiscovery().discover(environment: environment, prefix: prefix).first(where: { $0.appID == appID }) {
                    try TrackManiaAudio.prepare(runtime: runtime, game: game, prefix: prefix)
                }
            }
            if appID == "730" { try CS2WindowSettings.prepare(prefix: prefix) }
            let filename = appID == "11020" ? "trackmania-windowing.reg" : "cs2-windowing.reg"
            let policy = prefix.appendingPathComponent("drive_c/crossedover/" + filename)
            var registryData = Data([0xff, 0xfe]); registryData.append(registry.data(using: .utf16LittleEndian)!)
            try registryData.write(to: policy, options: .atomic)
            let configured = try await ProcessRunner.run(runtime.wine, arguments: ["regedit", "/S", "C:\\crossedover\\" + filename], environment: variables, timeout: 15)
            guard configured.status == 0 else { throw CrossedOverError.message("Could not prepare \(name)'s window controls.") }
        }
        // A detached worker drains output into a bounded log for the whole session.
        let file = paths.logs.appendingPathComponent(".launch-" + UUID().uuidString + ".json")
        try JSONEncoder().encode(request).write(to: file, options: .atomic)
        // Bundle.main can identify the outer GUI app when this tool lives in
        // Contents/MacOS. Re-execute the actual supervisor, never the GUI entrypoint.
        let worker = Process(); worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        worker.arguments = ["--launch-worker", file.path]
        worker.standardInput = FileHandle.nullDevice; worker.standardOutput = FileHandle.nullDevice; worker.standardError = FileHandle.nullDevice
        do { try worker.run() } catch { try? FileManager.default.removeItem(at: file); throw error }
        let message: String
        switch request.command {
        case .launchGame: message = "Launch requested. Waiting for the game process."
        case .installGame: message = "Installation requested. Confirm the download in Windows Steam."
        case .uninstallGame: message = "Uninstall requested. Confirm removal in Windows Steam."
        case .gameProperties: message = "Game properties requested in Windows Steam."
        case .verifyGame: message = "File verification requested. Check progress in Steam Downloads."
        case .openDownloads: message = "Steam Downloads requested."
        default: message = "Steam request sent."
        }
        return SupervisorReply(success: true, message: message)
    }
    public static func runLaunchWorker(requestFile: URL) throws {
        let data = try Data(contentsOf: requestFile)
        guard data.count <= 65_536 else { throw CrossedOverError.message("Launch worker request is too large.") }
        let request = try JSONDecoder().decode(SupervisorRequest.self, from: data)
        guard request.version == 1, ![.forceStop, .observe].contains(request.command) else { throw CrossedOverError.message("Invalid launch worker request.") }
        if request.command.requiresGameID {
            guard let id = request.appID, SteamDiscovery.validAppID(id) else { throw CrossedOverError.message("Invalid game identifier.") }
        }
        let paths = AppPaths(root: request.root)
        guard requestFile.deletingLastPathComponent().standardizedFileURL == paths.logs.standardizedFileURL,
              requestFile.lastPathComponent.hasPrefix(".launch-") else { throw CrossedOverError.message("Launch request must be in the managed logs directory.") }
        try FileManager.default.removeItem(at: requestFile)
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        guard let environment = try store.all(ManagedEnvironment.self, kind: "environment").first(where: { $0.id == request.environmentID }) else { throw CrossedOverError.message("Unknown environment.") }
        guard environment.state == "ready" || request.command == .shutdown else {
            throw CrossedOverError.message("Repair the Windows environment before opening Steam.")
        }
        let root = try FileSafety.containedURL(environment.runtimeID, in: paths.runtimes)
        let manifest = try JSONDecoder().decode(RuntimeManifest.self, from: Data(contentsOf: root.appendingPathComponent("runtime.json")))
        try RuntimeManager.validate(manifest, root: root, verifyHashes: false)
        let runtime = InstalledRuntime(manifest: manifest, root: root), prefix = paths.prefix(environment)
        var arguments = [try SteamService.steamExecutable(prefix: prefix).path]
        if request.command != .shutdown { arguments.append("-cef-disable-gpu") }
        if request.command == .shutdown { arguments += ["-shutdown"] }
        if request.command == .launchGame {
            guard let appID = request.appID, SteamDiscovery.validAppID(appID) else { throw CrossedOverError.message("Invalid game identifier.") }
            arguments += ["-silent", "-applaunch", appID]
            if let recipe = try ResourceCatalog.recipes().first(where: { $0.appID == appID }) {
                arguments += recipe.launchArguments ?? []
            }
        }
        if request.command == .installGame {
            guard let appID = request.appID, SteamDiscovery.validAppID(appID) else { throw CrossedOverError.message("Invalid game identifier.") }
            arguments.append("steam://install/" + appID)
        }
        let routes: [SupervisorRequest.Command: String] = [.uninstallGame: "uninstall", .gameProperties: "gameproperties", .verifyGame: "validate"]
        if let route = routes[request.command], let appID = request.appID { arguments.append("steam://" + route + "/" + appID) }
        if request.command == .openDownloads { arguments.append("steam://nav/downloads") }
        let pipe = Pipe(), process = Process()
        process.executableURL = runtime.wine; process.arguments = arguments
        process.currentDirectoryURL = prefix.appendingPathComponent("drive_c")
        process.environment = WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: environment.profile)
        process.standardInput = FileHandle.nullDevice; process.standardOutput = pipe; process.standardError = pipe
        // The parent releases its operation lock after the acknowledgement.
        var acquired: EnvironmentLock?
        for _ in 0..<100 {
            if let lock = try? EnvironmentLock(prefix: prefix) { acquired = lock; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard acquired != nil else { throw CrossedOverError.message("The environment remained locked during launch.") }
        try withExtendedLifetime(acquired) { try process.run() }; acquired = nil
        try pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        var bounded = Data()
        let log = paths.logs.appendingPathComponent("wine-session.log")
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            bounded.append(chunk)
            if bounded.count > 1_048_576 { bounded.removeFirst(bounded.count - 1_048_576) }
            try bounded.write(to: log, options: .atomic)
        }
    }
}

public struct SupervisorClient: Sendable {
    public var executable: URL
    public init(executable: URL) { self.executable = executable }
    public func send(_ request: SupervisorRequest) async throws -> SupervisorReply {
        let result = try await ProcessRunner.run(executable, input: JSONEncoder().encode(request), timeout: 30)
        guard let data = result.output.data(using: .utf8), let reply = try? JSONDecoder().decode(SupervisorReply.self, from: data) else { throw CrossedOverError.message("The runtime supervisor returned an invalid reply.") }
        guard result.status == 0, reply.success else { throw CrossedOverError.message(reply.message) }
        return reply
    }
}

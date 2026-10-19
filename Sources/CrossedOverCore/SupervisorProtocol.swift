import Foundation

public struct SupervisorRequest: Codable, Sendable {
    public var version: Int = 1
    public var root: URL
    public var environmentID: UUID
    public var command: Command
    public var appID: String?
    public var windowsAppID: UUID?
    public var runID: UUID?
    public enum Command: String, Codable, Sendable {
        case launchWindowsApp, openSteam, installGame, launchGame, uninstallGame, gameProperties, verifyGame, openDownloads, shutdown, forceStop, observe
        var requiresGameID: Bool { [.installGame, .launchGame, .uninstallGame, .gameProperties, .verifyGame].contains(self) }
    }
    public init(root: URL, environmentID: UUID, command: Command, appID: String? = nil, windowsAppID: UUID? = nil, runID: UUID? = nil) {
        self.root = root; self.environmentID = environmentID; self.command = command; self.appID = appID
        self.windowsAppID = windowsAppID; self.runID = runID
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
            throw CrossedOverError.message("Repair the Windows environment in Settings → Advanced before launching Windows software.")
        }
        if request.command == .launchWindowsApp {
            let app = try windowsApp(request, store: store)
            _ = try WindowsApps.executable(for: app, prefix: prefix)
            guard let runID = request.runID else { throw CrossedOverError.message("Missing Windows app launch identifier.") }
            let runs = try store.all(WindowsAppRun.self, kind: "windowsRun")
            guard !runs.contains(where: { $0.appID == app.id && $0.isActive && !$0.workerIsMissing }) else {
                throw CrossedOverError.message("This Windows app is already opening or running.")
            }
            guard !runs.contains(where: { $0.id == runID }) else { throw CrossedOverError.message("This launch identifier has already been used.") }
            try store.put(WindowsAppRun(id: runID, app: app), kind: "windowsRun", id: runID.uuidString)
        } else { _ = try SteamService.steamExecutable(prefix: prefix) }
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
        do { try worker.run() } catch {
            try? FileManager.default.removeItem(at: file)
            if let id = request.runID { try? store.remove(kind: "windowsRun", id: id.uuidString) }
            throw error
        }
        let message: String
        switch request.command {
        case .launchWindowsApp: message = "Windows app launch requested."
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
    private static func windowsApp(_ request: SupervisorRequest, store: Store) throws -> WindowsApp {
        guard let id = request.windowsAppID,
              let app = try store.all(WindowsApp.self, kind: "windowsApp").first(where: { $0.id == id && $0.environmentID == request.environmentID }) else {
            throw CrossedOverError.message("This Windows app is no longer in the library.")
        }
        return app
    }
    private static func runWindowsAppWorker(_ request: SupervisorRequest, paths: AppPaths, store: Store,
                                            environment: ManagedEnvironment, runtime: InstalledRuntime) throws {
        let app = try windowsApp(request, store: store), prefix = paths.prefix(environment)
        guard let id = request.runID,
              var run = try store.all(WindowsAppRun.self, kind: "windowsRun").first(where: { $0.id == id && $0.appID == app.id && $0.environmentID == environment.id && $0.state == "requested" }) else {
            throw CrossedOverError.message("Missing or already handled Windows app launch.")
        }
        run.workerPID = ProcessInfo.processInfo.processIdentifier
        try store.put(run, kind: "windowsRun", id: id.uuidString)
        var acquired: EnvironmentLock?
        for _ in 0..<100 {
            if let lock = try? EnvironmentLock(prefix: prefix) { acquired = lock; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard acquired != nil else { throw CrossedOverError.message("The environment remained locked during launch.") }
        let executable = try WindowsApps.executable(for: app, prefix: prefix)
        let pipe = Pipe(), process = Process()
        process.executableURL = runtime.wine; process.arguments = [executable.path]
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        var variables = WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: environment.profile)
        // Arbitrary apps must not inherit Steam's macOS identity.
        variables.removeValue(forKey: "CROSSEDOVER_STEAM_BRANDING")
        variables.removeValue(forKey: "WINEPRELOADERAPPNAME")
        process.environment = variables
        process.standardInput = FileHandle.nullDevice; process.standardOutput = pipe; process.standardError = pipe
        try withExtendedLifetime(acquired) { try process.run() }; acquired = nil
        run.state = "running"; run.detail = "Windows process started."
        try store.put(run, kind: "windowsRun", id: id.uuidString)
        try pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        let log = paths.logs.appendingPathComponent("windows-app-" + app.id.uuidString + ".log")
        var bounded = Data(), lastWrite = Date.distantPast
        try bounded.write(to: log, options: .atomic)
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            bounded.append(chunk)
            if bounded.count > 1_048_576 { bounded.removeFirst(bounded.count - 1_048_576) }
            if Date().timeIntervalSince(lastWrite) >= 0.25 {
                try bounded.write(to: log, options: .atomic); lastWrite = Date()
            }
        }
        try bounded.write(to: log, options: .atomic)
        process.waitUntilExit()
        run.exitCode = process.terminationStatus; run.endedAt = Date()
        run.state = process.terminationStatus == 0 ? "exited" : "failed"
        run.detail = process.terminationStatus == 0 ? "Windows process exited." : "Windows app exited with code \(process.terminationStatus). Open its launch log for details."
        try store.put(run, kind: "windowsRun", id: id.uuidString)
    }
    public static func runLaunchWorker(requestFile: URL) throws {
        var validatedRequest: SupervisorRequest?
        do { try launchWorker(requestFile: requestFile, validatedRequest: &validatedRequest) }
        catch {
            // The request is removed after validation, so preserve its identity separately.
            if let request = validatedRequest, request.command == .launchWindowsApp,
               let id = request.runID,
               let store = try? Store(url: request.root.appendingPathComponent("crossedover.sqlite")),
               var run = try? store.all(WindowsAppRun.self, kind: "windowsRun").first(where: { $0.id == id && $0.appID == request.windowsAppID && $0.environmentID == request.environmentID && $0.isActive }) {
                run.state = "failed"; run.endedAt = Date(); run.detail = Redaction.apply(error.localizedDescription)
                try? store.put(run, kind: "windowsRun", id: run.id.uuidString)
            }
            throw error
        }
    }
    private static func launchWorker(requestFile: URL, validatedRequest: inout SupervisorRequest?) throws {
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
        validatedRequest = request
        try FileManager.default.removeItem(at: requestFile)
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        guard let environment = try store.all(ManagedEnvironment.self, kind: "environment").first(where: { $0.id == request.environmentID }) else { throw CrossedOverError.message("Unknown environment.") }
        guard environment.state == "ready" || request.command == .shutdown else {
            throw CrossedOverError.message("Repair the Windows environment before launching Windows software.")
        }
        let root = try FileSafety.containedURL(environment.runtimeID, in: paths.runtimes)
        let manifest = try JSONDecoder().decode(RuntimeManifest.self, from: Data(contentsOf: root.appendingPathComponent("runtime.json")))
        try RuntimeManager.validate(manifest, root: root, verifyHashes: false)
        let runtime = InstalledRuntime(manifest: manifest, root: root), prefix = paths.prefix(environment)
        if request.command == .launchWindowsApp {
            try runWindowsAppWorker(request, paths: paths, store: store, environment: environment, runtime: runtime)
            return
        }
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
        process.executableURL = runtime.steamLoader; process.arguments = arguments
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

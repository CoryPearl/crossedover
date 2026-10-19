import Foundation

public struct SupervisorRequest: Codable, Sendable {
    public var version: Int = 1
    public var root: URL
    public var environmentID: UUID
    public var command: Command
    public var appID: String?
    public var windowsAppID: UUID?
    public var runID: UUID?
    // Recomputed by execute; caller input cannot select a different program.
    public var primeEpic: Bool? = nil
    var launchGeneration: String? = nil
    public enum Command: String, Codable, Sendable {
        case openUbisoft, launchUbisoftGame, ubisoftProperties, verifyUbisoftGame, uninstallUbisoftGame
        case openEpic, launchEpicGame, epicProperties, verifyEpicGame, uninstallEpicGame, epicDownloads
        case launchWindowsApp, openSteam, installGame, launchGame, uninstallGame, gameProperties, verifyGame, openDownloads, shutdown, forceStop, observe
        var isUbisoft: Bool { [.openUbisoft, .launchUbisoftGame, .ubisoftProperties, .verifyUbisoftGame, .uninstallUbisoftGame].contains(self) }
        var requiresUbisoftGameID: Bool { isUbisoft && self != .openUbisoft }
        var isEpic: Bool { [.openEpic, .launchEpicGame, .epicProperties, .verifyEpicGame, .uninstallEpicGame, .epicDownloads].contains(self) }
        var requiresEpicGameID: Bool { [.launchEpicGame, .epicProperties, .verifyEpicGame, .uninstallEpicGame].contains(self) }
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
        var launchRequest = request
        launchRequest.primeEpic = false
        var partnerLaunch = false
        let lock: EnvironmentLock
        if request.command == .forceStop {
            // Launch setup and a cold Epic primer briefly hold this lock.
            // Stopping must wait for their handoff rather than fail immediately.
            var acquired: EnvironmentLock?
            for _ in 0..<200 {
                if let candidate = try? EnvironmentLock(prefix: prefix) { acquired = candidate; break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard let acquired else { throw CrossedOverError.message("Windows is still preparing a launch. Try Stop again in a moment.") }
            lock = acquired
        } else { lock = try EnvironmentLock(prefix: prefix) }
        defer { withExtendedLifetime(lock) {} }
        if request.command == .forceStop {
            try LaunchGeneration.invalidate(prefix: prefix)
            _ = try await ProcessRunner.run(runtime.wineserver, arguments: ["-k"], environment: variables, timeout: 15)
            // -k returns nonzero when the server has already exited. A stopped
            // environment is a successful outcome, including repeated requests.
            let result = try await ProcessRunner.run(runtime.wineserver, arguments: ["-w"], environment: variables, timeout: 15)
            guard result.status == 0 else { throw CrossedOverError.message("Could not confirm environment shutdown: \(Redaction.apply(result.output).suffix(800))") }
            for var session in try store.all(LaunchSession.self, kind: "session") where session.environmentID == environment.id && session.endedAt == nil && ["requested", "running", "unknown"].contains(session.state) {
                session.state = "stopped"; session.endedAt = Date(); session.detail = "Stopped by the user with all Windows windows."
                try store.put(session, kind: "session", id: session.id.uuidString)
            }
            for var run in try store.all(WindowsAppRun.self, kind: "windowsRun") where run.environmentID == environment.id && run.isActive {
                run.state = "stopped"; run.endedAt = Date(); run.detail = "Stopped by the user with all Windows windows."
                try store.updateActiveWindowsRun(run)
            }
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
        if request.command.isEpic || request.command.isUbisoft {
            try EpicService.requireSupportedRuntime(runtime)
            if request.command.isUbisoft { _ = try UbisoftDiscovery.executable(prefix: prefix) }
            else { _ = try EpicService.executable(prefix: prefix) }
            if request.command.requiresEpicGameID || request.command.requiresUbisoftGameID {
                let game = try request.command.isUbisoft ? ubisoftGame(request, environment: environment, prefix: prefix) : epicGame(request, environment: environment, prefix: prefix)
                partnerLaunch = request.command == .launchEpicGame && game.epicPartnerGameID != nil
                if partnerLaunch { _ = try UbisoftDiscovery.executable(prefix: prefix) }
                if [.launchEpicGame, .verifyEpicGame, .uninstallEpicGame, .launchUbisoftGame, .verifyUbisoftGame, .uninstallUbisoftGame].contains(request.command) {
                    let names = try GameProcessDetection.executableNames(for: game, recipe: nil)
                    guard !names.isEmpty, let observer = runtime.manifest.observerRelativePath else { throw CrossedOverError.message("Could not confirm this game is closed. Manage it in Windows Epic.") }
                    let source = try FileSafety.containedURL(observer, in: runtime.root)
                    let destination = try FileSafety.containedURL("drive_c/crossedover/process-observer.exe", in: prefix)
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: source, to: destination) }
                    let result = try await ProcessRunner.run(runtime.wine, arguments: [destination.path], environment: variables, timeout: 15)
                    guard result.status == 0, let processes = decodeObservation(result.output) else { throw CrossedOverError.message("Could not check this game's running state. Close it and retry.") }
                    guard !processes.contains(where: { names.contains($0.executable.lowercased()) }) else { throw CrossedOverError.message("\(game.name) is running. Close it before retrying this action.") }
                    if request.command == .launchEpicGame && !partnerLaunch {
                        launchRequest.primeEpic = !processes.contains { $0.executable.lowercased() == "epicgameslauncher.exe" }
                    }
                }
            }
            try await EpicService.prepareGraphics(runtime: runtime, prefix: prefix, profile: environment.profile)
        } else if request.command == .launchWindowsApp {
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
        launchRequest.launchGeneration = try LaunchGeneration.current(prefix: prefix)
        let file = paths.logs.appendingPathComponent(".launch-" + UUID().uuidString + ".json")
        try JSONEncoder().encode(launchRequest).write(to: file, options: .atomic)
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
        case .openUbisoft: message = "Ubisoft Connect is opening."
        case .launchUbisoftGame: message = "Launch requested through Ubisoft Connect. Waiting for the game process."
        case .ubisoftProperties, .verifyUbisoftGame, .uninstallUbisoftGame: message = "Ubisoft Connect is opening. Choose the game in Library, then manage its files, verification, or uninstall there."
        case .openEpic: message = "Epic Games is opening. Sign in and install games there; completed installs appear in Games."
        case .launchEpicGame: message = partnerLaunch ? "Launch requested through Ubisoft Connect for this Epic installation. Waiting for the game process." : "Launch requested through Windows Epic. Waiting for the game process."
        case .uninstallEpicGame: message = "Epic Library is opening. Find the game, choose ⋯ → Manage → Uninstall, and confirm there."
        case .verifyEpicGame: message = "Epic Library is opening. Find the game, choose ⋯ → Manage → Verify, and check progress in Epic."
        case .epicProperties: message = "Epic Library is opening. Choose the game's ⋯ → Manage menu."
        case .epicDownloads: message = "Epic Library is opening. Use Epic's Downloads control for progress and updates."
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
    private static func ubisoftGame(_ request: SupervisorRequest, environment: ManagedEnvironment, prefix: URL) throws -> GameInstallation {
        guard let id = request.appID, SteamDiscovery.validAppID(id),
              let game = try UbisoftDiscovery().discover(environment: environment, prefix: prefix).first(where: { $0.appID == id }) else {
            throw CrossedOverError.message("This Ubisoft game is no longer installed. Refresh the library.")
        }
        return game
    }
    private static func epicGame(_ request: SupervisorRequest, environment: ManagedEnvironment, prefix: URL) throws -> GameInstallation {
        guard let id = request.appID, EpicDiscovery.validIdentifier(id),
              let game = try EpicDiscovery().discover(environment: environment, prefix: prefix).first(where: { $0.appID == id }) else {
            throw CrossedOverError.message("This Epic game is no longer installed. Refresh the Games library.")
        }
        return game
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
        guard try store.updateActiveWindowsRun(run) else { throw CrossedOverError.message("This Windows app launch was cancelled.") }
        var acquired: EnvironmentLock?
        for _ in 0..<100 {
            if let lock = try? EnvironmentLock(prefix: prefix) { acquired = lock; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard acquired != nil else { throw CrossedOverError.message("The environment remained locked during launch.") }
        try LaunchGeneration.check(request.launchGeneration, prefix: prefix)
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
        try store.updateActiveWindowsRun(run)
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
        try store.updateActiveWindowsRun(run)
    }
    public static func runLaunchWorker(requestFile: URL) throws {
        var validatedRequest: SupervisorRequest?
        do { try launchWorker(requestFile: requestFile, validatedRequest: &validatedRequest) }
        catch {
            // The request is removed after validation, so preserve its identity separately.
            if let request = validatedRequest, request.command.isEpic || request.command.isUbisoft {
                let name = request.command.isEpic ? "epic-session.log" : "ubisoft-session.log"
                let message = "Launch worker failed: " + Redaction.apply(error.localizedDescription).prefix(4096) + "\n"
                try? Data(message.utf8).write(to: AppPaths(root: request.root).logs.appendingPathComponent(name), options: .atomic)
            }
            if let request = validatedRequest, request.command == .launchWindowsApp,
               let id = request.runID,
               let store = try? Store(url: request.root.appendingPathComponent("crossedover.sqlite")),
               var run = try? store.all(WindowsAppRun.self, kind: "windowsRun").first(where: { $0.id == id && $0.appID == request.windowsAppID && $0.environmentID == request.environmentID && $0.isActive }) {
                run.state = "failed"; run.endedAt = Date(); run.detail = Redaction.apply(error.localizedDescription)
                try? store.updateActiveWindowsRun(run)
            }
            throw error
        }
    }
    private static func launchWorker(requestFile: URL, validatedRequest: inout SupervisorRequest?) throws {
        let data = try Data(contentsOf: requestFile)
        guard data.count <= 65_536 else { throw CrossedOverError.message("Launch worker request is too large.") }
        let request = try JSONDecoder().decode(SupervisorRequest.self, from: data)
        guard request.version == 1, ![.forceStop, .observe].contains(request.command) else { throw CrossedOverError.message("Invalid launch worker request.") }
        if request.command.requiresUbisoftGameID {
            guard let id = request.appID, SteamDiscovery.validAppID(id) else { throw CrossedOverError.message("Invalid Ubisoft game identifier.") }
        }
        if request.command.requiresEpicGameID {
            guard let id = request.appID, EpicDiscovery.validIdentifier(id) else { throw CrossedOverError.message("Invalid Epic game identifier.") }
        }
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
        var arguments: [String]
        var primeEpic = false
        if request.command.isUbisoft {
            try EpicService.requireSupportedRuntime(runtime)
            arguments = [try UbisoftDiscovery.executable(prefix: prefix).path]
            if request.command.requiresUbisoftGameID {
                let game = try ubisoftGame(request, environment: environment, prefix: prefix)
                if request.command == .launchUbisoftGame { arguments.append(try UbisoftDiscovery.launchURI(game.appID)) }
            }
        } else if request.command.isEpic {
            try EpicService.requireSupportedRuntime(runtime)
            let launcher = try EpicService.executable(prefix: prefix)
            var uri = EpicService.libraryURI
            var partnerID: String?
            if request.command.requiresEpicGameID {
                let game = try epicGame(request, environment: environment, prefix: prefix)
                if request.command == .launchEpicGame {
                    uri = try EpicService.launchURI(for: game)
                    partnerID = game.epicPartnerGameID
                }
            }
            if let partnerID {
                // Epic installs these through Ubisoft. Use the installed
                // Ubisoft URL entry point after the user's account linking.
                arguments = [try UbisoftDiscovery.executable(prefix: prefix).path, try UbisoftDiscovery.launchURI(partnerID)]
            } else {
                // Match Epic’s registered URL handler: URI is the first argument.
                arguments = request.command == .openEpic ? [launcher.path, "-SkipBuildPatchPrereq"] : [launcher.path, uri]
                primeEpic = request.command == .launchEpicGame && request.primeEpic == true
            }
        } else { arguments = [try SteamService.steamExecutable(prefix: prefix).path] }
        if !request.command.isEpic && !request.command.isUbisoft && request.command != .shutdown { arguments.append("-cef-disable-gpu") }
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
        process.executableURL = (request.command.isEpic || request.command.isUbisoft) ? runtime.wine : runtime.steamLoader; process.arguments = arguments
        process.currentDirectoryURL = prefix.appendingPathComponent("drive_c")
        if request.command.isUbisoft { process.environment = UbisoftDiscovery.environment(runtime: runtime, prefix: prefix, profile: environment.profile) }
        else if request.command.isEpic { process.environment = EpicService.environment(runtime: runtime, prefix: prefix, profile: environment.profile) }
        else { process.environment = WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: environment.profile) }
        process.standardInput = FileHandle.nullDevice; process.standardOutput = pipe; process.standardError = pipe
        // The parent releases its operation lock after the acknowledgement.
        var acquired: EnvironmentLock?
        for _ in 0..<100 {
            if let lock = try? EnvironmentLock(prefix: prefix) { acquired = lock; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard acquired != nil else { throw CrossedOverError.message("The environment remained locked during launch.") }
        try LaunchGeneration.check(request.launchGeneration, prefix: prefix)
        var primer: Process?
        if primeEpic {
            // Cold URI startup hides Epic's UI before sign-in/linking can finish
            // under Wine. Start its normal UI first; then submit the URI to it.
            let client = Process()
            client.executableURL = runtime.wine
            client.arguments = [try EpicService.executable(prefix: prefix).path, "-SkipBuildPatchPrereq"]
            client.currentDirectoryURL = process.currentDirectoryURL
            client.environment = process.environment
            // Foundation transfers a Pipe's writer when Process.run starts.
            // Reusing that same Pipe for the URI process raises an Objective-C
            // file-handle exception before the handoff can run.
            client.standardInput = FileHandle.nullDevice
            client.standardOutput = FileHandle.nullDevice; client.standardError = FileHandle.nullDevice
            try withExtendedLifetime(acquired) { try client.run() }
            primer = client
            Thread.sleep(forTimeInterval: 3)
        }
        try withExtendedLifetime(acquired) { try process.run() }; acquired = nil
        defer { withExtendedLifetime(primer) {} }
        try pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        var bounded = Data(), lastWrite = Date.distantPast
        let log = paths.logs.appendingPathComponent(request.command.isUbisoft ? "ubisoft-session.log" : request.command.isEpic ? "epic-session.log" : "wine-session.log")
        try bounded.write(to: log, options: .atomic)
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            bounded.append(chunk)
            if bounded.count > 1_048_576 { bounded.removeFirst(bounded.count - 1_048_576) }
            // Drain continuously, but avoid rewriting a megabyte on every tiny
            // Wine diagnostic chunk during launcher activity and downloads.
            if Date().timeIntervalSince(lastWrite) >= 0.25 {
                try bounded.write(to: log, options: .atomic); lastWrite = Date()
            }
        }
        try bounded.write(to: log, options: .atomic)
    }
}

public struct SupervisorClient: Sendable {
    public var executable: URL
    public init(executable: URL) { self.executable = executable }
    public func send(_ request: SupervisorRequest) async throws -> SupervisorReply {
        let result = try await ProcessRunner.run(executable, input: JSONEncoder().encode(request), timeout: request.command == .forceStop ? 60 : 30)
        guard let data = result.output.data(using: .utf8), let reply = try? JSONDecoder().decode(SupervisorReply.self, from: data) else { throw CrossedOverError.message("The runtime supervisor returned an invalid reply.") }
        guard result.status == 0, reply.success else { throw CrossedOverError.message(reply.message) }
        return reply
    }
}

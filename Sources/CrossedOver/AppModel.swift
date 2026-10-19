import AppKit
import Foundation
import Observation
import CrossedOverCore

@MainActor @Observable final class AppModel {
    let paths: AppPaths
    let store: Store
    let runtimeManager: RuntimeManager
    let environmentManager: EnvironmentManager
    let steamService: SteamService
    var host: HostReport?
    var runtimes: [InstalledRuntime] = []
    var environment: ManagedEnvironment?
    var games: [GameInstallation] = []
    var recipes: [GameRecipe] = []
    var operations: [OperationRecord] = []
    var sessions: [LaunchSession] = []
    var currentSession: LaunchSession?
    var busy = false
    var progress = ""
    var error: String?
    var notice: String?
    var selectedPage = "library"
    var pendingGame: GameInstallation?
    var diagnostics: String?
    private var work: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var observationCount = 0
    var runtime: InstalledRuntime? {
        if let environment { return runtimes.first { $0.id == environment.runtimeID } }
        return runtimes.first { $0.id.hasPrefix("wine-11.0-cx") } ?? runtimes.first
    }
    var bundledRuntime: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("BundledRuntime"),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("runtime.json").path) else { return nil }
        return url
    }
    var steamInstalled: Bool { guard let environment else { return false }; return (try? SteamService.steamExecutable(prefix: paths.prefix(environment))) != nil }
    var trackManiaLogo: NSImage? {
        guard let environment,
              let steam = try? SteamService.steamExecutable(prefix: paths.prefix(environment)),
              let logo = try? FileSafety.containedURL("appcache/librarycache/11020/logo.png", in: steam.deletingLastPathComponent()) else { return nil }
        return NSImage(contentsOf: logo)
    }
    var setupStep: Int { runtimes.isEmpty ? 0 : environment == nil ? 1 : !steamInstalled ? 2 : 3 }
    var supervisor: SupervisorClient {
        let sibling = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("CrossedOverSupervisor")
        return SupervisorClient(executable: sibling)
    }
    init(recoverInterruptedOperations: Bool = true) throws {
        if let root = ProcessInfo.processInfo.environment["CROSSEDOVER_DATA_ROOT"] { paths = AppPaths(root: URL(fileURLWithPath: root)) }
        else { paths = AppPaths() }
        try paths.prepare(); store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        runtimeManager = RuntimeManager(paths: paths); environmentManager = EnvironmentManager(paths: paths, store: store); steamService = SteamService(paths: paths)
        recipes = try ResourceCatalog.recipes()
        // A previous process may have ended during an operation. Preserve its journal entry.
        for var record in try store.all(OperationRecord.self, kind: "operation") where recoverInterruptedOperations && record.state == "running" {
            record.state = "interrupted"; record.detail = "The previous operation was interrupted. Retry it or inspect the environment."; record.updatedAt = Date()
            try store.put(record, kind: "operation", id: record.id.uuidString)
        }
    }
    func start() async {
        host = await HostInspector.inspect(at: paths.root)
        await refresh()
        if let previous = sessions.first(where: { ["requested", "running", "unknown"].contains($0.state) && $0.endedAt == nil }),
           let game = games.first(where: { $0.appID == previous.appID }), let environment {
            currentSession = previous; monitor(game: game, environment: environment)
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self else { return }
                if !self.busy { await self.refresh() }
            }
        }
    }
    func refresh() async {
        do {
            runtimes = try await runtimeManager.installed()
            environment = try store.all(ManagedEnvironment.self, kind: "environment").first
            if let environment {
                do {
                    let discovered = try SteamDiscovery().discover(environment: environment, prefix: paths.prefix(environment)).filter { $0.appID == "11020" }
                    try store.replaceGames(discovered, environmentID: environment.id); games = discovered
                } catch {
                    if games.isEmpty { games = try store.all(GameInstallation.self, kind: "game").filter { $0.appID == "11020" } }
                }
            }
            operations = try store.all(OperationRecord.self, kind: "operation").sorted { $0.updatedAt > $1.updatedAt }
            sessions = try store.all(LaunchSession.self, kind: "session").sorted { $0.startedAt > $1.startedAt }
        } catch { self.error = error.localizedDescription }
    }
    func perform(_ title: String, action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; progress = title; error = nil; notice = nil
        work = Task {
            var record = OperationRecord(kind: title, state: "running", detail: title)
            do {
                try store.put(record, kind: "operation", id: record.id.uuidString)
                try await action(); try Task.checkCancellation(); record.state = "completed"; record.detail = "Completed"
            } catch is CancellationError { record.state = "cancelled"; record.detail = "Cancelled. You can retry this operation." }
            catch { record.state = "failed"; record.detail = Redaction.apply(error.localizedDescription); self.error = error.localizedDescription }
            record.updatedAt = Date(); try? store.put(record, kind: "operation", id: record.id.uuidString)
            busy = false; progress = ""; await refresh()
        }
    }
    func cancel() { work?.cancel() }
    func setup() {
        guard host?.supported == true else { error = host?.blockers.joined(separator: "\n") ?? "Checking your Mac…"; return }
        perform("Set up Steam") {
            var selected = self.runtime
            if selected == nil {
                if let bundled = self.bundledRuntime {
                    self.progress = "Preparing and verifying the included runtime…"
                    selected = try await self.runtimeManager.importLocal(bundled)
                } else {
                    throw CrossedOverError.message("This thin development build needs a Steam-ready runtime. Build runtime/build.py, import its output in Settings, or use the packaged app with the included runtime.")
                }
            }
            guard let runtime = selected else { return }
            guard runtime.id != "wine-devel-11.18" else { throw CrossedOverError.message("This community runtime has a known black Steam window. Use the source-built CrossedOver runtime from Settings.") }
            if let existing = self.environment, existing.runtimeID != runtime.id { throw CrossedOverError.message("The environment's runtime is missing. Import its matching runtime before continuing setup.") }
            var environment = self.environment
            if environment == nil {
                self.progress = "Creating your Windows environment…"
                environment = try await self.environmentManager.create(runtime: runtime)
            }
            guard let environment else { return }
            if environment.state == "needsRepair" { throw CrossedOverError.message("Open Settings → Advanced and repair the interrupted environment before continuing setup.") }
            if !self.steamInstalled {
                self.progress = "Downloading and installing Windows Steam…"
                try await self.steamService.install(environment: environment, runtime: runtime)
            }
            self.progress = "Opening Steam…"
            _ = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .openSteam))
            self.notice = "Sign in to Steam to install TrackMania."
        }
    }
    func openSteam() {
        guard let environment else { setup(); return }
        perform("Open Windows Steam") {
            _ = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .openSteam))
            self.notice = "Steam is opening."
        }
    }
    func install(_ recipe: GameRecipe) {
        guard let environment, steamInstalled else { setup(); return }
        perform("Request \(recipe.name) installation") {
            _ = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .installGame, appID: recipe.appID))
            self.notice = "Confirm the download in Steam."
        }
    }
    func manage(_ game: GameInstallation, command: SupervisorRequest.Command) {
        guard let environment, [.uninstallGame, .gameProperties, .verifyGame].contains(command) else { return }
        if [.uninstallGame, .verifyGame].contains(command), currentSession != nil {
            error = "Close the game before managing its files."; return
        }
        let title: String
        switch command {
        case .uninstallGame: title = "Uninstall \(game.name)"
        case .verifyGame: title = "Verify \(game.name) files"
        default: title = "Open \(game.name) properties"
        }
        perform(title) {
            let reply = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: command, appID: game.appID))
            self.notice = reply.message
        }
    }
    func openDownloads() {
        guard let environment else { return }
        perform("Open Steam downloads") {
            let reply = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .openDownloads))
            self.notice = reply.message
        }
    }
    func showGameFiles(_ game: GameInstallation) {
        guard let environment else { return }
        do {
            guard let current = try SteamDiscovery().discover(environment: environment, prefix: paths.prefix(environment)).first(where: { $0.appID == game.appID }) else { throw CrossedOverError.message("This game is no longer installed.") }
            NSWorkspace.shared.open(URL(fileURLWithPath: current.directory, isDirectory: true))
        } catch { self.error = error.localizedDescription }
    }
    func recipe(for game: GameInstallation) -> GameRecipe? { recipes.first { $0.appID == game.appID } }
    func requestLaunch(_ game: GameInstallation) {
        guard currentSession == nil else { error = "Finish the current session before launching another game."; return }
        if let recipe = recipe(for: game), let environment, !(recipe.compatibleProfiles ?? [recipe.profile]).contains(environment.profile) {
            guard runtime?.manifest.profiles.contains(recipe.profile) == true else {
                error = "\(game.name) targets the \(recipe.profile.title) profile. Import the updated bundled runtime from Settings before trying this profile."; return
            }
            pendingGame = game
        } else { launch(game, restart: false) }
    }
    func launch(_ game: GameInstallation, restart: Bool) {
        pendingGame = nil
        guard let environment, let runtime else { return }
        perform("Launch \(game.name)") {
            var updated = environment
            if restart, let recipe = self.recipe(for: game) {
                self.progress = "Closing Steam before switching graphics…"
                _ = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .shutdown))
                var stopped = false
                for _ in 0..<15 {
                    try Task.checkCancellation()
                    do { try await self.environmentManager.requireStopped(environment, runtime: runtime); stopped = true; break }
                    catch { try await Task.sleep(for: .seconds(1)) }
                }
                guard stopped else { throw CrossedOverError.message("Steam is still running. Close its windows or use Force Stop in Environment, then retry.") }
                updated = try await self.environmentManager.setProfile(recipe.profile, environment: environment, runtime: runtime)
            }
            _ = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: updated.id, command: .launchGame, appID: game.appID))
            let session = LaunchSession(id: UUID(), appID: game.appID, environmentID: updated.id, startedAt: Date(), state: "requested")
            try self.store.put(session, kind: "session", id: session.id.uuidString); self.currentSession = session
            self.monitor(game: game, environment: updated)
        }
    }
    private func monitor(game: GameInstallation, environment: ManagedEnvironment) {
        monitorTask?.cancel(); observationCount = 0
        monitorTask = Task {
            var observedRunning = false
            let executableNames = recipe(for: game)?.executableNames.map { $0.lowercased() } ?? []
            while !Task.isCancelled, var session = currentSession {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                do {
                    let reply = try await supervisor.send(SupervisorRequest(root: paths.root, environmentID: environment.id, command: .observe))
                    guard let processes = reply.processes, !executableNames.isEmpty else {
                        session.state = "unknown"; session.detail = "Launch requested; this runtime or game has no validated process observer. Check the Steam window."
                        currentSession = session; try store.put(session, kind: "session", id: session.id.uuidString); return
                    }
                    let running = processes.contains { executableNames.contains($0.executable.lowercased()) }
                    if running { observedRunning = true; session.state = "running"; session.detail = "Game process observed." }
                    else if observedRunning {
                        session.state = "exited"; session.endedAt = Date(); session.detail = "Game process exited."
                        try store.put(session, kind: "session", id: session.id.uuidString); currentSession = nil; await refresh(); return
                    } else if Date().timeIntervalSince(session.startedAt) > 90 {
                        session.state = "failed"; session.endedAt = Date(); session.detail = "No matching game process appeared within 90 seconds. Check Steam for prompts."
                        try store.put(session, kind: "session", id: session.id.uuidString); currentSession = nil; error = session.detail; return
                    }
                    currentSession = session; try store.put(session, kind: "session", id: session.id.uuidString)
                } catch {
                    observationCount += 1
                    if observationCount >= 3 {
                        session.state = "unknown"; session.detail = "Process observation was interrupted. Check Windows Steam."
                        currentSession = session; try? store.put(session, kind: "session", id: session.id.uuidString); return
                    }
                }
            }
        }
    }
    func dismissUnknownSession() {
        if var session = currentSession {
            session.state = "unknown"; session.endedAt = Date(); session.detail = "Tracking dismissed by the user; game exit was not confirmed."
            try? store.put(session, kind: "session", id: session.id.uuidString)
        }
        monitorTask?.cancel(); currentSession = nil
    }
    func stop(force: Bool) {
        guard let environment else { return }
        perform(force ? "Force stop environment" : "Close Windows Steam") {
            _ = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: force ? .forceStop : .shutdown))
            if force {
                if var session = self.currentSession { session.state = "stopped"; session.endedAt = Date(); try self.store.put(session, kind: "session", id: session.id.uuidString) }
                self.currentSession = nil; self.monitorTask?.cancel()
            }
            self.notice = force ? "Stop requested for this Windows environment." : "Steam shutdown requested. Wait for its windows to close."
        }
    }
    func backup() {
        guard let environment, let runtime else { return }
        perform("Back up environment") { let url = try await self.environmentManager.backup(environment, runtime: runtime); self.notice = "Backup created."; NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func repair() {
        guard let environment, let runtime else { return }
        perform("Repair environment") { _ = try await self.environmentManager.repair(environment, runtime: runtime); self.notice = "Environment repaired. You can retry Steam setup." }
    }
    func changeProfile(_ profile: GraphicsProfile) {
        guard let environment, let runtime else { return }
        perform("Change graphics profile") {
            _ = try await self.environmentManager.setProfile(profile, environment: environment, runtime: runtime)
            self.notice = "Graphics profile changed to \(profile.title)."
        }
    }
    func useRuntime(_ replacement: InstalledRuntime) {
        guard let environment, let runtime else { return }
        perform("Back up and change runtime") {
            _ = try await self.environmentManager.migrate(environment, from: runtime, to: replacement)
            self.notice = "Runtime changed. The previous environment is preserved in Backups."
        }
    }
    func restoreBackup() {
        guard let environment else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = paths.backups
        panel.message = "Restore a managed backup. This replaces game files and saves inside the environment with their backed-up versions."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform("Restore environment backup") {
            _ = try await self.environmentManager.restore(url, current: environment, runtimeManager: self.runtimeManager)
            self.notice = "Environment and runtime selection restored."
        }
    }
    func importRuntime() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Select a trusted development runtime containing runtime.json. Its code runs with your user permissions."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform("Import development runtime") { _ = try await self.runtimeManager.importLocal(url); self.notice = "Runtime imported." }
    }
    func showDiagnostics() { do { diagnostics = try DiagnosticsService.preview(paths: paths, store: store, host: host) } catch { self.error = error.localizedDescription } }
    func exportDiagnostics(_ text: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "CrossedOver-diagnostics.txt"; panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url { do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription } }
    }
}

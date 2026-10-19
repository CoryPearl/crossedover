import AppKit
import Foundation
import ImageIO
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
    private var refreshing = false
    private var steamPath: URL?
    private var logoPath: String?
    @ObservationIgnored private var missingArtwork = Set<String>()
    var runtime: InstalledRuntime? {
        if let environment { return runtimes.first { $0.id == environment.runtimeID } }
        return runtimes.first { $0.id.hasPrefix("wine-11.0-cx") } ?? runtimes.first
    }
    var bundledRuntime: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("BundledRuntime"),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("runtime.json").path) else { return nil }
        return url
    }
    var steamInstalled: Bool { environment != nil && steamPath != nil }
    var trackManiaLogo: NSImage? { logoPath.flatMap { cachedImage(at: $0) } }
    @ObservationIgnored private let artworkCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>(); cache.countLimit = 64; cache.totalCostLimit = 64 * 1024 * 1024; return cache
    }()
    func artwork(for game: GameInstallation) -> NSImage? { game.artworkPath.flatMap { cachedImage(at: $0) } }
    private func cachedImage(at path: String) -> NSImage? {
        if let cached = artworkCache.object(forKey: path as NSString) { return cached }
        guard !missingArtwork.contains(path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640
              ] as CFDictionary) else { missingArtwork.insert(path); return nil }
        let image = NSImage(cgImage: thumbnail, size: .zero)
        artworkCache.setObject(image, forKey: path as NSString, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }
    func updateSteamLocation() {
        steamPath = environment.flatMap { try? SteamService.steamExecutable(prefix: paths.prefix($0)) }
        logoPath = steamPath.flatMap { try? FileSafety.containedURL("appcache/librarycache/11020/logo.png", in: $0.deletingLastPathComponent()).path }
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
        guard refreshTask == nil else { return }
        host = await HostInspector.inspect(at: paths.root)
        await refresh()
        if let previous = sessions.first(where: { ["requested", "running", "unknown"].contains($0.state) && $0.endedAt == nil }),
           let game = games.first(where: { $0.appID == previous.appID }), let environment {
            currentSession = previous; monitor(game: game, environment: environment)
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, let self else { return }
                if !self.busy && NSApp.isActive { await self.refresh() }
            }
        }
    }
    func refresh() async {
        guard !refreshing && !busy else { return }
        refreshing = true; defer { refreshing = false }
        do {
            let installed = try await runtimeManager.installed()
            // Discovery and SQLite writes can touch thousands of filesystem paths.
            // Keep them off the UI actor and leave unchanged observable values alone.
            let paths = paths, store = store
            let snapshot = try await Task.detached(priority: .utility) {
                let environment = try store.all(ManagedEnvironment.self, kind: "environment").first
                var games: [GameInstallation] = []
                if let environment {
                    let saved = try store.all(GameInstallation.self, kind: "game").filter { $0.environmentID == environment.id }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    games = (try? SteamDiscovery().discover(environment: environment, prefix: paths.prefix(environment))) ?? saved
                    if games != saved { try store.replaceGames(games, environmentID: environment.id) }
                }
                let operations = try store.all(OperationRecord.self, kind: "operation").sorted { $0.updatedAt > $1.updatedAt }
                let sessions = try store.all(LaunchSession.self, kind: "session").sorted { $0.startedAt > $1.startedAt }
                let steam = environment.flatMap { try? SteamService.steamExecutable(prefix: paths.prefix($0)) }
                let logo = steam.flatMap { try? FileSafety.containedURL("appcache/librarycache/11020/logo.png", in: $0.deletingLastPathComponent()).path }
                return (environment, games, operations, sessions, steam, logo)
            }.value
            guard !Task.isCancelled else { return }
            if runtimes != installed { runtimes = installed }
            if environment != snapshot.0 { environment = snapshot.0 }
            if games != snapshot.1 { games = snapshot.1 }
            if operations != snapshot.2 { operations = snapshot.2 }
            if sessions != snapshot.3 { sessions = snapshot.3 }
            if steamPath != snapshot.4 { steamPath = snapshot.4 }
            if logoPath != snapshot.5 { logoPath = snapshot.5 }
            missingArtwork.removeAll()
        } catch { self.error = error.localizedDescription }
    }
    func perform(_ title: String, action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; progress = title; error = nil; notice = nil
        work = Task {
            var record = OperationRecord(kind: title, state: "running", detail: title)
            do {
                let initial = record, store = store
                try await Task.detached(priority: .utility) { try store.put(initial, kind: "operation", id: initial.id.uuidString) }.value
                try await action(); try Task.checkCancellation(); record.state = "completed"; record.detail = "Completed"
            } catch is CancellationError { record.state = "cancelled"; record.detail = "Cancelled. You can retry this operation." }
            catch { record.state = "failed"; record.detail = Redaction.apply(error.localizedDescription); self.error = error.localizedDescription }
            record.updatedAt = Date()
            let finished = record, store = store
            try? await Task.detached(priority: .utility) { try store.put(finished, kind: "operation", id: finished.id.uuidString) }.value
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
            guard runtime.id != "wine-devel-11.18" else { throw CrossedOverError.message("This community runtime has a known black Steam window. Use the source-built crossedover runtime from Settings.") }
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
            self.notice = "Sign in to Steam to download your games."
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
    func openSteamDownloads() {
        guard let environment else { return }
        perform("Open Steam downloads") {
            let reply = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .openDownloads))
            self.notice = reply.message
        }
    }
    func openDownloadsFolder() {
        guard let environment else { error = "Set up Windows Steam first."; return }
        do {
            let folder = try SteamService.gamesFolder(prefix: paths.prefix(environment))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(folder) else { throw CrossedOverError.message("Finder couldn't open the games folder.") }
        } catch { self.error = error.localizedDescription }
    }
    func showGameFiles(_ game: GameInstallation) {
        guard let environment else { return }
        let prefix = paths.prefix(environment)
        Task {
            do {
                let folder = try await Task.detached(priority: .utility) {
                    guard let current = try SteamDiscovery().discover(environment: environment, prefix: prefix).first(where: { $0.appID == game.appID }) else {
                        throw CrossedOverError.message("This game is no longer installed.")
                    }
                    return URL(fileURLWithPath: current.directory, isDirectory: true)
                }.value
                guard NSWorkspace.shared.open(folder) else { throw CrossedOverError.message("Finder couldn't open this game's files.") }
            } catch { self.error = error.localizedDescription }
        }
    }
    func showWindowsDocuments() {
        guard let environment else { return }
        do {
            let folder = try GameFiles.documents(prefix: paths.prefix(environment))
            guard NSWorkspace.shared.open(folder) else { throw CrossedOverError.message("Finder couldn't open Windows Documents.") }
        } catch { self.error = error.localizedDescription }
    }
    func recipe(for game: GameInstallation) -> GameRecipe? { recipes.first { $0.appID == game.appID } }
    func gameName(appID: String) -> String {
        games.first { $0.appID == appID }?.name ?? recipes.first { $0.appID == appID }?.name ?? "Steam game \(appID)"
    }
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
            let recipe = recipe(for: game)
            let executableNames = (try? await Task.detached {
                try GameProcessDetection.executableNames(for: game, recipe: recipe)
            }.value) ?? []
            guard !Task.isCancelled else { return }
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
                    if currentSession != session {
                        currentSession = session
                        let saved = session, store = store
                        try await Task.detached(priority: .utility) { try store.put(saved, kind: "session", id: saved.id.uuidString) }.value
                    }
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
        perform("Change runtime") {
            _ = try await self.environmentManager.migrate(environment, from: runtime, to: replacement)
            self.notice = "Runtime changed. No automatic backup was created."
        }
    }
    func useIncludedRuntime() {
        guard let bundledRuntime, let environment, let current = runtime else { return }
        guard currentSession == nil else { error = "Quit your game before updating the runtime."; return }
        perform("Use included runtime") {
            let manifest = try await Task.detached(priority: .utility) {
                try JSONDecoder().decode(RuntimeManifest.self, from: Data(contentsOf: bundledRuntime.appendingPathComponent("runtime.json")))
            }.value
            guard manifest.id != current.id else { self.notice = "The included runtime is already in use."; return }
            try await self.environmentManager.requireStopped(environment, runtime: current)
            let installed = try await self.runtimeManager.installed()
            let replacement: InstalledRuntime
            if let existing = installed.first(where: { $0.id == manifest.id }) { replacement = existing }
            else { replacement = try await self.runtimeManager.importLocal(bundledRuntime) }
            _ = try await self.environmentManager.migrate(environment, from: current, to: replacement)
            self.notice = "Included runtime is ready. Reopen Steam to apply its updates."
        }
    }
    func clearBackups() {
        perform("Move backups to Trash") {
            let root = self.paths.root, store = self.store, paths = self.paths
            try await Task.detached(priority: .utility) {
                let locks = try store.all(ManagedEnvironment.self, kind: "environment").map { try EnvironmentLock(prefix: paths.prefix($0)) }
                defer { withExtendedLifetime(locks) {} }
                let backups = try ManagedStorage.backups(in: root, expected: AppPaths().root)
                if FileManager.default.fileExists(atPath: backups.path) {
                    try FileManager.default.trashItem(at: backups, resultingItemURL: nil)
                    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
                }
            }.value
            self.notice = "Backups moved to Trash. Empty Trash in Finder to reclaim their disk space."
        }
    }
    func uninstallApplication() {
        guard !busy else { return }
        guard currentSession == nil else { error = "Quit your game before uninstalling crossedover."; return }
        busy = true; progress = "Checking before uninstall…"; error = nil
        work = Task {
            do {
                let root = try ManagedStorage.dataRoot(paths.root, expected: AppPaths().root)
                let app = try ManagedStorage.application(Bundle.main.bundleURL, identifier: Bundle.main.bundleIdentifier)
                let store = store, paths = paths
                let environments = try await Task.detached {
                    try store.all(ManagedEnvironment.self, kind: "environment")
                }.value
                var locks: [EnvironmentLock] = []
                for environment in environments {
                    locks.append(try EnvironmentLock(prefix: paths.prefix(environment)))
                    let runtime = try await runtimeManager.resolve(environment.runtimeID)
                    try await environmentManager.requireStopped(environment, runtime: runtime)
                }
                // Nothing is removed until every managed Windows environment is stopped.
                while refreshing { try await Task.sleep(for: .milliseconds(50)) }
                try Task.checkCancellation()
                try FileManager.default.trashItem(at: root, resultingItemURL: nil)
                refreshTask?.cancel(); monitorTask?.cancel()
                try? store.close()
                UserDefaults.standard.removePersistentDomain(forName: "org.crossedover.CrossedOver")
                do { try FileManager.default.trashItem(at: app, resultingItemURL: nil) }
                catch {
                    let alert = NSAlert()
                    alert.messageText = "Games and app data moved to Trash"
                    alert.informativeText = "The app itself couldn't be moved. Quit crossedover and move it to Trash in Finder. Empty Trash to reclaim space."
                    alert.runModal()
                }
                withExtendedLifetime(locks) {}
                NSApp.terminate(nil)
            } catch { self.error = error.localizedDescription; busy = false; progress = "" }
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
        let panel = NSSavePanel(); panel.nameFieldStringValue = "crossedover-diagnostics.txt"; panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url { do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription } }
    }
}

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Observation
import CrossedOverCore

@MainActor @Observable final class AppModel {
    let paths: AppPaths
    let store: Store
    let runtimeManager: RuntimeManager
    let environmentManager: EnvironmentManager
    let steamService: SteamService
    let epicService: EpicService
    var host: HostReport?
    var runtimes: [InstalledRuntime] = []
    var environment: ManagedEnvironment?
    var games: [GameInstallation] = []
    var windowsApps: [WindowsApp] = []
    var windowsRuns: [WindowsAppRun] = []
    var recipes: [GameRecipe] = []
    var operations: [OperationRecord] = []
    var sessions: [LaunchSession] = []
    var currentSession: LaunchSession?
    var openingGame: GameInstallation?
    var openingApp: WindowsApp?
    var stoppingWindows = false
    var busy = false
    var progress = ""
    var error: String?
    var notice: String?
    var selectedPage = "library"
    var pendingGame: GameInstallation?
    var diagnostics: String?
    var showingMinecraft = false
    var bedrockStatus: BedrockEvent?
    var bedrockAvailable = false
    var bedrockChecked = false
    var bedrockInstalled = false
    var minecraftArtworkPath: String?
    var bedrockActive = false
    var bedrockStopping = false
    var bedrockError: String?
    private var bedrockChecking = false
    @ObservationIgnored private var verifiedBedrockBackend: BedrockBackend?
    private let bedrockService = BedrockService()
    private var bedrockTask: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var observationCount = 0
    private var refreshing = false
    private var steamPath: URL?
    private var epicPath: URL?
    private var ubisoftPath: URL?
    private var logoPath: String?
    var runtime: InstalledRuntime? {
        if let environment { return runtimes.first { $0.id == environment.runtimeID } }
        return runtimes.first { $0.id.hasPrefix("wine-11.0-cx") } ?? runtimes.first
    }
    var bundledRuntime: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("BundledRuntime"),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("runtime.json").path) else { return nil }
        return url
    }
    var epicInstalled: Bool { environment != nil && epicPath != nil }
    var steamInstalled: Bool { environment != nil && steamPath != nil }
    var ubisoftInstalled: Bool { environment != nil && ubisoftPath != nil }
    var bedrockBackendDirectory: URL? {
        if let path = ProcessInfo.processInfo.environment["CROSSEDOVER_BEDROCK_BACKEND"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        guard let resources = Bundle.main.resourceURL else { return nil }
        return resources.appendingPathComponent("BedrockBackend", isDirectory: true)
    }
    var launchStatus: (title: String, detail: String, waiting: Bool)? {
        if bedrockActive {
            return (bedrockStopping ? "Stopping Minecraft…" : bedrockStatus?.title ?? "Checking Minecraft…",
                    bedrockStatus?.detail ?? "Preparing the separate Bedrock session.", bedrockStatus?.phase != .playing || bedrockStopping)
        }
        if stoppingWindows { return ("Closing Windows…", "Stopping launches, games, and launchers.", true) }
        if let openingGame { return ("Opening \(openingGame.name)…", progress, true) }
        if let openingApp { return ("Opening \(openingApp.name)…", "Starting the Windows program.", true) }
        if let currentSession {
            let name = gameName(appID: currentSession.appID)
            switch currentSession.state {
            case "running": return ("\(name) is running", "Stop closes all crossedover Windows windows.", false)
            case "unknown": return ("Check \(name)’s launcher", "The launch was sent; game status is unavailable.", false)
            default: return ("Opening \(name)…", "Waiting for the game. Check its launcher for sign-in or setup prompts.", true)
            }
        }
        if let run = windowsRuns.first(where: { $0.environmentID == environment?.id && $0.isActive }),
           let app = windowsApps.first(where: { $0.id == run.appID }) {
            return (run.state == "requested" ? "Opening \(app.name)…" : "\(app.name) is running",
                    run.state == "requested" ? "Waiting for the Windows program." : "Stop closes all crossedover Windows windows.", run.state == "requested")
        }
        return nil
    }
    @ObservationIgnored var previewArtwork: [String: CGImage] = [:]
    func artworkPath(for game: GameInstallation?) -> String? {
        if game == nil || (game?.store == .steam && game?.appID == "11020") { return logoPath ?? game?.artworkPath }
        return game?.artworkPath
    }
    private func refreshMinecraftArtwork() async {
        guard minecraftArtworkPath == nil else { return }
        let root = paths.root
        minecraftArtworkPath = await Task.detached(priority: .utility) {
            for name in ["LargeLogo.png", "Logo.png", "StoreLogo.png"] {
                if let file = try? FileSafety.containedURL("Bedrock/game/" + name, in: root),
                   FileManager.default.fileExists(atPath: file.path) { return file.path }
            }
            return nil as String?
        }.value
    }
    func preparePreviewArtwork() async {
        await refreshMinecraftArtwork()
        for path in Set(games.compactMap { artworkPath(for: $0) } + [logoPath, minecraftArtworkPath].compactMap { $0 }) {
            previewArtwork[path] = await LibraryArtworkCache.shared.image(at: path)
        }
    }
    func updateSteamLocation() {
        steamPath = environment.flatMap { try? SteamService.steamExecutable(prefix: paths.prefix($0)) }
        epicPath = environment.flatMap { try? EpicService.executable(prefix: paths.prefix($0)) }
        ubisoftPath = environment.flatMap { try? UbisoftDiscovery.executable(prefix: paths.prefix($0)) }
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
        runtimeManager = RuntimeManager(paths: paths); environmentManager = EnvironmentManager(paths: paths, store: store); steamService = SteamService(paths: paths); epicService = EpicService(paths: paths)
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
        Task { await self.checkMinecraft() }
        if let previous = sessions.first(where: { ["requested", "running", "unknown"].contains($0.state) && $0.endedAt == nil }),
           let game = games.first(where: { $0.sessionAppID == previous.appID && $0.environmentID == previous.environmentID }), let environment {
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
    func refresh(refreshSizes: Bool = false) async {
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
                    games = GameLibrary.discover(environment: environment, prefix: paths.prefix(environment), previous: saved, refreshSizes: refreshSizes)
                    if games != saved { try store.replaceGames(games, environmentID: environment.id) }
                }
                let operations = try store.all(OperationRecord.self, kind: "operation").sorted { $0.updatedAt > $1.updatedAt }
                let sessions = try store.all(LaunchSession.self, kind: "session").sorted { $0.startedAt > $1.startedAt }
                let steam = environment.flatMap { try? SteamService.steamExecutable(prefix: paths.prefix($0)) }
                let logo = steam.flatMap { try? FileSafety.containedURL("appcache/librarycache/11020/logo.png", in: $0.deletingLastPathComponent()).path }
                let apps = try store.all(WindowsApp.self, kind: "windowsApp")
                    .filter { $0.environmentID == environment?.id }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                var runs = try store.all(WindowsAppRun.self, kind: "windowsRun").sorted { $0.startedAt > $1.startedAt }
                for index in runs.indices where runs[index].isActive && runs[index].workerIsMissing {
                    runs[index].state = "interrupted"; runs[index].endedAt = Date()
                    runs[index].detail = "The launch worker stopped. You can try opening the app again."
                    try store.put(runs[index], kind: "windowsRun", id: runs[index].id.uuidString)
                }
                let epic = environment.flatMap { try? EpicService.executable(prefix: paths.prefix($0)) }
                let ubisoft = environment.flatMap { try? UbisoftDiscovery.executable(prefix: paths.prefix($0)) }
                return (environment, games, operations, sessions, steam, logo, apps, runs, epic, ubisoft)
            }.value
            guard !Task.isCancelled else { return }
            if runtimes != installed { runtimes = installed }
            if environment != snapshot.0 { environment = snapshot.0 }
            if games != snapshot.1 { games = snapshot.1 }
            if operations != snapshot.2 { operations = snapshot.2 }
            if sessions != snapshot.3 { sessions = snapshot.3 }
            if steamPath != snapshot.4 { steamPath = snapshot.4 }
            if logoPath != snapshot.5 { logoPath = snapshot.5 }
            if windowsApps != snapshot.6 { windowsApps = snapshot.6 }
            if windowsRuns != snapshot.7 { windowsRuns = snapshot.7 }
            if epicPath != snapshot.8 { epicPath = snapshot.8 }
            if ubisoftPath != snapshot.9 { ubisoftPath = snapshot.9 }
            await refreshMinecraftInstallation()
        } catch { self.error = error.localizedDescription }
    }
    func perform(_ title: String, id: UUID = UUID(), completionState: String = "completed", allowsStopping: Bool = false, action: @escaping @MainActor () async throws -> Void) {
        guard !busy, !stoppingWindows || allowsStopping else { return }
        busy = true; progress = title; error = nil; notice = nil
        work = Task {
            var record = OperationRecord(kind: title, state: "running", detail: title)
            record.id = id
            do {
                let initial = record, store = store
                try await Task.detached(priority: .utility) { try store.put(initial, kind: "operation", id: initial.id.uuidString) }.value
                try Task.checkCancellation(); try await action(); try Task.checkCancellation()
                record.state = completionState
                record.detail = completionState == "requested" ? "Launch request sent. Waiting for the game process." : "Completed"
            } catch is CancellationError { record.state = "cancelled"; record.detail = "Cancelled. You can retry this operation." }
            catch {
                if Task.isCancelled { record.state = "cancelled"; record.detail = "Cancelled. You can retry this operation." }
                else { record.state = "failed"; record.detail = Redaction.apply(error.localizedDescription); self.error = error.localizedDescription }
            }
            record.updatedAt = Date()
            let finished = record, store = store
            try? await Task.detached(priority: .utility) { try store.finishOperation(finished) }.value
            openingGame = nil; openingApp = nil
            busy = false; progress = ""; await refresh()
        }
    }
    func cancel() { work?.cancel() }

    func checkMinecraft() async {
        guard !bedrockActive, !bedrockChecked, !bedrockChecking else { return }
        bedrockChecking = true; defer { bedrockChecking = false }
        bedrockError = nil
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
            bedrockError = "This local Bedrock preview requires an Apple silicon Mac with macOS 26 or later."
            bedrockChecked = true; return
        }
        guard let directory = bedrockBackendDirectory,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("backend.json").path) else {
            bedrockChecked = true; return
        }
        do {
            let backend = try await Task.detached(priority: .utility) { try BedrockBackend.load(at: directory) }.value
            let status = try await backend.status(dataRoot: paths.root)
            verifiedBedrockBackend = backend
            bedrockStatus = status; bedrockInstalled = status.phase == .ready; bedrockAvailable = true
            if bedrockInstalled { await refreshMinecraftArtwork() }
        } catch { bedrockError = "Minecraft's preview backend could not be verified. Rebuild or reinstall the matching backend." }
        bedrockChecked = true
    }

    private func refreshMinecraftInstallation() async {
        guard !bedrockActive, !bedrockChecking, let backend = verifiedBedrockBackend else { return }
        bedrockChecking = true; defer { bedrockChecking = false }
        // Offline status checks never sign in. Reuse the verified backend so
        // ordinary library refreshes do not hash its entire runtime again.
        guard let status = try? await backend.status(dataRoot: paths.root), !bedrockActive else { return }
        bedrockInstalled = status.phase == .ready
        if bedrockInstalled { await refreshMinecraftArtwork() }
        else { minecraftArtworkPath = nil }
    }

    func startMinecraft(signOut: Bool = false) {
        guard !bedrockActive, !busy, bedrockAvailable, let directory = bedrockBackendDirectory else { return }
        bedrockActive = true; bedrockStopping = false; bedrockStatus = nil; bedrockError = nil
        bedrockTask = Task {
            do {
                let backend = try await Task.detached(priority: .utility) { try BedrockBackend.load(at: directory) }.value
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
                    throw CrossedOverError.message("This Minecraft preview requires macOS 26 or later and Apple silicon.")
                }
                let events = try await bedrockService.events(backend: backend, dataRoot: paths.root, signOut: signOut)
                for try await event in events {
                    bedrockStatus = event
                    if event.phase == .ready || event.phase == .playing {
                        bedrockInstalled = true
                        await refreshMinecraftArtwork()
                    }
                    if event.phase == .new { bedrockInstalled = false }
                    if event.phase == .error { bedrockError = event.detail }
                }
            } catch is CancellationError {
                bedrockStatus = nil
            } catch {
                // A worker can report a reviewed failure before exiting with
                // nonzero status. Keep that actionable message for the user.
                if bedrockError == nil {
                    bedrockError = "Minecraft's session stopped. Your completed installation and worlds were kept. You can try again."
                }
            }
            // Stream cancellation can end iteration before the worker finishes
            // unwinding its children. Keep Stop/Uninstall fenced until it exits.
            let service = bedrockService
            await Task.detached { await service.waitUntilStopped() }.value
            bedrockActive = false; bedrockStopping = false
            await refreshMinecraftInstallation()
            // Preserve the session's failure/cancellation message. A subsequent
            // status check must not erase why installation stopped.
        }
    }

    func stopMinecraft() {
        guard bedrockActive, !bedrockStopping else { return }
        bedrockStopping = true
        // Cancel before the worker starts, or ask its own lifecycle to unwind.
        bedrockTask?.cancel()
        Task { await bedrockService.cancel() }
    }

    func openMinecraftFiles() {
        do {
            let home = try BedrockService.home(in: paths.root)
            guard FileManager.default.fileExists(atPath: home.path) else { return }
            NSWorkspace.shared.open(home)
        } catch { bedrockError = "Minecraft's files could not be opened safely." }
    }

    func uninstallMinecraft() {
        guard !bedrockActive, !busy else { return }
        perform("Uninstall Minecraft") {
            let paths = self.paths
            try await Task.detached(priority: .utility) {
                let lock = try BedrockService.acquireIdleData(dataRoot: paths.root)
                defer { withExtendedLifetime(lock) {} }
                let home = try BedrockService.home(in: paths.root)
                let original = home.appendingPathComponent("game")
                guard try original.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                    throw CrossedOverError.message("Minecraft's game folder is a symbolic link. It was preserved.")
                }
                let game = try FileSafety.containedURL("game", in: home)
                try FileManager.default.trashItem(at: game, resultingItemURL: nil)
            }.value
            self.bedrockInstalled = false; self.bedrockStatus = nil; self.minecraftArtworkPath = nil
            self.bedrockChecked = false; await self.checkMinecraft()
            self.notice = "Minecraft moved to Trash. Your worlds were kept in its separate Windows environment."
        }
    }
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
        guard let environment, steamInstalled else { setup(); return }
        perform("Open Windows Steam") {
            _ = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .openSteam))
            self.notice = "Steam is opening."
        }
    }
    func openEpic(reinstall: Bool = false) {
        perform(reinstall ? "Repair Windows Epic" : "Open Windows Epic") {
            let environment = try await self.prepareWindowsEnvironment()
            let runtime = try await self.runtimeManager.resolve(environment.runtimeID)
            if reinstall || (try? EpicService.executable(prefix: self.paths.prefix(environment))) == nil {
                self.progress = "Downloading and installing Epic's Windows launcher…"
                try await self.epicService.install(environment: environment, runtime: runtime)
            } else if try EpicLaunchSupport.installedVersion(prefix: self.paths.prefix(environment)) == nil {
                self.progress = "Installing Epic’s launch support. Keep Windows apps closed…"
                try await self.epicService.repairLaunchSupport(environment: environment, runtime: runtime)
            }
            self.progress = "Opening Epic Games…"
            let reply = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .openEpic))
            self.notice = reply.message
        }
    }
    func repairEpicLaunchSupport() {
        guard let environment else { return }
        perform("Repair Epic launch support") {
            let runtime = try await self.runtimeManager.resolve(environment.runtimeID)
            self.progress = "Installing Epic’s required components. Keep Windows apps closed…"
            try await self.epicService.repairLaunchSupport(environment: environment, runtime: runtime)
            self.notice = "Epic launch support is ready. You can try Play again."
        }
    }
    func openUbisoft() {
        guard let environment, ubisoftInstalled else {
            error = "Ubisoft Connect is not installed. Open a supported Ubisoft game in Epic to complete its launcher setup."
            return
        }
        perform("Open Ubisoft Connect") {
            let reply = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .openUbisoft))
            self.notice = reply.message
        }
    }
    func openEpicDownloads() {
        guard let environment else { openEpic(); return }
        perform("Open Epic downloads") {
            let reply = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .epicDownloads))
            self.notice = reply.message
        }
    }
    func openEpicGamesFolder() {
        guard let environment else { return }
        do {
            let folder = try EpicService.gamesFolder(prefix: paths.prefix(environment))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(folder) else { throw CrossedOverError.message("Finder couldn't open the Epic games folder.") }
        } catch { self.error = error.localizedDescription }
    }
    /// App imports need Wine, but never require downloading or signing into Steam.
    private func prepareWindowsEnvironment() async throws -> ManagedEnvironment {
        if let environment {
            guard environment.state == "ready", runtime != nil else { throw CrossedOverError.message("Repair the Windows environment or import its missing runtime in Settings → Advanced.") }
            return environment
        }
        guard host?.supported == true else { throw CrossedOverError.message(host?.blockers.joined(separator: "\n") ?? "Wait for the Mac compatibility check to finish.") }
        var selected = runtime
        if selected == nil, let bundledRuntime {
            progress = "Preparing the included Windows runtime…"
            selected = try await runtimeManager.importLocal(bundledRuntime)
        }
        guard let selected else { throw CrossedOverError.message("Import a runtime in Settings or use the packaged app with its included runtime.") }
        progress = "Creating your Windows environment…"
        return try await environmentManager.create(runtime: selected)
    }
    func chooseWindowsExecutable(for app: WindowsApp? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.title = app == nil ? "Add a Windows app or game" : "Choose the program to launch"
        panel.message = app == nil ? "Choose a local .exe. It will be added as a library card." : "After an installer finishes, choose the installed program’s .exe inside the Windows C: drive."
        if app != nil, let environment { panel.directoryURL = paths.prefix(environment).appendingPathComponent("drive_c") }
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
    func addWindowsApp(_ url: URL, name: String, category: LibraryCategory, includeFolder: Bool, replacing: WindowsApp? = nil) {
        perform(replacing == nil ? "Add \(name)" : "Update \(name)") {
            try await Task.detached(priority: .utility) { try WindowsApps.validateExecutable(url) }.value
            let environment = try await self.prepareWindowsEnvironment()
            self.progress = "Adding \(name) to your library…"
            let paths = self.paths, store = self.store
            let task = Task.detached(priority: .utility) {
                try WindowsApps.add(executable: url, name: name, category: category, includeFolder: includeFolder,
                                    environment: environment, paths: paths, store: store, replacing: replacing)
            }
            _ = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            self.selectedPage = category == .games ? "library" : "apps"
            self.notice = "Added to \(category.title). Use \(category == .games ? "Play" : "Run") on its card to open it."
        }
    }
    func latestRun(for app: WindowsApp) -> WindowsAppRun? { windowsRuns.first { $0.appID == app.id } }
    func runWindowsApp(_ app: WindowsApp) {
        guard !busy, !stoppingWindows, latestRun(for: app)?.isActive != true else { return }
        openingApp = app
        perform("Open \(app.name)") {
            defer { self.openingApp = nil }
            let reply = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: app.environmentID,
                command: .launchWindowsApp, windowsAppID: app.id, runID: UUID()))
            self.notice = reply.message
        }
    }
    func moveWindowsApp(_ app: WindowsApp, to category: LibraryCategory) {
        perform("Move \(app.name) to \(category.title)") {
            var updated = app; updated.category = category
            let store = self.store
            try await Task.detached { try store.put(updated, kind: "windowsApp", id: updated.id.uuidString) }.value
        }
    }
    func removeWindowsApp(_ app: WindowsApp) {
        perform("Remove \(app.name) from library") {
            let store = self.store
            try await Task.detached { try store.remove(kind: "windowsApp", id: app.id.uuidString) }.value
            self.notice = "Card removed. Its files stay in the Windows environment."
        }
    }
    func showWindowsAppFiles(_ app: WindowsApp) {
        guard let environment, environment.id == app.environmentID else { return }
        do {
            // Allow opening the containing folder even when the executable was moved or deleted.
            let folder = try FileSafety.containedURL((app.executablePath as NSString).deletingLastPathComponent, in: paths.prefix(environment))
            guard NSWorkspace.shared.open(folder) else { throw CrossedOverError.message("Finder couldn't open this app’s files.") }
        } catch { self.error = error.localizedDescription }
    }
    func showWindowsDrive() {
        guard let environment else { return }
        NSWorkspace.shared.open(paths.prefix(environment).appendingPathComponent("drive_c"))
    }
    func showWindowsAppLog(_ app: WindowsApp) {
        let log = paths.logs.appendingPathComponent("windows-app-" + app.id.uuidString + ".log")
        guard FileManager.default.fileExists(atPath: log.path) else { notice = "No launch log yet. Run the app first."; return }
        NSWorkspace.shared.open(log)
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
        let operation: SupervisorRequest.Command
        if game.managementStore == .ubisoft {
            operation = command == .uninstallGame ? .uninstallUbisoftGame : command == .verifyGame ? .verifyUbisoftGame : .ubisoftProperties
        } else if game.store == .epic {
            operation = command == .uninstallGame ? .uninstallEpicGame : command == .verifyGame ? .verifyEpicGame : .epicProperties
        } else { operation = command }
        let title: String
        switch command {
        case .uninstallGame: title = "Uninstall \(game.name)"
        case .verifyGame: title = "Verify \(game.name) files"
        default: title = "Open \(game.name) properties"
        }
        perform(title) {
            let reply = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: operation, appID: game.epicPartnerGameID ?? game.appID))
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
                    let games = try game.store == .epic ? EpicDiscovery().discover(environment: environment, prefix: prefix)
                        : game.store == .ubisoft ? UbisoftDiscovery().discover(environment: environment, prefix: prefix)
                        : SteamDiscovery().discover(environment: environment, prefix: prefix)
                    guard let current = games.first(where: { $0.id == game.id }) else {
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
    func recipe(for game: GameInstallation) -> GameRecipe? { game.store == .steam ? recipes.first { $0.appID == game.appID } : nil }
    func gameName(appID: String) -> String {
        games.first { $0.sessionAppID == appID }?.name ?? recipes.first { $0.appID == appID }?.name ?? "Game \(appID)"
    }
    func requestLaunch(_ game: GameInstallation) {
        guard currentSession == nil else { error = "Finish the current session before launching another game."; return }
        if let recipe = recipe(for: game), let environment, !(recipe.compatibleProfiles ?? [recipe.profile]).contains(environment.profile) {
            guard runtime?.manifest.supports(recipe.profile) == true else {
                error = "\(game.name) targets the \(recipe.profile.title) profile. Import the updated bundled runtime from Settings before trying this profile."; return
            }
            pendingGame = game
        } else { launch(game, restart: false) }
    }
    func launch(_ game: GameInstallation, restart: Bool) {
        guard !busy, !stoppingWindows, currentSession == nil else { return }
        pendingGame = nil
        guard let environment, let runtime else { return }
        openingGame = game
        let sessionID = UUID()
        perform("Launch \(game.name)", id: sessionID, completionState: "requested") {
            defer { self.openingGame = nil }
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
                guard stopped else { throw CrossedOverError.message("Close Steam, Epic, and Windows apps before changing graphics. Force quit is available in Settings → Advanced.") }
                updated = try await self.environmentManager.setProfile(recipe.profile, environment: environment, runtime: runtime)
            }
            try Task.checkCancellation()
            self.progress = "Preparing graphics and contacting \(game.store.title)…"
            _ = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: updated.id, command: game.store == .epic ? .launchEpicGame : game.store == .ubisoft ? .launchUbisoftGame : .launchGame, appID: game.appID))
            try Task.checkCancellation()
            let session = LaunchSession(id: sessionID, appID: game.sessionAppID, environmentID: updated.id, startedAt: Date(), state: "requested")
            try self.store.putSession(session); self.currentSession = session
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
                    guard !Task.isCancelled, currentSession?.id == session.id else { return }
                    guard let processes = reply.processes, !executableNames.isEmpty else {
                        session.state = "unknown"; session.detail = "Launch requested; this runtime or game has no validated process observer. Check the game's Windows launcher."
                        currentSession = session; try store.putSession(session); return
                    }
                    let running = processes.contains { executableNames.contains($0.executable.lowercased()) }
                    if running { observedRunning = true; session.state = "running"; session.detail = "Game process observed." }
                    else if observedRunning {
                        session.state = "exited"; session.endedAt = Date(); session.detail = "Game process exited."
                        try store.putSession(session); currentSession = nil; await refresh(); return
                    } else if Date().timeIntervalSince(session.startedAt) > 90 {
                        session.state = "failed"; session.endedAt = Date(); session.detail = "No matching game process appeared within 90 seconds. Check the game's Windows launcher for prompts."
                        try store.putSession(session); currentSession = nil; error = session.detail; return
                    }
                    if currentSession != session {
                        currentSession = session
                        let saved = session, store = store
                        _ = try await Task.detached(priority: .utility) { try store.putSession(saved) }.value
                    }
                } catch {
                    guard !Task.isCancelled, currentSession?.id == session.id else { return }
                    observationCount += 1
                    if observationCount >= 3 {
                        session.state = "unknown"; session.detail = "Process observation was interrupted. Check the game's Windows launcher."
                        currentSession = session; _ = try? store.putSession(session); return
                    }
                }
            }
        }
    }
    func dismissUnknownSession() {
        if var session = currentSession {
            session.state = "unknown"; session.endedAt = Date(); session.detail = "Tracking dismissed by the user; game exit was not confirmed."
            _ = try? store.putSession(session)
        }
        monitorTask?.cancel(); currentSession = nil
    }
    func stop(force: Bool) {
        if force { stopLaunchAndCloseWindows(); return }
        guard let environment else { return }
        perform("Close Windows Steam") {
            _ = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .shutdown))
            self.notice = "Steam shutdown requested. Wait for its windows to close."
        }
    }
    func stopLaunchAndCloseWindows() {
        guard !stoppingWindows, let environment else { return }
        stoppingWindows = true; pendingGame = nil
        let observation = monitorTask
        observation?.cancel()
        let previous = work
        previous?.cancel()
        stopTask = Task {
            // Let the cancelled operation finish before starting another one.
            // The supervisor also fences detached workers that have not run yet.
            await previous?.value
            await observation?.value
            self.perform("Stop and close Windows", allowsStopping: true) {
                defer { self.stoppingWindows = false; self.openingGame = nil; self.openingApp = nil }
                do {
                    _ = try await self.supervisor.send(SupervisorRequest(root: self.paths.root, environmentID: environment.id, command: .forceStop))
                    self.currentSession = nil
                    self.notice = "Windows games, apps, and launchers are closed."
                } catch {
                    if let session = self.currentSession, let game = self.games.first(where: { $0.sessionAppID == session.appID }) {
                        self.monitor(game: game, environment: environment)
                    }
                    throw error
                }
            }
        }
    }
    func backup() {
        guard let environment, let runtime else { return }
        perform("Back up environment") { let url = try await self.environmentManager.backup(environment, runtime: runtime); self.notice = "Backup created."; NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func repair() {
        guard let environment, let runtime else { return }
        perform("Repair environment") { _ = try await self.environmentManager.repair(environment, runtime: runtime); self.notice = "Environment repaired. You can retry setup or launch an app." }
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
            self.notice = "Included runtime is ready. Reopen Windows apps or Steam to apply its updates."
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
        guard !bedrockActive else { error = "Stop Minecraft's session before uninstalling crossedover."; return }
        guard currentSession == nil else { error = "Quit your game before uninstalling crossedover."; return }
        busy = true; progress = "Checking before uninstall…"; error = nil
        work = Task {
            do {
                let root = try ManagedStorage.dataRoot(paths.root, expected: AppPaths().root)
                let bedrockLock = try BedrockService.acquireIdleData(dataRoot: root)
                defer { withExtendedLifetime(bedrockLock) {} }
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
        panel.message = "Restore a managed backup. This replaces apps, games, saves, and executable cards with their backed-up versions."
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

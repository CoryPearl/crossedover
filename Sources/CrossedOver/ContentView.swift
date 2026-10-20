import AppKit
import SwiftUI
import CrossedOverCore

private enum Palette {
    static let canvas = Color(white: 0.085)
    static let sidebar = Color(white: 0.065)
    static let surface = Color(white: 0.105)
    static let ink = Color(white: 0.93)
    static let muted = Color(white: 0.60)
    static let line = Color(white: 0.21)
}

/// Search only local setting labels and concepts, never account or game data.
private enum SettingsSection: CaseIterable {
    case graphics, drive, steam, epic, platforms, recovery, runtime, support, backups, uninstall

    var isAdvanced: Bool { [.recovery, .runtime, .support].contains(self) }
    var index: String {
        switch self {
        case .graphics: "Windows environment graphics renderer DirectX DXMT DXVK Metal OpenGL performance legacy quality resolution frame limits"
        case .drive: "Windows environment C: drive files folders installed imported apps user Finder"
        case .steam: "Windows Steam client account library store open quit set up downloaded games download folder Finder progress updates"
        case .epic: "Windows Epic Games Launcher account library store open set up repair launch support graphics DirectX DXMT DXVK Metal downloaded games download folder files progress updates"
        case .platforms: "Other platforms Xbox Cloud Gaming stream browser account controller Minecraft Bedrock Windows edition WineGDK Microsoft sign in launcher"
        case .recovery: "Advanced recovery restore backups repair environment force quit stop files"
        case .runtime: "Advanced runtime import use included switch Wine version"
        case .support: "Advanced support diagnostics report show backups macOS memory hardware system requirements"
        case .backups: "Backups manual create clear delete Trash default Windows environment games apps saves disk space storage"
        case .uninstall: "Uninstall crossedover remove delete Windows apps games saves app data disk space storage"
        }
    }
    func matches(_ query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy { index.localizedStandardContains(String($0)) }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    var renderingSnapshot = false
    var previewAdvanced = false
    var previewLibraryMode: String? = nil
    var previewSearch: String? = nil
    @AppStorage("libraryPresentation") private var libraryPresentation = "grid"
    @State private var searchText = ""
    @State private var settingsSearchText = ""
    @FocusState private var settingsSearchFocused: Bool
    @AppStorage("gameStoreFilter") private var gameStoreFilter = "all"
    @FocusState private var searchFocused: Bool
    @State private var advancedExpanded = false
    @State private var forceStopConfirmation = false
    @State private var clearBackupsConfirmation = false
    @State private var uninstallConfirmation = false
    @State private var manualBackupConfirmation = false
    @State private var pendingRuntime: InstalledRuntime?
    @State private var pendingIncludedRuntime = false
    @State private var moddingGame: GameInstallation?
    @State private var propertiesGame: GameInstallation?
    @State private var executableDraft: WindowsAppDraft?
    @State private var removingApp: WindowsApp?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                if renderingSnapshot {
                    Color.clear.overlay(alignment: .topLeading) {
                        page.fixedSize(horizontal: false, vertical: true)
                    }.clipped()
                } else if model.selectedPage == "settings" {
                    VStack(alignment: .leading, spacing: 22) {
                        pageHeader
                        settingsSearchBar
                    }.padding(.horizontal, 32).padding(.top, 46).padding(.bottom, 22)
                    NativePageScroll(resetPosition: settingsQuery) {
                        settings.padding(.horizontal, 32).padding(.bottom, 40)
                            .frame(maxWidth: 1004, alignment: .topLeading)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else if model.selectedPage == "activity" {
                    NativePageScroll { page.frame(maxWidth: .infinity, alignment: .topLeading) }
                } else {
                    ScrollView { page.frame(maxWidth: .infinity, alignment: .topLeading) }
                }
                if let launch = model.launchStatus { launchStatus(launch) }
                else if model.busy || model.notice != nil { status }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Palette.ink).background(Palette.canvas).tint(Palette.ink)
        .ignoresSafeArea(.container, edges: .top)
        .focusedSceneValue(\.librarySearch, {
            if model.selectedPage == "settings" { settingsSearchFocused = true }
            else {
                if !["library", "apps"].contains(model.selectedPage) { model.selectedPage = "library" }
                searchFocused = true
            }
        })
        .alert("Couldn't complete the action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
            Button("View activity") { model.selectedPage = "activity"; model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Restart Steam to change graphics?", isPresented: Binding(get: { model.pendingGame != nil }, set: { if !$0 { model.pendingGame = nil } }), titleVisibility: .visible) {
            if let game = model.pendingGame { Button("Restart and play") { model.launch(game, restart: true) } }
            Button("Cancel", role: .cancel) { model.pendingGame = nil }
        } message: { Text("Close Epic and any running games or Windows apps first. Steam downloads may pause during the restart.") }
        .confirmationDialog("Force quit the Windows environment?", isPresented: $forceStopConfirmation, titleVisibility: .visible) {
            Button("Force quit", role: .destructive) { model.stop(force: true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Unsaved work and game progress may be lost.") }
        .confirmationDialog("Move all environment backups to Trash?", isPresented: $clearBackupsConfirmation, titleVisibility: .visible) {
            Button("Move backups to Trash", role: .destructive) { model.clearBackups() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your installed games and current saves stay in place. Backups remain in Trash until you empty it in Finder.") }
        .confirmationDialog("Uninstall crossedover and all its data?", isPresented: $uninstallConfirmation, titleVisibility: .visible) {
            Button("Uninstall app and data", role: .destructive) { model.uninstallApplication() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Quit Steam, Epic, games, and Windows apps first. This moves crossedover, its Windows Steam and Epic clients, every managed game and Windows app, local saves, runtimes, and backups to Trash, then quits. Empty Trash to reclaim space. Your separate Mac Steam library stays in place.") }
        .confirmationDialog("Create a full manual backup?", isPresented: $manualBackupConfirmation, titleVisibility: .visible) {
            Button("Create backup") { model.backup() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This copies the default Windows environment and its games, apps, and local saves. Other retained environments stay separate. Backups can take substantial disk space and are never automatic.") }
        .confirmationDialog("Change the Windows runtime?", isPresented: Binding(get: { pendingRuntime != nil || pendingIncludedRuntime }, set: { if !$0 { pendingRuntime = nil; pendingIncludedRuntime = false } }), titleVisibility: .visible) {
            if let runtime = pendingRuntime { Button("Change runtime") { pendingRuntime = nil; model.useRuntime(runtime) } }
            if pendingIncludedRuntime { Button("Use included runtime") { pendingIncludedRuntime = false; model.useIncludedRuntime() } }
            Button("Cancel", role: .cancel) { pendingRuntime = nil; pendingIncludedRuntime = false }
        } message: { Text("Quit Steam, Epic, games, and Windows apps first. This updates the Windows environment in place, without an automatic backup. You can create a manual backup in Settings → Backups before continuing.") }
        .confirmationDialog("Remove this card from your library?", isPresented: Binding(get: { removingApp != nil }, set: { if !$0 { removingApp = nil } }), titleVisibility: .visible) {
            if let app = removingApp { Button("Remove card", role: .destructive) { model.removeWindowsApp(app); removingApp = nil } }
            Button("Cancel", role: .cancel) { removingApp = nil }
        } message: { Text("The app’s files and installed software stay in the Windows environment. Removing a card does not uninstall the program.") }
        .sheet(item: $executableDraft) { draft in
            WindowsAppEditor(model: model, draft: draft) { executableDraft = nil }
        }
        .sheet(item: $propertiesGame) { game in gameProperties(game) }
        .sheet(item: $moddingGame) { game in modding(game) }
        .sheet(isPresented: $model.showingMinecraft) { MinecraftLauncherView(model: model) }
        .sheet(isPresented: Binding(get: { model.diagnostics != nil }, set: { if !$0 { model.diagnostics = nil } })) { diagnostics }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 19, weight: .medium))
                Text("crossedover").font(.system(size: 14, weight: .semibold)).tracking(-0.25)
            }.padding(.horizontal, 20).padding(.top, 54).padding(.bottom, 36)
            VStack(spacing: 5) {
                navigation("Games", icon: "gamecontroller", page: "library")
                navigation("Apps", icon: "square.grid.2x2", page: "apps")
                navigation("Settings", icon: "slider.horizontal.3", page: "settings")
            }.padding(.horizontal, 12)
            Spacer(minLength: 36)
            navigation("Activity", icon: "clock.arrow.circlepath", page: "activity").padding(.horizontal, 12)
            Rule().padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 10) {
                if renderingSnapshot { launcherMenuLabel }
                else {
                    Menu { GameLauncherActions(model: model) } label: { launcherMenuLabel }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .disabled(model.busy)
                        .help("Open Steam, Epic Games, Ubisoft Connect, or Minecraft")
                }
                Text("Windows launchers").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 20)
            Text("VERSION \(AppVersion.current)").font(.system(size: 9, weight: .medium)).tracking(1.2)
                .foregroundStyle(Palette.muted.opacity(0.7)).padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 24)
        }.frame(width: 196).frame(maxHeight: .infinity).background(Palette.sidebar)
    }

    private var launcherMenuLabel: some View {
        HStack(spacing: 8) {
            Text("Game Launchers")
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink.opacity(0.85))
            .padding(.horizontal, 12).frame(height: 34)
            .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
    }

    private func navigation(_ title: String, icon: String, page: String) -> some View {
        let selected = model.selectedPage == page
        return Button { model.selectedPage = page } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: selected ? .medium : .regular))
                Spacer()
            }.foregroundStyle(selected ? Palette.ink : Palette.muted).padding(.horizontal, 12).frame(height: 38)
                .background(selected ? Color.white.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Color.white.opacity(0.07) : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 28) {
            pageHeader
            switch model.selectedPage {
            case "settings":
                settingsSearchBar
                settings.frame(maxWidth: 940, alignment: .leading)
            case "activity": activity
            case "mods" where renderingSnapshot:
                if let game = model.games.first { modding(game) }
            case "import" where renderingSnapshot:
                WindowsAppEditor(model: model, draft: WindowsAppDraft(url: URL(fileURLWithPath: "/Users/you/Downloads/Windows App/app.exe"), category: .apps), renderingSnapshot: true, dismiss: {})
            default: library
            }
        }.padding(.horizontal, 32).padding(.top, 46).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.selectedPage == "settings" ? "Settings" : model.selectedPage == "activity" ? "Activity" : appsPage ? "Apps" : "Games")
                        .font(.system(size: 25, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text(model.selectedPage == "settings" ? "Windows, launchers, and app preferences." : model.selectedPage == "activity" ? "Recent actions and sessions." : appsPage ? "Your Windows apps, on Mac." : "Your games, together on Mac.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if ["library", "apps"].contains(model.selectedPage) {
                    Button { beginImport() } label: { Label("Add .exe", systemImage: "plus") }
                        .buttonStyle(SecondaryButton()).disabled(model.busy).keyboardShortcut("o")
                        .help("Add a Windows app or game (⌘O)")
                    Button { Task { await model.refresh(refreshSizes: true) } } label: { Image(systemName: "arrow.clockwise").frame(width: 12) }
                        .buttonStyle(SecondaryButton()).disabled(model.busy).help("Refresh library (⌘R)").accessibilityLabel("Refresh library")
                }
            }
            Rule()
        }
    }

    private var appsPage: Bool { model.selectedPage == "apps" }
    private var importedApps: [WindowsApp] { model.windowsApps.filter { $0.category == (appsPage ? .apps : .games) } }
    private var filteredApps: [WindowsApp] {
        guard appsPage || ["all", "added"].contains(gameStoreFilter) else { return [] }
        return query.isEmpty ? importedApps : importedApps.filter { $0.name.localizedStandardContains(query) }
    }
    private var query: String { (previewSearch ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showingList: Bool { (previewLibraryMode ?? libraryPresentation) == "list" }
    private var showingMinecraft: Bool {
        !appsPage && model.bedrockInstalled && ["all", "minecraft"].contains(gameStoreFilter)
            && (query.isEmpty || "Minecraft Bedrock Edition".localizedStandardContains(query))
    }
    private var filteredGames: [GameInstallation] {
        guard !appsPage else { return [] }
        return model.games.filter { game in
            (gameStoreFilter == "all" || gameStoreFilter == game.store.rawValue) && (query.isEmpty || game.name.localizedStandardContains(query))
        }
    }
    private var totalCount: Int { importedApps.count + (appsPage ? 0 : model.games.count + (model.bedrockInstalled ? 1 : 0)) }
    private var libraryCount: String {
        let count = filteredGames.count + filteredApps.count + (showingMinecraft ? 1 : 0), noun = appsPage ? "APPS" : "GAMES"
        return query.isEmpty ? "\(count) \(noun)" : "\(count) OF \(totalCount) \(noun)"
    }
    private var library: some View {
        let games = filteredGames, apps = filteredApps
        return VStack(alignment: .leading, spacing: 18) {
            libraryToolbar
            sectionLabel(totalCount == 0 ? "GET STARTED" : appsPage ? "YOUR APPS" : "YOUR GAMES", trailing: totalCount == 0 ? nil : libraryCount)
            if totalCount == 0 && query.isEmpty {
                if appsPage {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "app.dashed").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Palette.muted)
                        Text("Bring a Windows app.").font(.system(size: 18, weight: .medium))
                        Text("Add an .exe to keep it here. Run it whenever you need it, with no Steam account required.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        Button("Add Windows app…") { beginImport() }.buttonStyle(PrimaryButton()).disabled(model.busy)
                    }.padding(28).frame(maxWidth: 420, alignment: .leading).panel()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("A home for your Windows games.").font(.system(size: 18, weight: .medium))
                        Text("Install through Windows Steam or Epic. Completed downloads appear here automatically. Add .exe for games from elsewhere.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button(model.steamInstalled ? "Open Steam" : "Set up Steam") { model.openSteam() }.buttonStyle(SecondaryButton())
                            Button(model.epicInstalled ? "Open Epic" : "Set up Epic") { model.openEpic() }.buttonStyle(SecondaryButton())
                        }.disabled(model.busy)
                        if model.steamInstalled, let demo = model.recipes.first(where: { $0.appID == "11020" }) {
                            Button("Install TrackMania demo") { model.install(demo) }.buttonStyle(TextButton()).disabled(model.busy)
                        }
                    }.padding(28).frame(maxWidth: 510, alignment: .leading).panel()
                }
            } else if games.isEmpty && apps.isEmpty && !showingMinecraft {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 24, weight: .light)).foregroundStyle(Palette.muted)
                    Text(appsPage ? "No apps found" : "No games found").font(.system(size: 15, weight: .medium))
                    Text(query.isEmpty ? "Install games through the selected launcher, or choose All games." : "No titles match “\(query)”.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                    if !query.isEmpty { Button("Clear search") { searchText = ""; searchFocused = true }.buttonStyle(SecondaryButton()) }
                    else if gameStoreFilter == "epic" { Button(model.epicInstalled ? "Open Epic" : "Set up Epic") { model.openEpic() }.buttonStyle(SecondaryButton()).disabled(model.busy) }
                }.padding(.vertical, 64).padding(.horizontal, 24).frame(maxWidth: .infinity)
            } else if showingList {
                LazyVStack(spacing: 0) {
                    ForEach(games) { game in gameRow(game); if game.id != games.last?.id || !apps.isEmpty || showingMinecraft { Rule().padding(.horizontal, 16) } }
                    ForEach(apps) { app in windowsAppRow(app); if app.id != apps.last?.id || showingMinecraft { Rule().padding(.horizontal, 16) } }
                    if showingMinecraft { minecraftRow }
                }.panel()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(games) { game in gameCard(game) }
                    ForEach(apps) { app in windowsAppCard(app) }
                    if showingMinecraft { minecraftCard }
                }
            }
            if !appsPage, let tracked = model.currentSession,
               !model.games.contains(where: { $0.sessionAppID == tracked.appID && $0.environmentID == tracked.environmentID }) {
                HStack(spacing: 16) {
                    Text("The tracked game is no longer in this library.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                    Button("Dismiss tracking") { model.dismissUnknownSession() }.buttonStyle(TextButton())
                }.padding(18).panel()
            }
            if !model.steamInstalled, let blocker = model.host?.blockers.first {
                Label(blocker, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.top, 10)
            }
        }
    }

    private var minecraftState: String {
        model.bedrockActive ? (model.bedrockStatus?.phase == .playing ? "Running" : "Opening…") : "Installed"
    }
    private var minecraftActions: some View {
        HStack(spacing: 10) {
            Button { model.showingMinecraft = true } label: { Image(systemName: "ellipsis") }
                .buttonStyle(.plain).help("Minecraft launcher, files, and account options").accessibilityLabel("Minecraft options")
            Button { model.startMinecraft() } label: { Label(model.bedrockActive ? (model.bedrockStatus?.phase == .playing ? "Running" : "Opening") : "Play", systemImage: "play.fill") }
                .buttonStyle(PrimaryButton()).disabled(model.bedrockActive || !model.bedrockAvailable || model.busy)
                .accessibilityLabel("Play Minecraft Bedrock")
        }
    }
    private func minecraftArtwork(compact: Bool = false) -> some View {
        let path = model.minecraftArtworkPath
        return LibraryArtwork(path: path, preview: renderingSnapshot ? path.flatMap { model.previewArtwork[$0] } : nil) { image in
            ZStack {
                Palette.sidebar
                if let image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
                        .padding(compact ? 6 : 16).accessibilityLabel("Minecraft artwork")
                } else {
                    Image(systemName: "cube").font(.system(size: compact ? 22 : 34, weight: .ultraLight))
                        .foregroundStyle(Palette.muted).accessibilityHidden(true)
                }
            }
        }
    }
    private var minecraftCard: some View {
        VStack(spacing: 0) {
            minecraftArtwork().frame(height: 112).frame(maxWidth: .infinity)
            Rule()
            VStack(alignment: .leading, spacing: 10) {
                Text("MINECRAFT · WINDOWS").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.muted)
                Text("Minecraft Bedrock").font(.system(size: 17, weight: .medium)).tracking(-0.3)
            }.frame(height: 66, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            Text("Recommended: DirectX 10–11")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
                .help("Minecraft's separate environment uses DXMT automatically; the shared graphics setting does not change it.")
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
            Rule()
            HStack { Text(minecraftState).font(.system(size: 11)).foregroundStyle(Palette.muted); Spacer(); minecraftActions }
                .padding(.horizontal, 16).padding(.vertical, 14)
        }.panel()
    }
    private var minecraftRow: some View {
        HStack(spacing: 16) {
            minecraftArtwork(compact: true).frame(width: 88, height: 56).clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 6) {
                Text("Minecraft Bedrock").font(.system(size: 13, weight: .medium))
                Text("Minecraft · " + minecraftState).font(.system(size: 10)).foregroundStyle(Palette.muted)
                Text("Recommended: DirectX 10–11").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            minecraftActions
        }.padding(16)
    }
    private func beginImport(_ app: WindowsApp? = nil) {
        if let app, let environment = model.environment(id: app.environmentID) {
            let url = model.paths.prefix(environment).appendingPathComponent(app.executablePath)
            executableDraft = WindowsAppDraft(url: url, category: app.category, app: app)
        } else if let url = model.chooseWindowsExecutable() {
            executableDraft = WindowsAppDraft(url: url, category: appsPage ? .apps : .games)
        }
    }
    private func windowsAppState(_ app: WindowsApp) -> String {
        switch model.latestRun(for: app)?.state {
        case "requested": "Opening…"
        case "running": "Running"
        case "failed": "Last launch failed"
        case "interrupted": "Launch interrupted"
        default: "Ready"
        }
    }
    private func windowsAppIcon(_ app: WindowsApp, compact: Bool = false) -> some View {
        ZStack {
            Palette.sidebar
            Image(systemName: app.category == .games ? "gamecontroller" : "app")
                .font(.system(size: compact ? 22 : 32, weight: .ultraLight)).foregroundStyle(Palette.muted)
        }.accessibilityHidden(true)
    }
    private func windowsAppCard(_ app: WindowsApp) -> some View {
        VStack(spacing: 0) {
            windowsAppIcon(app).frame(height: 112)
            Rule()
            VStack(alignment: .leading, spacing: 10) {
                Text("WINDOWS · .EXE").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.muted)
                Text(app.name).font(.system(size: 17, weight: .medium)).tracking(-0.3).lineLimit(2).help(app.name)
            }.frame(height: 66, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            Rule()
            HStack(spacing: 12) {
                Text(windowsAppState(app)).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                Spacer(minLength: 0)
                windowsAppMenu(app)
                windowsAppAction(app)
            }.padding(.horizontal, 16).padding(.vertical, 14)
            windowsAppFailure(app)
        }.panel()
    }
    private func windowsAppRow(_ app: WindowsApp) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                windowsAppIcon(app, compact: true).frame(width: 88, height: 56).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1).help(app.name)
                    Text("Windows .exe · " + windowsAppState(app)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) { windowsAppMenu(app); windowsAppAction(app) }.fixedSize()
            }.padding(16)
            windowsAppFailure(app)
        }
    }
    @ViewBuilder private func windowsAppFailure(_ app: WindowsApp) -> some View {
        if let run = model.latestRun(for: app), ["failed", "interrupted"].contains(run.state), let detail = run.detail {
            Rule()
            Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(3).help(detail)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func windowsAppAction(_ app: WindowsApp) -> some View {
        let run = model.latestRun(for: app)
        return Button { model.runWindowsApp(app) } label: {
            Label(run?.isActive == true ? (run?.state == "running" ? "Running" : "Opening") : app.category == .games ? "Play" : "Run", systemImage: "play.fill")
                .lineLimit(1).fixedSize()
        }.buttonStyle(PrimaryButton()).disabled(model.busy || run?.isActive == true).accessibilityLabel("Run " + app.name)
    }
    private func windowsAppMenu(_ app: WindowsApp) -> some View {
        Group {
            if renderingSnapshot { managementLabel(compact: true) }
            else {
                Menu {
                    Button("Edit app / choose executable…") { beginImport(app) }.disabled(model.latestRun(for: app)?.isActive == true)
                    Button("Show app files") { model.showWindowsAppFiles(app) }
                    Button("Show launch log") { model.showWindowsAppLog(app) }
                    Button(app.category == .games ? "Move to Apps" : "Move to Games") { model.moveWindowsApp(app, to: app.category == .games ? .apps : .games) }
                    Divider()
                    Button("Remove from library…", role: .destructive) { removingApp = app }.disabled(model.latestRun(for: app)?.isActive == true)
                } label: { managementLabel(compact: true) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Manage " + app.name)
            }
        }.disabled(model.busy)
    }

    private var libraryToolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Palette.muted)
                if renderingSnapshot {
                    Text(query.isEmpty ? appsPage ? "Search apps" : "Search games" : query).foregroundStyle(query.isEmpty ? Palette.muted : Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(appsPage ? "Search apps" : "Search games", text: $searchText).textFieldStyle(.plain)
                        .focused($searchFocused).accessibilityLabel(appsPage ? "Search apps" : "Search games")
                        .onExitCommand { if searchText.isEmpty { searchFocused = false } else { searchText = "" } }
                }
                if !query.isEmpty {
                    Button { searchText = ""; searchFocused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                    }.buttonStyle(.plain).accessibilityLabel("Clear search").help("Clear search")
                }
            }.font(.system(size: 12)).padding(.horizontal, 11).frame(height: 34).frame(maxWidth: 340)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(searchFocused ? Palette.muted : Palette.line))
                .background {
                    if !renderingSnapshot { SearchFocusDismissal(isFocused: searchFocused) { searchFocused = false } }
                }
            Spacer(minLength: 0)
            if !appsPage {
                if renderingSnapshot { menuLabel(storeFilterTitle) }
                else {
                    Menu {
                        Button("All games") { gameStoreFilter = "all" }
                        Button("Steam") { gameStoreFilter = "steam" }
                        Button("Epic Games") { gameStoreFilter = "epic" }
                        Button("Ubisoft Connect") { gameStoreFilter = "ubisoft" }
                        if model.bedrockInstalled { Button("Minecraft") { gameStoreFilter = "minecraft" } }
                        Button("Added .exe") { gameStoreFilter = "added" }
                    } label: { menuLabel(storeFilterTitle) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Filter games by store")
                }
            }
            HStack(spacing: 2) {
                presentationButton("grid", title: "Grid view", symbol: "square.grid.2x2")
                presentationButton("list", title: "List view", symbol: "list.bullet")
            }.padding(3).background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
        }
    }

    private var storeFilterTitle: String {
        switch gameStoreFilter { case "steam": "Steam"; case "epic": "Epic Games"; case "ubisoft": "Ubisoft Connect"; case "minecraft": "Minecraft"; case "added": "Added .exe"; default: "All games" }
    }
    private func presentationButton(_ mode: String, title: String, symbol: String) -> some View {
        let selected = (showingList ? "list" : "grid") == mode
        return Button { libraryPresentation = mode } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 32, height: 28)
                .foregroundStyle(selected ? Palette.ink : Palette.muted)
                .background(selected ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func gameRow(_ game: GameInstallation) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                artwork(game, compact: true).frame(width: 88, height: 56).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name).font(.system(size: 13, weight: .medium)).lineLimit(1).help(game.name)
                    Text(game.store.title + " · " + gameState(game) + (game.sizeBytes > 0 ? " · " + ByteCountFormatter.string(fromByteCount: game.sizeBytes, countStyle: .file) : ""))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                    rendererHint(game)
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) { manageMenu(game, compact: true); gameAction(game) }.fixedSize()
            }
            if session(for: game)?.state == "unknown" {
                HStack {
                    Text("Check Steam for game status.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Dismiss tracking") { model.dismissUnknownSession() }.buttonStyle(TextButton())
                }
            }
        }.padding(16)
    }

    private func session(for game: GameInstallation?) -> LaunchSession? {
        guard let game, let session = model.currentSession,
              session.appID == game.sessionAppID, session.environmentID == game.environmentID else { return nil }
        return session
    }

    private func gameCard(_ game: GameInstallation?) -> some View {
        VStack(spacing: 0) {
            artwork(game).frame(height: 112)
            Rule()
            gameDetails(game).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            rendererHint(game).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
            Rule()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.muted).frame(width: 5, height: 5)
                        Text(gameState(game)).font(.system(size: 11, weight: .medium)).lineLimit(1).help(gameState(game))
                    }
                    if let game, game.sizeBytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: game.sizeBytes, countStyle: .file))
                            .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1).help("Installed game files")
                    }
                }
                Spacer(minLength: 8)
                if let game { manageMenu(game, compact: true) }
                gameAction(game)
            }.padding(.horizontal, 16).padding(.vertical, 14)
            if session(for: game)?.state == "unknown" {
                Rule()
                HStack(spacing: 16) {
                    Text("Check Steam for game status.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                    Button("Dismiss tracking") { model.dismissUnknownSession() }.buttonStyle(TextButton())
                }.padding(16)
            }
        }.panel()
    }

    private func artwork(_ game: GameInstallation?, compact: Bool = false) -> some View {
        let isDemo = game == nil || (game?.store == .steam && game?.appID == "11020")
        let path = model.artworkPath(for: game)
        return LibraryArtwork(path: path, preview: renderingSnapshot ? path.flatMap { model.previewArtwork[$0] } : nil) { image in
            ZStack {
                (isDemo ? Color(white: 0.85) : Palette.sidebar)
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().padding(.horizontal, compact ? 8 : 22).padding(.vertical, compact ? 8 : 18)
                        .accessibilityLabel("\(game?.name ?? "TrackMania Nations Forever") artwork")
                } else if isDemo && !compact {
                    VStack(spacing: 5) {
                        Text("TRACKMANIA").font(.system(size: 25, weight: .heavy, design: .rounded)).tracking(-1)
                        Text("NATIONS FOREVER").font(.system(size: 10, weight: .semibold)).tracking(2)
                    }.foregroundStyle(Color(white: 0.12))
                } else {
                    Image(systemName: "gamecontroller").font(.system(size: compact ? 20 : 26, weight: .ultraLight))
                        .foregroundStyle(Palette.muted).accessibilityHidden(true)
                }
            }
        }
    }

    private func gameDetails(_ game: GameInstallation?) -> some View {
        let isDemo = game == nil || (game?.store == .steam && game?.appID == "11020")
        return VStack(alignment: .leading, spacing: 0) {
            Text(game?.store.title.uppercased() ?? "STEAM").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.muted)
                .padding(.bottom, 10)
            Text(isDemo ? "TrackMania" : game?.name ?? "Windows game")
                .font(.system(size: 17, weight: .medium)).tracking(-0.3).lineLimit(2)
                .help(game?.name ?? "TrackMania Nations Forever")
            if isDemo {
                Text("Nations Forever").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 3)
            }
        }.frame(height: 66, alignment: .topLeading)
    }

    @ViewBuilder private func rendererHint(_ game: GameInstallation?) -> some View {
        if let game {
            let recommendation = model.rendererRecommendation(for: game)
            Button { propertiesGame = game } label: {
                Text(recommendation.summary).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle)
            }.buttonStyle(.plain).help(recommendation.detail)
                .accessibilityLabel("Graphics for \(game.name): \(recommendation.summary)")
        }
    }

    private func gameState(_ game: GameInstallation?) -> String {
        if let session = session(for: game) {
            switch session.state {
            case "requested": return "Opening…"
            case "unknown": return "Status unknown"
            default: return session.state.capitalized
            }
        }
        return game != nil ? "Installed" : model.steamInstalled ? "Ready to install" : "Steam setup required"
    }

    @ViewBuilder private func gameAction(_ game: GameInstallation?) -> some View {
        if let game {
            let tracked = session(for: game)
            Button { model.requestLaunch(game) } label: {
                Label(tracked == nil ? "Play" : tracked?.state == "running" ? "In game" : "Sent", systemImage: "play.fill")
                    .lineLimit(1).fixedSize().frame(minWidth: 48)
            }.buttonStyle(PrimaryButton()).disabled(model.busy || model.currentSession != nil)
                .accessibilityLabel("Play \(game.name)")
        } else if !model.steamInstalled {
            Button(model.setupStep > 0 ? "Continue setup" : "Set up Steam") { model.setup() }
                .buttonStyle(PrimaryButton()).disabled(model.busy || model.host?.supported != true)
        } else if let recipe = model.recipes.first(where: { $0.appID == "11020" }) {
            Button("Install demo") { model.install(recipe) }.buttonStyle(PrimaryButton()).disabled(model.busy)
        }
    }

    private func manageMenu(_ game: GameInstallation, compact: Bool = false) -> some View {
        Group {
            if renderingSnapshot { managementLabel(compact: compact) }
            else {
                Menu {
                    Button("Graphics recommendation…") { propertiesGame = game }
                    Button("Game properties…") {
                        if game.store != .steam { propertiesGame = game }
                        else { model.manage(game, command: .gameProperties) }
                    }
                    if game.store != .steam { Button("Manage in \(game.managementStore.title)…") { model.manage(game, command: .gameProperties) } }
                    Button("Show game files") { model.showGameFiles(game) }
                    Button("Mods & files…") { moddingGame = game }
                    Button(game.store != .steam ? "Verify files in \(game.managementStore.title)…" : "Verify game files…") { model.manage(game, command: .verifyGame) }.disabled(model.currentSession != nil)
                    Divider()
                    Button(game.store != .steam ? "Uninstall in \(game.managementStore.title)…" : "Uninstall…", role: .destructive) { model.manage(game, command: .uninstallGame) }.disabled(model.currentSession != nil)
                } label: { managementLabel(compact: compact) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Manage \(game.name)").help("Manage \(game.name)")
            }
        }.disabled(model.busy)
    }

    private func gameProperties(_ game: GameInstallation) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name).font(.system(size: 22, weight: .medium))
                    Text(game.store.title).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("Done") { propertiesGame = nil }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
            }
            Rule()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Installed · " + (game.sizeBytes > 0 ? ByteCountFormatter.string(fromByteCount: game.sizeBytes, countStyle: .file) : "Size unavailable")).font(.system(size: 12))
                        Text(game.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button("Show game files") { model.showGameFiles(game) }.buttonStyle(SecondaryButton())
                    }
                    Rule()
                    let recommendation = model.rendererRecommendation(for: game)
                    Text(recommendation.summary).font(.system(size: 14, weight: .medium))
                    Text(recommendation.detail)
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    if game.store == .steam {
                        Text("Current renderer: " + (model.environment(for: game)?.profile.title ?? "Not configured"))
                            .font(.system(size: 12))
                        if let profile = recommendation.profile, model.runtime(for: game)?.manifest.supports(profile) != true {
                            Text("The selected runtime does not include this renderer. Import a runtime with the required graphics backend before applying it.")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        if let profile = recommendation.profile, model.environment(for: game)?.profile != profile {
                            Button("Use \(profile.title)") { model.changeProfile(profile, for: game) }.buttonStyle(SecondaryButton())
                                .disabled(model.busy || model.currentSession != nil || model.runtime(for: game)?.manifest.supports(profile) != true)
                            Text("Quit Windows games, apps and launchers first. This changes the renderer for games and apps in this Windows environment; other environments keep their settings.")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("Launcher managed: DXVK for DirectX 9 and DXMT for DirectX 10–11, when included in the runtime. The shared graphics setting does not change the launcher's renderer policy.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    if game.store == .steam && game.appID == "730" {
                        Text("60 FPS target · the old 720p preset upgrades once to 1600 × 900. Choose another resolution in CS2’s Video settings; later choices are preserved. The preset uses low scene detail, MSAA/AO off and dynamic shadows on, with FSR disabled for clarity. Metal presentation timing targets 60 FPS alongside the game’s frame cap. Fullscreen can raise render resolution. This is a target, not a guaranteed minimum.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("For updates, verification, and uninstall, use this game's management controls inside \(game.managementStore.title). The launcher owns download progress and confirmation dialogs.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Button("Manage in \(game.managementStore.title)…") { propertiesGame = nil; model.manage(game, command: .gameProperties) }.buttonStyle(SecondaryButton()).disabled(model.busy)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 520)
        }.padding(30).frame(width: 550).foregroundStyle(Palette.ink).background(Palette.canvas)
    }

    private func modding(_ game: GameInstallation) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mods & files").font(.system(size: 22, weight: .medium))
                    Text(game.name).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("Done") { moddingGame = nil }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
            }
            Rule()
            VStack(alignment: .leading, spacing: 10) {
                detailHeading("Manual mods")
                Text("Open the game folder and follow the mod's Windows installation instructions. Some games store mods, maps, or skins in Windows Documents instead.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Game folder") { moddingGame = nil; model.showGameFiles(game) }.buttonStyle(SecondaryButton())
                    Button("Windows Documents") { moddingGame = nil; model.showWindowsDocuments(for: game) }.buttonStyle(SecondaryButton())
                }
            }
            if game.store == .steam {
            VStack(alignment: .leading, spacing: 10) {
                detailHeading("Steam Workshop")
                Text("For games with Workshop support, subscribe to items in Windows Steam and let their downloads finish. Enable them inside the game if required.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Button("Open Steam") { moddingGame = nil; model.openSteam() }.buttonStyle(SecondaryButton())
            }
            }
            Rule()
            Text("Quit the game before changing files. Mods that need a Windows mod manager, DLL overrides, or additional software may need extra setup. Game verification and updates can replace modified files.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(30).frame(width: 540).foregroundStyle(Palette.ink).background(Palette.canvas)
    }

    @ViewBuilder private func managementLabel(compact: Bool) -> some View {
        if compact {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 32, height: 34)
                .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
        } else { menuLabel("Manage", icon: "ellipsis") }
    }

    private var settingsQuery: String {
        (previewSearch ?? settingsSearchText).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var settingsSections: Set<SettingsSection> {
        Set(SettingsSection.allCases.filter {
            !([.drive, .recovery].contains($0) && model.environment == nil) && $0.matches(settingsQuery)
        })
    }
    private var showAdvancedSettings: Bool { !settingsQuery.isEmpty || advancedExpanded || previewAdvanced }

    private var advancedHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Advanced").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                Text("Recovery, runtime, and diagnostics").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            if settingsQuery.isEmpty {
                Image(systemName: showAdvancedSettings ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
            }
        }.padding(22).contentShape(Rectangle())
    }

    private var settingsSearchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Palette.muted)
            if renderingSnapshot {
                Text(settingsQuery.isEmpty ? "Search settings" : settingsQuery)
                    .foregroundStyle(settingsQuery.isEmpty ? Palette.muted : Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Search settings", text: $settingsSearchText).textFieldStyle(.plain)
                    .focused($settingsSearchFocused).accessibilityLabel("Search settings")
                    .onExitCommand {
                        if settingsSearchText.isEmpty { settingsSearchFocused = false }
                        else { settingsSearchText = "" }
                    }
            }
            if !settingsQuery.isEmpty {
                Button { settingsSearchText = ""; settingsSearchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                }.buttonStyle(.plain).accessibilityLabel("Clear settings search").help("Clear search")
            }
        }.font(.system(size: 12)).padding(.horizontal, 11).frame(height: 34).frame(maxWidth: 420)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(settingsSearchFocused ? Palette.muted : Palette.line))
            .background {
                if !renderingSnapshot { SearchFocusDismissal(isFocused: settingsSearchFocused) { settingsSearchFocused = false } }
            }
            .help("Find settings by name or topic (⌘F)")
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 26) {
            if settingsSections.contains(.graphics) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("WINDOWS ENVIRONMENT")
                    VStack(alignment: .leading, spacing: 0) {
                        settingRow("Graphics renderer", detail: "Used by the default Windows environment. For other games, use their graphics recommendation. Quit its Windows software before changing it.") {
                            Group {
                                if renderingSnapshot { menuLabel(model.environment?.profile.title ?? "Not set up") }
                                else {
                                    Menu {
                                        ForEach(model.runtime?.manifest.graphicsProfiles ?? []) { profile in
                                            Button(profile.title) { model.changeProfile(profile) }
                                        }
                                    } label: { menuLabel(model.environment?.profile.title ?? "Not set up") }
                                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                }
                            }.disabled(model.busy || model.environment == nil)
                        }
                        Rule().padding(.horizontal, 22)
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach([GraphicsProfile.combined, .metal, .performance, .legacy]) { profile in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(profile.title) · \(profile.subtitle)").font(.system(size: 11, weight: .medium))
                                    Text(profile.explanation).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                                    if let runtime = model.runtime, !runtime.manifest.supports(profile) {
                                        Text("Not available in this runtime").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    }
                                }
                            }
                            Text("Epic and Ubisoft manage their own renderer combination. DirectX 12 is not supported by these modes. Change resolution, visual quality, and frame limits inside each app.")
                                .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }.padding(22)
                    }.panel()
                }
            }
            if settingsSections.contains(.drive) {
                VStack(spacing: 0) {
                    settingRow("Windows C: drive", detail: "Installed apps, imported files, and Windows user folders.") {
                        Button("Open in Finder") { model.showWindowsDrive() }.buttonStyle(SecondaryButton())
                    }
                }.panel()
            }
            if settingsSections.contains(.steam) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("WINDOWS STEAM")
                    VStack(spacing: 0) {
                        settingRow("Steam client", detail: "Your account, library, and store.") {
                            if model.steamInstalled {
                                Button("Open") { model.openSteam() }.buttonStyle(SecondaryButton())
                                Button("Quit") { model.stop(force: false) }.buttonStyle(SecondaryButton())
                            } else {
                                Button("Set up") { model.setup() }.buttonStyle(SecondaryButton()).disabled(model.host?.supported != true)
                            }
                        }
                        if model.steamInstalled {
                            Rule().padding(.horizontal, 22)
                            settingRow("Downloaded games", detail: "Open the installed games folder in Finder.") {
                                Button { model.openDownloadsFolder() } label: { Label("Open download folder", systemImage: "folder") }.buttonStyle(SecondaryButton())
                            }
                            Rule().padding(.horizontal, 22)
                            settingRow("Steam Downloads", detail: "Manage download progress and updates in Steam.") {
                                Button { model.openSteamDownloads() } label: { Label("Steam Downloads", systemImage: "arrow.up.right") }.buttonStyle(SecondaryButton())
                            }
                        }
                    }.panel().disabled(model.busy)
                }
            }
            if settingsSections.contains(.epic) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("WINDOWS EPIC GAMES")
                    VStack(spacing: 0) {
                        settingRow("Epic Games Launcher", detail: "Your Epic account, library, and store.") {
                            Button(model.epicInstalled ? "Open Epic" : "Set up Epic") { model.openEpic() }.buttonStyle(SecondaryButton())
                        }
                        if model.epicInstalled {
                            Rule().padding(.horizontal, 22)
                            settingRow("Launch support", detail: "Installs Epic components needed by Play. Quit Windows games and launchers before repairing.") {
                                Button("Repair launch support") { model.repairEpicLaunchSupport() }.buttonStyle(SecondaryButton())
                            }
                            Rule().padding(.horizontal, 22)
                            settingRow("Graphics", detail: "DXMT handles DirectX 10–11; DXVK handles DirectX 9 when available. The launcher manages this combination.") {
                                Text("Managed").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                            Rule().padding(.horizontal, 22)
                            settingRow("Downloaded games", detail: "Default install folder. Each game's menu opens its actual files.") {
                                Button("Open download folder") { model.openEpicGamesFolder() }.buttonStyle(SecondaryButton())
                            }
                            Rule().padding(.horizontal, 22)
                            settingRow("Epic downloads", detail: "Open Epic, then use its Downloads control for progress and updates.") {
                                Button("Open Epic") { model.openEpicDownloads() }.buttonStyle(SecondaryButton())
                            }
                        }
                    }.panel().disabled(model.busy)
                }
            }
            if settingsSections.contains(.platforms) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("OTHER PLATFORMS")
                    VStack(spacing: 0) {
                        settingRow("Xbox Cloud Gaming", detail: "Stream supported titles in your browser. Account, plan, region, and controller requirements vary. These are not local downloads.") {
                            Link("Open Xbox Cloud", destination: URL(string: "https://www.xbox.com/play")!).buttonStyle(SecondaryButton())
                        }
                        Rule().padding(.horizontal, 22)
                        settingRow("Minecraft Bedrock", detail: "A local preview using its own WineGDK runtime and Microsoft sign-in. Requires an owned Windows edition; availability depends on the included backend.") {
                            Button("Open Minecraft…") { model.showingMinecraft = true }.buttonStyle(SecondaryButton())
                        }
                    }.panel()
                }
            }
            if settingsSections.contains(where: { $0.isAdvanced }) {
                VStack(spacing: 0) {
                    if settingsQuery.isEmpty {
                        Button { advancedExpanded.toggle() } label: { advancedHeader }
                            .buttonStyle(.plain).accessibilityValue(showAdvancedSettings ? "Expanded" : "Collapsed")
                    } else { advancedHeader.accessibilityAddTraits(.isHeader) }
                    if showAdvancedSettings { Rule(); advanced.frame(maxWidth: .infinity, alignment: .leading).padding(22) }
                }.panel()
            }
            if settingsSections.contains(.backups) || settingsSections.contains(.uninstall) {
                VStack(alignment: .leading, spacing: 0) {
                    if settingsSections.contains(.backups) {
                        settingRow("Backups", detail: "Manual only. Includes the default Windows environment and its games and apps.") {
                            HStack(spacing: 8) {
                                Button("Create backup…") { manualBackupConfirmation = true }
                                    .buttonStyle(SecondaryButton()).disabled(model.environment == nil)
                                Button("Clear backups…") { clearBackupsConfirmation = true }.buttonStyle(SecondaryButton())
                            }
                        }
                    }
                    if settingsSections.contains(.backups) && settingsSections.contains(.uninstall) { Rule().padding(.horizontal, 22) }
                    if settingsSections.contains(.uninstall) {
                        settingRow("Uninstall crossedover", detail: "Remove crossedover, Windows apps, games, saves, and app data.") {
                            Button("Uninstall…") { uninstallConfirmation = true }.buttonStyle(SecondaryButton())
                        }
                    }
                }.panel().disabled(model.busy)
            }
            if settingsSections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No settings found").font(.system(size: 16, weight: .medium))
                    Text("Try graphics, downloads, Minecraft, or backups.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Button("Clear search") { settingsSearchText = ""; settingsSearchFocused = true }
                        .buttonStyle(SecondaryButton())
                }.padding(.vertical, 32)
            }
            Text("crossedover \(AppVersion.current)").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 26) {
            if settingsSections.contains(.recovery), let environment = model.environment {
                VStack(alignment: .leading, spacing: 12) {
                    detailHeading("Recovery")
                    Text("Quit Steam, Epic, games, and Windows apps before restoring or repairing. Full environment backups are manual only; small copies of changed settings are kept for recovery.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { recoveryActions(environment) }
                        VStack(alignment: .leading, spacing: 8) { recoveryActions(environment) }
                    }.disabled(model.busy)
                    Button("Force quit environment…") { forceStopConfirmation = true }.buttonStyle(TextButton()).disabled(model.busy)
                }
            }
            if settingsSections.contains(.runtime) {
                if settingsSections.contains(.recovery) { Rule() }
                VStack(alignment: .leading, spacing: 12) {
                    detailHeading("Runtime")
                    Text(model.runtime?.manifest.name ?? "No runtime installed").font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    HStack(spacing: 8) {
                        Button("Import runtime…") { model.importRuntime() }.buttonStyle(SecondaryButton())
                        if model.bundledRuntime != nil && model.environment != nil {
                            Button("Use included runtime…") { pendingIncludedRuntime = true }.buttonStyle(SecondaryButton())
                        }
                        let alternatives = model.runtimes.filter { model.environment != nil && $0.id != model.environment?.runtimeID }
                        if !alternatives.isEmpty {
                            if renderingSnapshot { menuLabel("Switch runtime…") }
                            else {
                                Menu {
                                    ForEach(alternatives) { runtime in
                                        Button("Use \(runtime.manifest.name)") { pendingRuntime = runtime }
                                    }
                                } label: { menuLabel("Switch runtime…") }
                                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            }
                        }
                    }.disabled(model.busy)
                }
            }
            if settingsSections.contains(.support) {
                if settingsSections.contains(.recovery) || settingsSections.contains(.runtime) { Rule() }
                VStack(alignment: .leading, spacing: 12) {
                    detailHeading("Support")
                    HStack(spacing: 8) {
                        Button("Diagnostics…") { model.showDiagnostics() }.buttonStyle(SecondaryButton())
                        Button("Show backups") { NSWorkspace.shared.open(model.paths.backups) }.buttonStyle(SecondaryButton())
                    }
                    if let host = model.host {
                        Text("macOS \(host.osVersion) · \(host.memoryGB) GB memory").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        ForEach(host.blockers, id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                    }
                }
            }
        }
    }


    @ViewBuilder private func recoveryActions(_ environment: ManagedEnvironment) -> some View {
        Button("Restore…") { model.restoreBackup() }.buttonStyle(SecondaryButton())
        Button("Repair") { model.repair() }.buttonStyle(SecondaryButton())
        Button("Show files") { NSWorkspace.shared.open(model.paths.prefix(environment)) }.buttonStyle(SecondaryButton())
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("RECENT ACTIONS", trailing: "LATEST 20")
                VStack(spacing: 0) {
                    if model.operations.isEmpty { emptyRow("No activity yet", detail: "Actions will appear here as you use crossedover.") }
                    ForEach(Array(model.operations.prefix(20).enumerated()), id: \.element.id) { index, operation in
                        if index > 0 { Rule().padding(.horizontal, 22) }
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: operation.statusTitle == "Completed" ? "checkmark.circle" : operation.state == "failed" ? "exclamationmark.circle" : "clock")
                                .font(.system(size: 14)).foregroundStyle(Palette.muted).frame(width: 18).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(operation.kind).font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text(operation.statusTitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                if operation.detail != "Completed" {
                                    Text(operation.detail).font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                }
                                Text(operation.updatedAt, style: .relative).font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                        }.padding(22)
                    }
                }.panel()
            }
            if !model.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("GAME SESSIONS")
                    VStack(spacing: 0) {
                        ForEach(Array(model.sessions.prefix(15).enumerated()), id: \.element.id) { index, session in
                            if index > 0 { Rule().padding(.horizontal, 22) }
                            HStack {
                                Text(model.gameName(appID: session.appID)).font(.system(size: 12)).lineLimit(2)
                                Spacer()
                                Text(session.state.capitalized)
                                Text(session.startedAt, style: .date).frame(width: 85, alignment: .trailing)
                            }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(22)
                        }
                    }.panel()
                }
            }
        }
    }

    private func launchStatus(_ launch: (title: String, detail: String, waiting: Bool)) -> some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 14) {
                if launch.waiting {
                    if renderingSnapshot { Image(systemName: "arrow.triangle.2.circlepath").frame(width: 16) }
                    else { ProgressView().controlSize(.small).frame(width: 16) }
                } else {
                    Image(systemName: "gamecontroller").frame(width: 16).foregroundStyle(Palette.muted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(launch.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(launch.detail).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
                Button(model.bedrockActive ? "Stop Minecraft" : "Stop & close Windows") {
                    if model.bedrockActive { model.stopMinecraft() } else { model.stopLaunchAndCloseWindows() }
                }
                    .buttonStyle(SecondaryButton()).disabled(model.stoppingWindows || model.bedrockStopping)
                    .help(model.bedrockActive ? "Stops only the separate Minecraft session. Unsaved progress may be lost." : "Stops this launch and closes all crossedover Windows games, apps, and launchers. Unsaved progress may be lost.")
            }.padding(.horizontal, 26).padding(.vertical, 14)
        }.background(Palette.surface)
    }

    private var status: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 12) {
                if model.busy {
                    if renderingSnapshot { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13)).frame(width: 16) }
                    else { ProgressView().controlSize(.mini).tint(Palette.ink) }
                }
                else { Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Palette.muted) }
                Text(model.busy ? model.progress : model.notice ?? "").font(.system(size: 11)).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.updatesFrequently)
                if model.busy { Button("Cancel") { model.cancel() }.buttonStyle(TextButton()) }
                else {
                    Button { model.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 24, height: 24) }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Dismiss message")
                }
            }.padding(.horizontal, 26).padding(.vertical, 16)
        }.background(Palette.surface)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Diagnostics").font(.system(size: 22, weight: .medium))
            Text("Review before sharing. Steam sign-in files and raw logs are excluded.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            ScrollView {
                Text(model.diagnostics ?? "").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.panel()
            HStack {
                Button("Close") { model.diagnostics = nil }.buttonStyle(SecondaryButton())
                Spacer()
                Button("Save report…") { model.exportDiagnostics(model.diagnostics ?? "") }.buttonStyle(PrimaryButton())
            }
        }.padding(32).frame(width: 680, height: 520).foregroundStyle(Palette.ink).background(Palette.canvas).preferredColorScheme(.dark)
    }

    private func settingRow<Content: View>(_ label: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) { content() }.fixedSize()
        }.padding(22)
    }

    private func menuLabel(_ title: String, icon: String = "chevron.down") -> some View {
        HStack(spacing: 12) {
            Text(title)
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
        }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink.opacity(0.85))
            .padding(.horizontal, 12).frame(height: 34)
            .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
    }
    private func sectionLabel(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing { Text(trailing) }
        }.font(.system(size: 9, weight: .medium)).tracking(1.15).foregroundStyle(Palette.muted)
    }
    private func detailHeading(_ title: String) -> some View { Text(title).font(.system(size: 12, weight: .medium)) }
    private func emptyRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared by the sidebar and macOS menu bar so launcher availability stays consistent.
struct GameLauncherActions: View {
    @Bindable var model: AppModel

    var body: some View {
        Button(model.steamInstalled ? "Open Steam" : "Set up Steam…") { model.openSteam() }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(model.busy || (!model.steamInstalled && model.host?.supported != true))
        Button(model.epicInstalled ? "Open Epic Games" : "Set up Epic Games…") { model.openEpic() }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(model.busy || (!model.epicInstalled && model.host?.supported != true))
        Divider()
        Button(model.ubisoftInstalled ? "Open Ubisoft Connect" : "Ubisoft Connect (not installed)") { model.openUbisoft() }
            .disabled(model.busy || !model.ubisoftInstalled)
            .help("Supported Epic games install Ubisoft Connect during their initial setup in Epic.")
        Divider()
        Button("Minecraft Bedrock…") { model.showingMinecraft = true }
            .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}

private struct LibrarySearchKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

/// Observe clicks without consuming them, so buttons and menus still work on
/// the first click. The search field and its clear button share this region.
private struct SearchFocusDismissal: NSViewRepresentable {
    var isFocused: Bool
    var dismiss: () -> Void

    func makeNSView(context: Context) -> ClickRegion { ClickRegion() }
    func updateNSView(_ view: ClickRegion, context: Context) {
        view.update(isFocused: isFocused, dismiss: dismiss)
    }
    static func dismantleNSView(_ view: ClickRegion, coordinator: ()) { view.stopMonitoring() }

    final class ClickRegion: NSView {
        private var monitor: Any?
        private var dismiss: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func update(isFocused: Bool, dismiss: @escaping () -> Void) {
            self.dismiss = dismiss
            guard isFocused else { stopMonitoring(); return }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                if !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.dismiss?()
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            dismiss = nil
        }
    }
}

extension FocusedValues {
    var librarySearch: (@MainActor () -> Void)? {
        get { self[LibrarySearchKey.self] }
        set { self[LibrarySearchKey.self] = newValue }
    }
}

private struct Rule: View {
    var body: some View { Rectangle().fill(Palette.line).frame(height: 1).accessibilityHidden(true) }
}
private extension View {
    func panel() -> some View {
        self.background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
    }
}

private struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(white: 0.08))
            .padding(.horizontal, 18).frame(height: 34)
            .background(Palette.ink.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.35).contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
private struct SecondaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink.opacity(0.85))
            .padding(.horizontal, 12).frame(height: 34)
            .background(Color.white.opacity(configuration.isPressed ? 0.09 : 0.02), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
            .opacity(enabled ? 1 : 0.35).contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
private struct TextButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11)).foregroundStyle(Palette.ink.opacity(configuration.isPressed ? 0.5 : 0.75))
            .padding(.vertical, 5).contentShape(Rectangle()).opacity(enabled ? 1 : 0.35)
    }
}

private struct WindowsAppDraft: Identifiable {
    let id = UUID()
    var url: URL
    var category: LibraryCategory
    var app: WindowsApp? = nil
}

private struct WindowsAppEditor: View {
    @Bindable var model: AppModel
    let draft: WindowsAppDraft
    var renderingSnapshot = false
    let dismiss: () -> Void
    @State private var url: URL
    @State private var name: String
    @State private var category: LibraryCategory
    @State private var includeFolder = false

    init(model: AppModel, draft: WindowsAppDraft, renderingSnapshot: Bool = false, dismiss: @escaping () -> Void) {
        self.model = model; self.draft = draft; self.renderingSnapshot = renderingSnapshot; self.dismiss = dismiss
        _url = State(initialValue: draft.url)
        _name = State(initialValue: draft.app?.name ?? draft.url.deletingPathExtension().lastPathComponent)
        _category = State(initialValue: draft.category)
    }
    private var alreadyInWindows: Bool {
        guard let environment = draft.app.flatMap({ model.environment(id: $0.environmentID) }) ?? model.environment else { return false }
        return url.standardizedFileURL.path.hasPrefix(model.paths.prefix(environment).appendingPathComponent("drive_c").standardizedFileURL.path + "/")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(draft.app == nil ? "Add to your library" : "Edit Windows app").font(.system(size: 22, weight: .medium))
                Text("A local Windows app, with a place on your Mac.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Rule()
            VStack(alignment: .leading, spacing: 8) {
                Text("Name").font(.system(size: 12, weight: .medium))
                if renderingSnapshot {
                    Text(name).font(.system(size: 12)).padding(7).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.line))
                } else { TextField("App name", text: $name).textFieldStyle(.roundedBorder) }
            }
            if renderingSnapshot {
                HStack {
                    Text("Library").font(.system(size: 12))
                    Spacer()
                    ForEach(LibraryCategory.allCases) { item in
                        Text(item.title).font(.system(size: 12)).padding(.horizontal, 24).padding(.vertical, 6)
                            .background(category == item ? Palette.line : Palette.surface, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            } else {
                Picker("Library", selection: $category) {
                    ForEach(LibraryCategory.allCases) { category in Text(category.title).tag(category) }
                }.pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Executable").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Choose…") {
                        if let selected = model.chooseWindowsExecutable(for: draft.app) { url = selected; includeFolder = false }
                    }.buttonStyle(SecondaryButton())
                }
                Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(3).textSelection(.enabled)
                if !alreadyInWindows {
                    if renderingSnapshot {
                        Label("Include files from the containing folder", systemImage: "square").font(.system(size: 12))
                    } else {
                        Toggle("Include files from the containing folder", isOn: $includeFolder).toggleStyle(.checkbox).font(.system(size: 12))
                    }
                    Text(includeFolder ? "Copies everything in “\(url.deletingLastPathComponent().lastPathComponent)”, including subfolders. Choose a folder containing only this app." : "Copies this .exe only. Enable the folder option for portable apps or installers that need nearby DLLs, assets, or data files.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Already inside the Windows C: drive. Its files are used in place.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            Rule()
            Text("Nothing is uploaded. Files already in the Windows C: drive are used in place. Apps run with your Mac user permissions; add software you trust. Compatibility varies.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Text("Using an installer? Run it first, then choose Edit app / choose executable on the card and select the installed program in C:.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", action: dismiss).buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Spacer()
                Button(draft.app == nil ? "Add to library" : "Save") {
                    model.addWindowsApp(url, name: name, category: category, includeFolder: includeFolder, replacing: draft.app)
                    dismiss()
                }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            }
        }.padding(30).frame(width: 520).foregroundStyle(Palette.ink).background(Palette.canvas).preferredColorScheme(.dark)
    }
}

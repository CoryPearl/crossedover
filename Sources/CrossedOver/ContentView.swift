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

struct ContentView: View {
    @Bindable var model: AppModel
    var renderingSnapshot = false
    var previewAdvanced = false
    var previewLibraryMode: String? = nil
    var previewSearch: String? = nil
    @AppStorage("libraryPresentation") private var libraryPresentation = "grid"
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var advancedExpanded = false
    @State private var forceStopConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                if renderingSnapshot {
                    Color.clear.overlay(alignment: .topLeading) {
                        page.fixedSize(horizontal: false, vertical: true)
                    }.clipped()
                } else {
                    ScrollView { page.frame(maxWidth: .infinity, alignment: .topLeading) }
                }
                if model.busy || model.notice != nil { status }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Palette.ink).background(Palette.canvas).tint(Palette.ink)
        .ignoresSafeArea(.container, edges: .top)
        .focusedSceneValue(\.librarySearch, {
            model.selectedPage = "library"
            searchFocused = true
        })
        .alert("Couldn't complete the action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
            Button("View activity") { model.selectedPage = "activity"; model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Restart Steam to change graphics?", isPresented: Binding(get: { model.pendingGame != nil }, set: { if !$0 { model.pendingGame = nil } }), titleVisibility: .visible) {
            if let game = model.pendingGame { Button("Restart and play") { model.launch(game, restart: true) } }
            Button("Cancel", role: .cancel) { model.pendingGame = nil }
        } message: { Text("Close any running game first. Steam downloads may pause during the restart.") }
        .confirmationDialog("Force quit the Windows environment?", isPresented: $forceStopConfirmation, titleVisibility: .visible) {
            Button("Force quit", role: .destructive) { model.stop(force: true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Unsaved game progress may be lost.") }
        .sheet(isPresented: Binding(get: { model.diagnostics != nil }, set: { if !$0 { model.diagnostics = nil } })) { diagnostics }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 19, weight: .medium))
                Text("crossedover").font(.system(size: 14, weight: .semibold)).tracking(-0.25)
            }.padding(.horizontal, 20).padding(.top, 54).padding(.bottom, 36)
            VStack(spacing: 5) {
                navigation("Library", icon: "square.grid.2x2", page: "library")
                navigation("Settings", icon: "slider.horizontal.3", page: "settings")
            }.padding(.horizontal, 12)
            Spacer(minLength: 36)
            navigation("Activity", icon: "clock.arrow.circlepath", page: "activity").padding(.horizontal, 12)
            Rule().padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 10) {
                Button { model.openSteam() } label: {
                    HStack {
                        Text(model.steamInstalled ? "Open Steam" : "Set up Steam")
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(SecondaryButton()).disabled(model.busy || (!model.steamInstalled && model.host?.supported != true))
                    .help("Open the Windows Steam client")
                Text("Windows client").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 20)
            Text("VERSION \(AppVersion.current)").font(.system(size: 9, weight: .medium)).tracking(1.2)
                .foregroundStyle(Palette.muted.opacity(0.7)).padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 24)
        }.frame(width: 196).frame(maxHeight: .infinity).background(Palette.sidebar)
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
            case "settings": settings.frame(maxWidth: 940, alignment: .leading)
            case "activity": activity
            default: library
            }
        }.padding(.horizontal, 32).padding(.top, 46).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.selectedPage == "settings" ? "Settings" : model.selectedPage == "activity" ? "Activity" : "Library")
                        .font(.system(size: 25, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text(model.selectedPage == "settings" ? "Steam and game preferences." : model.selectedPage == "activity" ? "Recent actions and game sessions." : "Your Windows games, on Mac.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if model.selectedPage == "library" {
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise").frame(width: 12) }
                        .buttonStyle(SecondaryButton()).disabled(model.busy).help("Refresh library (⌘R)").accessibilityLabel("Refresh library")
                }
            }
            Rule()
        }
    }

    private var library: some View {
        let games = filteredGames
        return VStack(alignment: .leading, spacing: 18) {
            libraryToolbar
            sectionLabel(model.games.isEmpty ? "GET STARTED" : "INSTALLED GAMES",
                         trailing: model.games.isEmpty ? nil : libraryCount)
            if model.games.isEmpty {
                gameCard(nil).frame(maxWidth: 320)
                if model.steamInstalled {
                    Text("Games installed through Windows Steam appear here automatically.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            } else if games.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 24, weight: .light)).foregroundStyle(Palette.muted)
                    Text("No games found").font(.system(size: 15, weight: .medium))
                    Text("No titles match “\(query)”.").font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                    Button("Clear search") { searchText = ""; searchFocused = true }.buttonStyle(SecondaryButton())
                }.padding(.vertical, 64).padding(.horizontal, 24).frame(maxWidth: .infinity)
            } else if showingList {
                LazyVStack(spacing: 0) {
                    ForEach(games) { game in
                        gameRow(game)
                        if game.id != games.last?.id { Rule().padding(.horizontal, 16) }
                    }
                }.panel()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(games) { game in gameCard(game) }
                }
            }
            if let tracked = model.currentSession,
               !model.games.contains(where: { $0.appID == tracked.appID && $0.environmentID == tracked.environmentID }) {
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

    private var query: String { (previewSearch ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showingList: Bool { (previewLibraryMode ?? libraryPresentation) == "list" }
    private var filteredGames: [GameInstallation] {
        query.isEmpty ? model.games : model.games.filter { $0.name.localizedStandardContains(query) }
    }
    private var libraryCount: String {
        let count = filteredGames.count
        return query.isEmpty ? "\(count) \(count == 1 ? "GAME" : "GAMES")" : "\(count) OF \(model.games.count) GAMES"
    }

    private var libraryToolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Palette.muted)
                if renderingSnapshot {
                    Text(query.isEmpty ? "Search games" : query).foregroundStyle(query.isEmpty ? Palette.muted : Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Search games", text: $searchText).textFieldStyle(.plain)
                        .focused($searchFocused).accessibilityLabel("Search games")
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
                .background(SearchFocusDismissal(isFocused: searchFocused) { searchFocused = false })
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                presentationButton("grid", title: "Grid view", symbol: "square.grid.2x2")
                presentationButton("list", title: "List view", symbol: "list.bullet")
            }.padding(3).background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
        }
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
                    Text(gameState(game) + (game.sizeBytes > 0 ? " · " + ByteCountFormatter.string(fromByteCount: game.sizeBytes, countStyle: .file) : ""))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
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
              session.appID == game.appID, session.environmentID == game.environmentID else { return nil }
        return session
    }

    private func gameCard(_ game: GameInstallation?) -> some View {
        VStack(spacing: 0) {
            artwork(game).frame(height: 112)
            Rule()
            gameDetails(game).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            Rule()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.muted).frame(width: 5, height: 5)
                        Text(gameState(game)).font(.system(size: 11, weight: .medium)).lineLimit(1).help(gameState(game))
                    }
                    if let game, session(for: game) == nil, game.sizeBytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: game.sizeBytes, countStyle: .file))
                            .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1).help("Space used on disk")
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
        let isDemo = game == nil || game?.appID == "11020"
        let image = isDemo ? model.trackManiaLogo ?? game.flatMap { model.artwork(for: $0) } : game.flatMap { model.artwork(for: $0) }
        return ZStack {
            (isDemo ? Color(white: 0.85) : Palette.sidebar)
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(.horizontal, compact ? 8 : 22).padding(.vertical, compact ? 8 : 18)
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

    private func gameDetails(_ game: GameInstallation?) -> some View {
        let isDemo = game == nil || game?.appID == "11020"
        let experimental = game.flatMap { model.recipe(for: $0) }?.status == "experimental"
        return VStack(alignment: .leading, spacing: 0) {
            Text(isDemo ? "DEMO" : experimental ? "EXPERIMENTAL" : "COMPATIBILITY UNTESTED").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.muted)
                .padding(.bottom, 10)
            Text(isDemo ? "TrackMania" : game?.name ?? "Windows game")
                .font(.system(size: 17, weight: .medium)).tracking(-0.3).lineLimit(2)
                .help(game?.name ?? "TrackMania Nations Forever")
            if isDemo {
                Text("Nations Forever").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 3)
            }
        }.frame(height: 66, alignment: .topLeading)
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
                    Button("Game properties…") { model.manage(game, command: .gameProperties) }
                    Button("Show game files") { model.showGameFiles(game) }
                    Button("Verify game files…") { model.manage(game, command: .verifyGame) }.disabled(model.currentSession != nil)
                    Divider()
                    Button("Uninstall…", role: .destructive) { model.manage(game, command: .uninstallGame) }.disabled(model.currentSession != nil)
                } label: { managementLabel(compact: compact) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Manage \(game.name)").help("Manage \(game.name)")
            }
        }.disabled(model.busy)
    }

    @ViewBuilder private func managementLabel(compact: Bool) -> some View {
        if compact {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 32, height: 34)
                .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
        } else { menuLabel("Manage", icon: "ellipsis") }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("GAME EXPERIENCE")
                settingRow("Graphics", detail: "Quit Steam before changing the graphics profile.") {
                    Group {
                        if renderingSnapshot { menuLabel(model.environment?.profile.title ?? "Not set up") }
                        else {
                            Menu {
                                ForEach((model.runtime?.manifest.profiles ?? []).filter { $0 != .metal }) { profile in
                                    Button(profile.title) { model.changeProfile(profile) }
                                }
                            } label: { menuLabel(model.environment?.profile.title ?? "Not set up") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        }
                    }.disabled(model.busy || model.environment == nil)
                }.panel()
            }
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
                        settingRow("Downloads", detail: "Manage installs and updates in Steam.") {
                            Button { model.openDownloads() } label: { Label("Open", systemImage: "arrow.up.right") }.buttonStyle(SecondaryButton())
                        }
                    }
                }.panel().disabled(model.busy)
            }
            VStack(spacing: 0) {
                Button { advancedExpanded.toggle() } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Advanced").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                            Text("Recovery, runtime, and diagnostics").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: advancedExpanded || previewAdvanced ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                    }.padding(22).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(advancedExpanded || previewAdvanced ? "Expanded" : "Collapsed")
                if advancedExpanded || previewAdvanced { Rule(); advanced.padding(22) }
            }.panel()
            Text("crossedover \(AppVersion.current)").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let environment = model.environment {
                VStack(alignment: .leading, spacing: 12) {
                    detailHeading("Recovery")
                    Text("Quit Steam and all games before backing up or repairing.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { recoveryActions(environment) }
                        VStack(alignment: .leading, spacing: 8) { recoveryActions(environment) }
                    }.disabled(model.busy)
                    Button("Force quit environment…") { forceStopConfirmation = true }.buttonStyle(TextButton()).disabled(model.busy)
                }
                Rule()
            }
            VStack(alignment: .leading, spacing: 12) {
                detailHeading("Runtime")
                Text(model.runtime?.manifest.name ?? "No runtime installed").font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("Import runtime…") { model.importRuntime() }.buttonStyle(SecondaryButton())
                    let alternatives = model.runtimes.filter { model.environment != nil && $0.id != model.environment?.runtimeID }
                    if !alternatives.isEmpty {
                        if renderingSnapshot { menuLabel("Switch runtime…") }
                        else {
                            Menu {
                                ForEach(alternatives) { runtime in
                                    Button("Back up and use \(runtime.manifest.name)") { model.useRuntime(runtime) }
                                }
                            } label: { menuLabel("Switch runtime…") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        }
                    }
                }.disabled(model.busy)
            }
            Rule()
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

    @ViewBuilder private func recoveryActions(_ environment: ManagedEnvironment) -> some View {
        Button("Back up") { model.backup() }.buttonStyle(SecondaryButton())
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
                            Image(systemName: operation.state == "completed" ? "checkmark.circle" : operation.state == "failed" ? "exclamationmark.circle" : "clock")
                                .font(.system(size: 14)).foregroundStyle(Palette.muted).frame(width: 18).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(operation.kind).font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text(operation.state.capitalized).font(.system(size: 10)).foregroundStyle(Palette.muted)
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

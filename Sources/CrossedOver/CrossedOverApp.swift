import AppKit
import Sparkle
import SwiftUI
import CrossedOverCore

@main @MainActor enum EntryPoint {
    static func main() async {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), index + 1 < CommandLine.arguments.count {
            do {
                // Preview reads real library metadata without starting operations
                // or changing interrupted-operation records.
                let model = try AppModel(recoverInterruptedOperations: false)
                model.runtimes = try await model.runtimeManager.installed()
                model.environment = try model.store.all(ManagedEnvironment.self, kind: "environment").first
                if let environment = model.environment {
                    model.games = GameLibrary.discover(environment: environment, prefix: model.paths.prefix(environment))
                }
                model.windowsApps = try model.store.all(WindowsApp.self, kind: "windowsApp")
                model.windowsRuns = try model.store.all(WindowsAppRun.self, kind: "windowsRun").sorted { $0.startedAt > $1.startedAt }
                if let fixture = CommandLine.arguments.firstIndex(of: "--preview-apps"), fixture + 1 < CommandLine.arguments.count {
                    model.windowsApps = try JSONDecoder().decode([WindowsApp].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[fixture + 1])))
                }
                model.updateSteamLocation()
                model.operations = try model.store.all(OperationRecord.self, kind: "operation").sorted { $0.updatedAt > $1.updatedAt }
                model.sessions = try model.store.all(LaunchSession.self, kind: "session").sorted { $0.startedAt > $1.startedAt }
                if let fixture = CommandLine.arguments.firstIndex(of: "--preview-games"), fixture + 1 < CommandLine.arguments.count {
                    model.games = try JSONDecoder().decode([GameInstallation].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[fixture + 1])))
                }
                if let page = CommandLine.arguments.firstIndex(of: "--preview-page"), page + 1 < CommandLine.arguments.count {
                    model.selectedPage = CommandLine.arguments[page + 1]
                }
                let compact = CommandLine.arguments.contains("--compact-preview")
                if let stateIndex = CommandLine.arguments.firstIndex(of: "--preview-state"), stateIndex + 1 < CommandLine.arguments.count {
                    switch CommandLine.arguments[stateIndex + 1] {
                    case "setup": model.environment = nil; model.games = []
                    case "install": model.games = []
                    case "running", "unknown":
                        if let environment = model.environment {
                            model.currentSession = LaunchSession(appID: model.games.first?.sessionAppID ?? "11020", environmentID: environment.id, state: CommandLine.arguments[stateIndex + 1])
                        }
                    case "busy": model.busy = true; model.progress = "Preparing your game. This may take a moment…"
                    case "notice": model.notice = "Uninstall requested. Confirm in Steam; the library will update when it finishes."
                    default: break
                    }
                }
                let advanced = CommandLine.arguments.contains("--preview-advanced")
                let tall = CommandLine.arguments.contains("--tall-preview")
                func previewArgument(_ flag: String) -> String? {
                    guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
                    return CommandLine.arguments[index + 1]
                }
                let width = min(2560, max(840, Double(previewArgument("--preview-width") ?? "") ?? (compact ? 840 : 1100)))
                let height = min(1800, max(620, Double(previewArgument("--preview-height") ?? "") ?? (tall ? 1400 : compact ? 620 : 760)))
                await model.preparePreviewArtwork()
                let renderer = ImageRenderer(content: ContentView(model: model, renderingSnapshot: true, previewAdvanced: advanced,
                    previewLibraryMode: previewArgument("--preview-layout") ?? "grid", previewSearch: previewArgument("--preview-search"))
                    .environment(\.colorScheme, .dark).frame(width: width, height: height))
                renderer.scale = 2
                guard let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CrossedOverError.message("Could not render the SwiftUI preview.") }
                try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                return
            } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
        }
        CrossedOverApp.main()
    }
}

struct CrossedOverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @FocusedValue(\.librarySearch) private var librarySearch
    private let model: AppModel?
    private let startupError: String?
    init() {
        do { model = try AppModel(); startupError = nil }
        catch { model = nil; startupError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let model { ContentView(model: model)
                .frame(minWidth: 840, minHeight: 620)
                .preferredColorScheme(.dark)
                .task { await model.start() }
            } else {
                ContentUnavailableView("Couldn't open your library", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError ?? "The local data directory could not be opened. Your existing files have not been removed."))
                    .frame(width: 700, height: 420).preferredColorScheme(.dark)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { delegate.checkForUpdates() }
                    .disabled(!delegate.updatesConfigured)
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .textEditing) {
                Button("Search Library…") { librarySearch?() }.keyboardShortcut("f").disabled(librarySearch == nil)
            }
            CommandMenu("Epic") {
                Button("Open Windows Epic") { model?.openEpic() }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model == nil || model?.busy == true)
                Button("Epic Downloads") { model?.openEpicDownloads() }.disabled(model?.busy == true || model?.epicInstalled != true)
            }
            CommandMenu("Steam") {
                Button("Open Windows Steam") { model?.openSteam() }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model == nil || model?.busy == true)
                Button("Refresh Library") { Task { await model?.refresh() } }.keyboardShortcut("r").disabled(model == nil || model?.busy == true)
                Divider()
                Button("Close Windows Steam") { model?.stop(force: false) }.disabled(model?.busy == true || model?.environment == nil)
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var updater: SPUStandardUpdaterController?
    var updatesConfigured: Bool { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        if updatesConfigured { updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) }
    }
    func checkForUpdates() { updater?.checkForUpdates(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

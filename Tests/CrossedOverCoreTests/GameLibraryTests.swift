import Foundation
import Testing
@testable import CrossedOverCore

struct GameLibraryTests {
    @Test func fullscreenPoliciesPreserveShooterMouseCaptureAndOnlyTargetKnownGames() throws {
        let shooter = try #require(GameWindowingPolicy.registry(for: "730"))
        #expect(shooter.contains("AppDefaults\\cs2.exe\\Mac Driver"))
        #expect(shooter.contains("\"AllowCursorClipping\"=\"Y\""))
        #expect(shooter.contains("\"CursorClippingLocksWindows\"=\"N\""))
        #expect(shooter.contains("\"CursorClippingFollowsWindow\"=\"Y\""))
        #expect(shooter.contains("\"FullscreenIgnoreMaxSize\"=\"Y\""))
        #expect(shooter.contains("\"NativeFullscreen\"=\"Y\""))
        #expect(shooter.contains("\"CaptureDisplaysForFullscreen\"=\"N\""))
        #expect(shooter.contains("\"gameoverlayrenderer\"=-"))
        #expect(shooter.contains("\"gameoverlayrenderer64\"=-"))
        #expect(!shooter.contains("\"gameoverlayrenderer64\"=\"\""))
        #expect(!shooter.contains("TmForever.exe"))
        let demo = try #require(GameWindowingPolicy.registry(for: "11020"))
        #expect(demo.contains("AppDefaults\\TmForever.exe\\Mac Driver"))
        #expect(demo.contains("\"AllowCursorClipping\"=\"N\""))
        #expect(demo.contains("\"NativeFullscreen\"=\"N\""))
        #expect(demo.contains("\"CursorClippingFollowsWindow\"=\"N\""))
        #expect(demo.contains("\"gameoverlayrenderer64\"=\"\""))
        #expect(GameWindowingPolicy.registry(for: "99999") == nil)
    }
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CrossedOver-library-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func manifest(_ id: String, name: String, directory: String, flags: Int = 4, library: URL) throws {
        try FileManager.default.createDirectory(at: library.appendingPathComponent("steamapps/common/" + directory), withIntermediateDirectories: true)
        let content = "\"AppState\" { \"appid\" \"\(id)\" \"name\" \"\(name)\" \"installdir\" \"\(directory)\" \"StateFlags\" \"\(flags)\" \"SizeOnDisk\" \"12345\" }"
        try content.write(to: library.appendingPathComponent("steamapps/appmanifest_\(id).acf"), atomically: true, encoding: .utf8)
    }

    @Test func libraryDiscoversAllCompletedGamesAcrossManagedLibrariesAndRemovesUninstalls() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let environment = ManagedEnvironment(runtimeID: "fixture")
        let steam = root.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        let second = root.appendingPathComponent("drive_c/More Games")
        try manifest("11020", name: "TrackMania Nations Forever", directory: "TrackMania", library: steam)
        try manifest("730", name: "Counter-Strike 2", directory: "Counter-Strike Global Offensive", library: second)
        try manifest("42", name: "A future game", directory: "Future", library: steam)
        try manifest("43", name: "Downloading", directory: "Downloading", flags: 1026, library: steam)
        try manifest("228980", name: "Steamworks Common Redistributables", directory: "Steamworks Shared", library: steam)
        try "\"libraryfolders\" { \"1\" { \"path\" \"C:\\\\More Games\" } }".write(to: steam.appendingPathComponent("steamapps/libraryfolders.vdf"), atomically: true, encoding: .utf8)
        let cache = steam.appendingPathComponent("appcache/librarycache/730/content-hash")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data().write(to: cache.appendingPathComponent("header.jpg"))
        let discovery = SteamDiscovery()
        let games = try discovery.discover(environment: environment, prefix: root)
        #expect(games.map(\.appID) == ["42", "730", "11020"])
        #expect(games.allSatisfy { $0.environmentID == environment.id })
        #expect(games.first { $0.appID == "730" }?.artworkPath == cache.appendingPathComponent("header.jpg").path)
        let store = try Store(url: root.appendingPathComponent("fixture.sqlite"))
        try store.replaceGames(games, environmentID: environment.id)
        try FileManager.default.removeItem(at: second.appendingPathComponent("steamapps/appmanifest_730.acf"))
        try store.replaceGames(discovery.discover(environment: environment, prefix: root), environmentID: environment.id)
        #expect(try !store.all(GameInstallation.self, kind: "game").contains { $0.appID == "730" })
        #expect(try store.all(GameInstallation.self, kind: "game").count == 2)
    }

    @Test func unknownGamesUseInstalledExecutablesWithoutFollowingLinks() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let gameRoot = root.appendingPathComponent("game")
        try FileManager.default.createDirectory(at: gameRoot.appendingPathComponent("bin/win64"), withIntermediateDirectories: true)
        try Data().write(to: gameRoot.appendingPathComponent("bin/win64/CS2.EXE"))
        try Data().write(to: gameRoot.appendingPathComponent("launcher.exe"))
        try Data().write(to: gameRoot.appendingPathComponent("data.dll"))
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data().write(to: outside.appendingPathComponent("unrelated.exe"))
        try FileManager.default.createSymbolicLink(at: gameRoot.appendingPathComponent("linked"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: gameRoot.appendingPathComponent("linked.exe"), withDestinationURL: outside.appendingPathComponent("unrelated.exe"))
        let game = GameInstallation(appID: "730", environmentID: UUID(), name: "Counter-Strike 2", directory: gameRoot.path, sizeBytes: 0)
        let detected = try GameProcessDetection.executableNames(for: game, recipe: nil)
        #expect(detected == ["cs2.exe", "launcher.exe"])
        let recipe = GameRecipe(appID: "730", name: "Fixture", profile: .performance, executableNames: ["CS2.EXE"], status: "fixture", notes: "")
        #expect(try GameProcessDetection.executableNames(for: game, recipe: recipe) == ["cs2.exe"])
    }

    @Test func preferredEnvironmentKeepsRetainedGamesAndRoutesDuplicateToNewInstallation() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root); try paths.prepare()
        let store = try Store(url: root.appendingPathComponent("library.sqlite"))
        var old = ManagedEnvironment(runtimeID: "old-runtime")
        old.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!; old.state = "ready"
        var fresh = ManagedEnvironment(runtimeID: "new-runtime")
        fresh.id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!; fresh.state = "ready"
        for environment in [old, fresh] { try store.put(environment, kind: "environment", id: environment.id.uuidString) }
        let oldSteam = paths.prefix(old).appendingPathComponent("drive_c/Program Files (x86)/Steam")
        let newSteam = paths.prefix(fresh).appendingPathComponent("drive_c/Program Files (x86)/Steam")
        try manifest("730", name: "Counter-Strike 2", directory: "CS2", library: oldSteam)
        try manifest("730", name: "Counter-Strike 2", directory: "CS2", library: newSteam)
        try manifest("11020", name: "TrackMania", directory: "TrackMania", library: oldSteam)
        let epicFolder = paths.prefix(old).appendingPathComponent("drive_c/Epic Games/Brawlhalla")
        try FileManager.default.createDirectory(at: epicFolder, withIntermediateDirectories: true)
        try Data().write(to: epicFolder.appendingPathComponent("Brawlhalla.exe"))
        let manifests = paths.prefix(old).appendingPathComponent(EpicDiscovery.manifestsPath)
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        // Store-qualified identity must keep an Epic ID that collides with Steam.
        let item: [String: Any] = ["AppName": "730", "DisplayName": "Brawlhalla", "InstallLocation": #"C:\Epic Games\Brawlhalla"#,
                                   "LaunchExecutable": "Brawlhalla.exe", "InstallSize": 1]
        try JSONSerialization.data(withJSONObject: item).write(to: manifests.appendingPathComponent("brawl.item"))
        try store.setDefaultEnvironment(fresh.id)
        #expect(try store.libraryEnvironments().map(\.id) == [fresh.id, old.id])
        var games = GameLibrary.discover(environments: try store.libraryEnvironments(), paths: paths)
        #expect(games.count == 3)
        #expect(games.first { $0.store == .steam && $0.appID == "730" }?.environmentID == fresh.id)
        #expect(games.first { $0.store == .epic && $0.appID == "730" }?.environmentID == old.id)
        #expect(games.first { $0.appID == "11020" }?.environmentID == old.id)
        #expect(games.first { $0.appID == "11020" }?.directory.hasPrefix(paths.prefix(old).path) == true)
        // If the preferred copy is uninstalled, the retained installation remains available.
        try FileManager.default.removeItem(at: newSteam.appendingPathComponent("steamapps/appmanifest_730.acf"))
        games = GameLibrary.discover(environments: try store.libraryEnvironments(), paths: paths)
        #expect(games.first { $0.store == .steam && $0.appID == "730" }?.environmentID == old.id)
        #expect(try store.libraryEnvironments().first?.id == fresh.id)
        #expect(throws: CrossedOverError.self) { try store.setDefaultEnvironment(UUID()) }
    }
}

import Foundation
import Testing
@testable import CrossedOverCore

@Suite struct EpicTests {
    func fixture() throws -> (AppPaths, Store, ManagedEnvironment, InstalledRuntime) {
        let paths = AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("crossedover-epic-" + UUID().uuidString))
        try paths.prepare()
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        let runtimeRoot = paths.runtimes.appendingPathComponent("test-epic")
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        for name in ["wine", "wineserver", "steam-only"] {
            let script = name == "wine" ? "#!/bin/sh\ncase \"$1\" in */process-observer.exe) echo '[]';; *) /usr/bin/printf '%s\\n' \"$@\" \"$CROSSEDOVER_STEAM_BRANDING\" \"$WINEDLLPATH\";; esac\n" : "#!/bin/sh\nexit 0\n"
            try script.write(to: runtimeRoot.appendingPathComponent(name), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtimeRoot.appendingPathComponent(name).path)
        }
        for relative in ["observer.exe", "dxmt/x86_64-windows/d3d11.dll", "dxmt/x86_64-windows/dxgi.dll", "dxmt/x86_64-windows/winemetal.dll", "dxmt/i386-windows/winemetal.dll", "lib/wine/x86_64-unix/winemetal.so"] {
            let file = runtimeRoot.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        let manifest = RuntimeManifest(id: "test-epic", name: "Test Epic", version: "test", wineRelativePath: "wine", wineserverRelativePath: "wineserver", profiles: [.legacy, .metal], sourceURL: "https://example.invalid", sourceSHA256: String(repeating: "0", count: 64), observerRelativePath: "observer.exe", steamLoaderRelativePath: "steam-only")
        try JSONEncoder().encode(manifest).write(to: runtimeRoot.appendingPathComponent("runtime.json"))
        let runtime = InstalledRuntime(manifest: manifest, root: runtimeRoot)
        var environment = ManagedEnvironment(runtimeID: manifest.id); environment.state = "ready"
        let prefix = paths.prefix(environment)
        let launcher = prefix.appendingPathComponent("drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: launcher)
        try store.put(environment, kind: "environment", id: environment.id.uuidString)
        return (paths, store, environment, runtime)
    }
    @discardableResult func install(_ name: String = "Example", paths: AppPaths, environment: ManagedEnvironment, extra: [String: Any] = [:]) throws -> URL {
        let prefix = paths.prefix(environment)
        let manifests = prefix.appendingPathComponent(EpicDiscovery.manifestsPath)
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        let game = prefix.appendingPathComponent("drive_c/Program Files/Epic Games/" + name)
        try FileManager.default.createDirectory(at: game.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("owned test executable".utf8).write(to: game.appendingPathComponent("bin/game.exe"))
        var item: [String: Any] = ["AppName": name, "DisplayName": name + " game", "CatalogNamespace": "example-ns", "CatalogItemId": "catalog-item", "InstallLocation": "C:\\Program Files\\Epic Games\\" + name, "LaunchExecutable": "bin\\game.exe", "InstallSize": 4096, "bIsIncompleteInstall": false, "bIsDLC": false]
        item.merge(extra) { _, new in new }
        let file = manifests.appendingPathComponent(name + ".item")
        try JSONSerialization.data(withJSONObject: item).write(to: file)
        return file
    }
    @Test func discoversCompletedBaseGamesAndDistinguishesStoresAndLegacyRecords() throws {
        let (paths, _, environment, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try install("730", paths: paths, environment: environment)
        try install("downloading", paths: paths, environment: environment, extra: ["bIsIncompleteInstall": true])
        try install("DLC", paths: paths, environment: environment, extra: ["bIsDLC": true])
        try install("child", paths: paths, environment: environment, extra: ["MainGameAppName": "730"])
        try install("UE_5.5", paths: paths, environment: environment)
        let games = try EpicDiscovery().discover(environment: environment, prefix: paths.prefix(environment))
        #expect(games.count == 1)
        let epic = try #require(games.first)
        #expect(epic.store == .epic); #expect(epic.appID == "730"); #expect(epic.sizeBytes == 4096)
        #expect(epic.launchExecutable == "bin/game.exe")
        let legacy = "{\"appID\":\"730\",\"environmentID\":\"\(environment.id.uuidString)\",\"name\":\"Steam CS2\",\"directory\":\"/test\",\"sizeBytes\":0}"
        let steam = try JSONDecoder().decode(GameInstallation.self, from: Data(legacy.utf8))
        #expect(steam.store == .steam); #expect(steam.sessionAppID == "730")
        #expect(epic.sessionAppID == "epic:730"); #expect(epic.id != steam.id)
    }
    @Test func skipsUnsafeAndMissingInstallsAndRejectsEscapingManifestLinks() throws {
        let (paths, _, environment, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let prefix = paths.prefix(environment)
        for (name, fields): (String, [String: Any]) in [
            ("external", ["InstallLocation": "D:\\OtherLibrary"]), ("traversal", ["LaunchExecutable": "..\\..\\windows\\system32\\cmd.exe"]),
            ("absolute", ["LaunchExecutable": "/tmp/test.exe"]), ("missing", ["LaunchExecutable": "missing.exe"]),
            ("badId", ["AppName": "bad?x=launch&silent=false"])] {
            try install(name, paths: paths, environment: environment, extra: fields)
        }
        #expect(try EpicDiscovery().discover(environment: environment, prefix: prefix).isEmpty)
        for value in ["C:\\..\\..\\escape", "Z:\\Users\\someone", "https://example.invalid/app"] {
            #expect(throws: (any Error).self) { try EpicDiscovery.windowsPath(value, prefix: prefix) }
        }
        let outside = paths.root.appendingPathComponent("outside.item"); try Data("{}".utf8).write(to: outside)
        let link = prefix.appendingPathComponent(EpicDiscovery.manifestsPath + "/linked.item")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try EpicDiscovery().discover(environment: environment, prefix: prefix) }
    }
    @Test func providerFailurePreservesOnlyThatStoresCardsAndUninstallRemovesThem() throws {
        let (paths, store, environment, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let prefix = paths.prefix(environment)
        let file = try install(paths: paths, environment: environment)
        let prior = GameLibrary.discover(environment: environment, prefix: prefix)
        #expect(prior.count == 1)
        try Data("{ partial update".utf8).write(to: file)
        let steam = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps")
        try FileManager.default.createDirectory(at: steam.appendingPathComponent("common/Demo"), withIntermediateDirectories: true)
        try Data("\"AppState\" { \"appid\" \"11020\" \"name\" \"TrackMania\" \"installdir\" \"Demo\" \"StateFlags\" \"4\" }".utf8).write(to: steam.appendingPathComponent("appmanifest_11020.acf"))
        let merged = GameLibrary.discover(environment: environment, prefix: prefix, previous: prior)
        #expect(merged.count == 2); #expect(merged.contains { $0.store == .steam }); #expect(merged.contains { $0.store == .epic })
        try store.replaceGames(merged, environmentID: environment.id)
        #expect(try store.all(GameInstallation.self, kind: "game").count == 2)
        try FileManager.default.removeItem(at: file)
        let uninstalled = GameLibrary.discover(environment: environment, prefix: prefix, previous: merged)
        #expect(uninstalled.count == 1); #expect(uninstalled[0].store == .steam)
    }
    @Test func epicURIsAndGraphicsAreScopedAndCannotInjectActions() throws {
        let (paths, _, environment, runtime) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try install(paths: paths, environment: environment)
        var game = try #require(EpicDiscovery().discover(environment: environment, prefix: paths.prefix(environment)).first)
        #expect(try EpicService.launchURI(for: game) == "com.epicgames.launcher://apps/example-ns%3Acatalog-item%3AExample?action=launch&silent=false")
        for bad in ["id?x=y", "bad/../../app", "id&action=uninstall", "id\nother", "..", "", "游戏"] {
            game.appID = bad
            #expect(throws: (any Error).self) { try EpicService.launchURI(for: game) }
        }
        let variables = EpicService.environment(runtime: runtime, prefix: paths.prefix(environment), profile: .legacy)
        #expect(variables["WINEDLLPATH"] == runtime.root.appendingPathComponent("dxmt").path)
        #expect(variables["CROSSEDOVER_STEAM_BRANDING"] == nil)
        #expect(variables["CROSSEDOVER_STEAM_CEF_COMPAT"] == nil)
        let steam = WineConfiguration.environment(runtime: runtime, prefix: paths.prefix(environment), profile: .legacy)
        #expect(steam["WINEDLLPATH"] == nil); #expect(steam["CROSSEDOVER_STEAM_BRANDING"] == "1")
    }
    @Test func installerRequiresOfficialHTTPSAndCompoundWindowsInstaller() throws {
        let (paths, _, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let file = paths.downloads.appendingPathComponent("installer.msi")
        var data = Data([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]); data.append(Data(repeating: 0, count: 100_001))
        try data.write(to: file)
        try EpicService.validateInstaller(file, finalURL: URL(string: "https://epicgames-download1.akamaized.net/Builds/EpicInstaller.msi")!)
        for url in ["http://download.epicgames.com/Epic.msi", "https://epicgames.com.attacker.invalid/file.msi", "https://example.invalid/Epic.msi"] {
            #expect(throws: (any Error).self) { try EpicService.validateInstaller(file, finalURL: URL(string: url)!) }
        }
        try Data("<html>Download error</html>".utf8).write(to: file)
        #expect(throws: (any Error).self) { try EpicService.validateInstaller(file, finalURL: EpicService.installerURL) }
    }
    @Test func workerLaunchesThroughEpicWithoutSteamAndManagementUsesOnlyLibraryURI() throws {
        let (paths, _, environment, runtime) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try install(paths: paths, environment: environment)
        let file = paths.logs.appendingPathComponent(".launch-epic-test.json")
        let log = paths.logs.appendingPathComponent("epic-session.log")
        let launcher = try EpicService.executable(prefix: paths.prefix(environment))
        for command in [SupervisorRequest.Command.openEpic, .launchEpicGame, .epicProperties, .verifyEpicGame, .uninstallEpicGame, .epicDownloads] {
            try JSONEncoder().encode(SupervisorRequest(root: paths.root, environmentID: environment.id, command: command, appID: "Example")).write(to: file)
            try SupervisorEngine.runLaunchWorker(requestFile: file)
            let output = try String(contentsOf: log, encoding: .utf8)
            let uri = command == .launchEpicGame ? "com.epicgames.launcher://apps/example-ns%3Acatalog-item%3AExample?action=launch&silent=false" : EpicService.libraryURI
            let expected = command == .openEpic ? "-SkipBuildPatchPrereq" : uri
            #expect(output == launcher.path + "\n" + expected + "\n\n" + runtime.root.appendingPathComponent("dxmt").path + "\n")
        }
        for bad in [nil, "bad?cmd=run", "not-installed"] as [String?] {
            try JSONEncoder().encode(SupervisorRequest(root: paths.root, environmentID: environment.id, command: .launchEpicGame, appID: bad)).write(to: file)
            #expect(throws: (any Error).self) { try SupervisorEngine.runLaunchWorker(requestFile: file) }
        }
        #expect(!FileManager.default.fileExists(atPath: paths.logs.appendingPathComponent("wine-session.log").path))
    }
    @Test func runningEpicGameCannotBeVerifiedUninstalledOrRelaunched() async throws {
        let (paths, _, environment, runtime) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try install(paths: paths, environment: environment)
        try "#!/bin/sh\necho '[{\"pid\":42,\"executable\":\"game.exe\"}]'\n".write(to: runtime.wine, atomically: true, encoding: .utf8)
        for command in [SupervisorRequest.Command.verifyEpicGame, .uninstallEpicGame, .launchEpicGame] {
            do {
                _ = try await SupervisorEngine.execute(SupervisorRequest(root: paths.root, environmentID: environment.id, command: command, appID: "Example"))
                Issue.record("An active Epic game must not be managed or relaunched")
            } catch { #expect(error.localizedDescription.contains("is running")) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.logs.path).filter { $0.hasPrefix(".launch-") }.isEmpty)
    }
    @Test func coldEpicLaunchPrimesClientWithoutReusingTransferredPipe() throws {
        let (paths, _, environment, runtime) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try install(paths: paths, environment: environment)
        let file = paths.logs.appendingPathComponent(".launch-cold-epic.json")
        var request = SupervisorRequest(root: paths.root, environmentID: environment.id, command: .launchEpicGame, appID: "Example")
        request.primeEpic = true
        try JSONEncoder().encode(request).write(to: file)
        try SupervisorEngine.runLaunchWorker(requestFile: file)
        let output = try String(contentsOf: paths.logs.appendingPathComponent("epic-session.log"), encoding: .utf8)
        #expect(output.contains(try EpicService.launchURI(for: #require(EpicDiscovery().discover(environment: environment, prefix: paths.prefix(environment)).first))))
        #expect(!output.contains("-SkipBuildPatchPrereq"))
        #expect(output.contains(runtime.root.appendingPathComponent("dxmt").path))
    }
}

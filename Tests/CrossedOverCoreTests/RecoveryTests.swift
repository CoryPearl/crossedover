import Foundation
import Testing
@testable import CrossedOverCore

@Suite(.serialized) struct RecoveryTests {
    func fixture() throws -> (AppPaths, Store, ManagedEnvironment, InstalledRuntime) {
        let paths = AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("CrossedOver-recovery-" + UUID().uuidString))
        try paths.prepare()
        let store = try Store(url: paths.root.appendingPathComponent("test.sqlite"))
        let runtime = try makeRuntime(id: "original", exitStatus: 0, paths: paths)
        var environment = ManagedEnvironment(runtimeID: runtime.id); environment.state = "ready"
        try FileManager.default.createDirectory(at: paths.prefix(environment), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.prefix(environment).appendingPathComponent("drive_c"), withIntermediateDirectories: true)
        try Data("original save".utf8).write(to: paths.prefix(environment).appendingPathComponent("save.dat"))
        try store.put(environment, kind: "environment", id: environment.id.uuidString)
        return (paths, store, environment, runtime)
    }
    func makeRuntime(id: String, exitStatus: Int, paths: AppPaths) throws -> InstalledRuntime {
        let root = paths.runtimes.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, status) in [("wine", exitStatus), ("wineserver", 0)] {
            let url = root.appendingPathComponent(name)
            try "#!/bin/sh\nexit \(status)\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        let manifest = RuntimeManifest(id: id, name: id, version: "test", wineRelativePath: "wine", wineserverRelativePath: "wineserver", sourceURL: "https://example.invalid/source", sourceSHA256: String(repeating: "0", count: 64))
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("runtime.json"))
        return InstalledRuntime(manifest: manifest, root: root)
    }
    @Test func backupRestoreRestoresFilesAndRuntimeSelection() async throws {
        let (paths, store, environment, runtime) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let manager = EnvironmentManager(paths: paths, store: store)
        let backup = try await manager.backup(environment, runtime: runtime)
        let save = paths.prefix(environment).appendingPathComponent("save.dat")
        try Data("changed save".utf8).write(to: save)
        let restored = try await manager.restore(backup, current: environment, runtimeManager: RuntimeManager(paths: paths))
        #expect(restored.runtimeID == runtime.id)
        #expect(try String(contentsOf: save, encoding: .utf8) == "original save")
    }
    @Test func manualBackupRestoresExecutableCardsAndLegacyBackupClearsThem() async throws {
        let (paths, store, environment, runtime) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let app = WindowsApp(environmentID: environment.id, name: "Saved app", category: .apps, executablePath: "drive_c/App/app.exe")
        try store.put(app, kind: "windowsApp", id: app.id.uuidString)
        let manager = EnvironmentManager(paths: paths, store: store)
        let backup = try await manager.backup(environment, runtime: runtime)
        try store.remove(kind: "windowsApp", id: app.id.uuidString)
        let later = WindowsApp(environmentID: environment.id, name: "Newer game", category: .games, executablePath: "drive_c/new.exe")
        try store.put(later, kind: "windowsApp", id: later.id.uuidString)
        _ = try await manager.restore(backup, current: environment, runtimeManager: RuntimeManager(paths: paths))
        #expect(try store.all(WindowsApp.self, kind: "windowsApp") == [app])
        // A malformed metadata file must leave current files and cards intact.
        var escaping = app; escaping.executablePath = "drive_c/../../escape.exe"
        try JSONEncoder().encode([escaping]).write(to: backup.appendingPathComponent("windows-apps.json"))
        await #expect(throws: (any Error).self) { try await manager.restore(backup, current: environment, runtimeManager: RuntimeManager(paths: paths)) }
        #expect(try store.all(WindowsApp.self, kind: "windowsApp") == [app])
        try FileManager.default.removeItem(at: backup.appendingPathComponent("windows-apps.json"))
        _ = try await manager.restore(backup, current: environment, runtimeManager: RuntimeManager(paths: paths))
        #expect(try store.all(WindowsApp.self, kind: "windowsApp").isEmpty)
    }
    @Test func failedUpgradePreservesFilesRequiresRepairAndDoesNotBackUp() async throws {
        let (paths, store, environment, runtime) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let replacement = try makeRuntime(id: "broken", exitStatus: 1, paths: paths)
        let manager = EnvironmentManager(paths: paths, store: store)
        await #expect(throws: (any Error).self) { try await manager.migrate(environment, from: runtime, to: replacement) }
        #expect(try store.all(ManagedEnvironment.self, kind: "environment").first?.runtimeID == "original")
        #expect(try String(contentsOf: paths.prefix(environment).appendingPathComponent("save.dat"), encoding: .utf8) == "original save")
        #expect(try store.all(ManagedEnvironment.self, kind: "environment").first?.state == "needsRepair")
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path).isEmpty)
    }
    @Test func successfulUpgradeDoesNotBackUpAndRepairRecoversFailedUpgrade() async throws {
        let (paths, store, environment, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let manager = EnvironmentManager(paths: paths, store: store)
        let replacement = try makeRuntime(id: "replacement", exitStatus: 0, paths: paths)
        let upgraded = try await manager.migrate(environment, from: original, to: replacement)
        #expect(upgraded.runtimeID == replacement.id)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path).isEmpty)
        let broken = try makeRuntime(id: "broken", exitStatus: 1, paths: paths)
        await #expect(throws: (any Error).self) { try await manager.migrate(upgraded, from: replacement, to: broken) }
        let interrupted = try #require(store.all(ManagedEnvironment.self, kind: "environment").first)
        await #expect(throws: (any Error).self) {
            try await SupervisorEngine.execute(SupervisorRequest(root: paths.root, environmentID: interrupted.id, command: .openSteam))
        }
        for file in ["system.reg", "user.reg"] {
            try Data("WINE REGISTRY Version 2".utf8).write(to: paths.prefix(environment).appendingPathComponent(file))
        }
        let repaired = try await manager.repair(interrupted, runtime: replacement)
        #expect(repaired.state == "ready")
        #expect(try String(contentsOf: paths.prefix(environment).appendingPathComponent("save.dat"), encoding: .utf8) == "original save")
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path).isEmpty)
    }
    @Test func restoreRejectsAnUnmanagedBackup() async throws {
        let (paths, store, environment, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let manager = EnvironmentManager(paths: paths, store: store)
        await #expect(throws: (any Error).self) { try await manager.restore(paths.root, current: environment, runtimeManager: RuntimeManager(paths: paths)) }
    }
    @Test func unsupportedProfileCannotChangeMetadata() async throws {
        let (paths, store, environment, runtime) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let manager = EnvironmentManager(paths: paths, store: store)
        await #expect(throws: (any Error).self) { try await manager.setProfile(.metal, environment: environment, runtime: runtime) }
        #expect(try store.all(ManagedEnvironment.self, kind: "environment").first?.profile == .legacy)
    }
    @Test func performanceProfileInstallsBothArchitecturesAndCanReturnToLegacy() async throws {
        let (paths, store, environment, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var manifest = original.manifest
        manifest.profiles = [.legacy, .performance]; manifest.supportsMSync = true
        let runtime = InstalledRuntime(manifest: manifest, root: original.root)
        for directory in ["system32", "syswow64"] {
            try FileManager.default.createDirectory(at: paths.prefix(environment).appendingPathComponent("drive_c/windows/" + directory), withIntermediateDirectories: true)
        }
        for (path, data) in [
            ("dxvk/i386-windows/d3d9.dll", "native-32"),
            ("dxvk/x86_64-windows/d3d9.dll", "native-64"),
            ("dxvk/libMoltenVK.dylib", "test-library"),
            ("dxvk/dxvk.conf", "d3d9.maxAvailableMemory = 1024\n")
        ] {
            let file = runtime.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(data.utf8).write(to: file)
        }
        try RuntimeManager.validate(manifest, root: runtime.root, verifyHashes: false)
        let manager = EnvironmentManager(paths: paths, store: store)
        let fast = try await manager.setProfile(.performance, environment: environment, runtime: runtime)
        let prefix = paths.prefix(fast)
        #expect(try String(contentsOf: prefix.appendingPathComponent("drive_c/windows/syswow64/d3d9.dll"), encoding: .utf8) == "native-32")
        #expect(try String(contentsOf: prefix.appendingPathComponent("drive_c/windows/system32/d3d9.dll"), encoding: .utf8) == "native-64")
        #expect(FileManager.default.fileExists(atPath: prefix.appendingPathComponent("drive_c/crossedover/dxvk.conf").path))
        let fastVariables = WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: .performance)
        #expect(fastVariables["WINEDLLOVERRIDES"]?.contains("d3d9=n;") == true)
        #expect(fastVariables["DXVK_CONFIG_FILE"] == "C:\\crossedover\\dxvk.conf")
        #expect(fastVariables["WINEMSYNC"] == "1")
        #expect(fastVariables["CROSSEDOVER_STEAM_BRANDING"] == "1")
        #expect(fastVariables["WINE_D3D_CONFIG"] == "renderer=gdi")
        let legacy = try await manager.setProfile(.legacy, environment: fast, runtime: runtime)
        let legacyVariables = WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: legacy.profile)
        #expect(legacyVariables["WINEDLLOVERRIDES"]?.contains("d3d9=b;") == true)
        #expect(legacyVariables["DXVK_CONFIG_FILE"] == nil)
        #expect(legacyVariables["WINE_D3D_CONFIG"] == "renderer=gl")
        #expect(try store.all(ManagedEnvironment.self, kind: "environment").first?.profile == .legacy)
        try FileManager.default.removeItem(at: runtime.root.appendingPathComponent("dxvk/i386-windows/d3d9.dll"))
        #expect(throws: (any Error).self) { try RuntimeManager.validate(manifest, root: runtime.root, verifyHashes: false) }
    }
    @Test func synchronizationFallbackIsSharedAndSurvivesBackup() async throws {
        let (paths, store, environment, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var manifest = original.manifest; manifest.supportsMSync = true
        let runtime = InstalledRuntime(manifest: manifest, root: original.root)
        let manager = EnvironmentManager(paths: paths, store: store), prefix = paths.prefix(environment)
        try await manager.setServerSynchronization(true, environment: environment, runtime: runtime)
        for profile in GraphicsProfile.allCases {
            #expect(WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: profile)["WINEMSYNC"] == "0")
        }
        let backup = try await manager.backup(environment, runtime: original)
        try await manager.setServerSynchronization(false, environment: environment, runtime: runtime)
        #expect(WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: .legacy)["WINEMSYNC"] == "1")
        _ = try await manager.restore(backup, current: environment, runtimeManager: RuntimeManager(paths: paths))
        #expect(WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: .legacy)["WINEMSYNC"] == "0")
    }
    @Test func steamLoaderIsOptionalExecutableAndContained() throws {
        let (paths, _, _, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        #expect(original.steamLoader == original.wine)
        var manifest = original.manifest
        manifest.steamLoaderRelativePath = "crossedover Steam"
        #expect(throws: (any Error).self) { try RuntimeManager.validate(manifest, root: original.root, verifyHashes: false) }
        let loader = original.root.appendingPathComponent("crossedover Steam")
        try FileManager.default.copyItem(at: original.wine, to: loader)
        try RuntimeManager.validate(manifest, root: original.root, verifyHashes: false)
        #expect(InstalledRuntime(manifest: manifest, root: original.root).steamLoader == loader)
        manifest.steamLoaderRelativePath = "../outside"
        #expect(throws: (any Error).self) { try RuntimeManager.validate(manifest, root: original.root, verifyHashes: false) }
    }
    @Test func x87HelperIsValidatedAndOnlySelectedForPerformance() throws {
        let (paths, _, environment, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var manifest = original.manifest; manifest.x87RelativePath = "x87sidecar"
        #expect(throws: (any Error).self) { try RuntimeManager.validate(manifest, root: original.root, verifyHashes: false) }
        let helper = original.root.appendingPathComponent("x87sidecar")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        try RuntimeManager.validate(manifest, root: original.root, verifyHashes: false)
        let runtime = InstalledRuntime(manifest: manifest, root: original.root)
        #expect(WineConfiguration.environment(runtime: runtime, prefix: paths.prefix(environment), profile: .performance)["ROSETTA_X87_PATH"] == helper.path)
        #expect(WineConfiguration.environment(runtime: runtime, prefix: paths.prefix(environment), profile: .legacy)["ROSETTA_X87_PATH"] == nil)
        #expect(WineConfiguration.environment(runtime: runtime, prefix: paths.prefix(environment), profile: .metal)["ROSETTA_X87_PATH"] == nil)
        manifest.x87RelativePath = "../outside"
        #expect(throws: (any Error).self) { try RuntimeManager.validate(manifest, root: original.root, verifyHashes: false) }
    }
    @Test func oldManifestDoesNotEnableUnadvertisedSynchronization() throws {
        let (paths, _, _, runtime) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var document = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(runtime.manifest)) as? [String: Any])
        document.removeValue(forKey: "supportsMSync")
        let decoded = try JSONDecoder().decode(RuntimeManifest.self, from: JSONSerialization.data(withJSONObject: document))
        #expect(decoded.supportsMSync == nil)
        #expect(decoded.x87RelativePath == nil)
        let old = InstalledRuntime(manifest: decoded, root: runtime.root)
        #expect(WineConfiguration.environment(runtime: old, prefix: paths.root, profile: .legacy)["WINEMSYNC"] == "0")
    }
    @Test func launchWorkerCapsRuntimeOutput() async throws {
        let (paths, _, environment, runtime) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        try store.put(environment, kind: "environment", id: environment.id.uuidString)
        try "#!/bin/sh\n/usr/bin/head -c 1500000 /dev/zero\n".write(to: runtime.wine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtime.wine.path)
        let steam = paths.prefix(environment).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
        try FileManager.default.createDirectory(at: steam.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: steam)
        let file = paths.logs.appendingPathComponent(".launch-test.json")
        try JSONEncoder().encode(SupervisorRequest(root: paths.root, environmentID: environment.id, command: .openSteam)).write(to: file)
        try await Task.detached { try SupervisorEngine.runLaunchWorker(requestFile: file) }.value
        let attributes = try FileManager.default.attributesOfItem(atPath: paths.logs.appendingPathComponent("wine-session.log").path)
        #expect((attributes[.size] as? Int) == 1_048_576)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
    @Test func installationUsesOnlyTheManagedSteamAndValidAppIDs() async throws {
        let (paths, _, environment, runtime) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        try store.put(environment, kind: "environment", id: environment.id.uuidString)
        try "#!/bin/sh\n/usr/bin/printf '%s\\n' \"$@\"\n".write(to: runtime.wine, atomically: true, encoding: .utf8)
        let steam = paths.prefix(environment).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
        try FileManager.default.createDirectory(at: steam.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: steam)
        let file = paths.logs.appendingPathComponent(".launch-install.json")
        let request = SupervisorRequest(root: paths.root, environmentID: environment.id, command: .installGame, appID: "11020")
        try JSONEncoder().encode(request).write(to: file)
        try await Task.detached { try SupervisorEngine.runLaunchWorker(requestFile: file) }.value
        let log = paths.logs.appendingPathComponent("wine-session.log")
        #expect(try String(contentsOf: log, encoding: .utf8) == steam.path + "\n-cef-disable-gpu\nsteam://install/11020\n")
        let launch = SupervisorRequest(root: paths.root, environmentID: environment.id, command: .launchGame, appID: "11020")
        try JSONEncoder().encode(launch).write(to: file)
        try await Task.detached { try SupervisorEngine.runLaunchWorker(requestFile: file) }.value
        #expect(try String(contentsOf: log, encoding: .utf8) == steam.path + "\n-cef-disable-gpu\n-silent\n-applaunch\n11020\n")
        let cs2 = try #require(ResourceCatalog.recipes().first { $0.appID == "730" })
        #expect(cs2.profile == .metal)
        #expect(cs2.compatibleProfiles == [.metal])
        #expect(cs2.executableNames == ["cs2.exe"])
        try JSONEncoder().encode(SupervisorRequest(root: paths.root, environmentID: environment.id, command: .launchGame, appID: "730")).write(to: file)
        try await Task.detached { try SupervisorEngine.runLaunchWorker(requestFile: file) }.value
        let cs2Arguments = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(cs2Arguments.prefix(5) == [steam.path, "-cef-disable-gpu", "-silent", "-applaunch", "730"])
        #expect(Array(cs2Arguments.dropFirst(5)) == cs2.launchArguments)
        for (command, uri) in [(SupervisorRequest.Command.uninstallGame, "steam://uninstall/11020"), (.gameProperties, "steam://gameproperties/11020"), (.verifyGame, "steam://validate/11020"), (.openDownloads, "steam://nav/downloads")] {
            try JSONEncoder().encode(SupervisorRequest(root: paths.root, environmentID: environment.id, command: command, appID: "11020")).write(to: file)
            try await Task.detached { try SupervisorEngine.runLaunchWorker(requestFile: file) }.value
            #expect(try String(contentsOf: log, encoding: .utf8) == steam.path + "\n-cef-disable-gpu\n" + uri + "\n")
        }
        let original = try Data(contentsOf: log)
        for command in [SupervisorRequest.Command.installGame, .uninstallGame, .gameProperties, .verifyGame] {
          for invalid in [nil, "0", "11020/../../run", "11020 -applaunch 1"] as [String?] {
            let malformed = SupervisorRequest(root: paths.root, environmentID: environment.id, command: command, appID: invalid)
            try JSONEncoder().encode(malformed).write(to: file)
            #expect(throws: (any Error).self) { try SupervisorEngine.runLaunchWorker(requestFile: file) }
            #expect(try Data(contentsOf: log) == original)
          }
        }
    }
    @Test func managingRunningGameIsRejectedBeforeSteamReceivesARequest() async throws {
        let (paths, _, environment, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        try store.put(environment, kind: "environment", id: environment.id.uuidString)
        var manifest = original.manifest; manifest.observerRelativePath = "observer.exe"
        try Data().write(to: original.root.appendingPathComponent("observer.exe"))
        try JSONEncoder().encode(manifest).write(to: original.root.appendingPathComponent("runtime.json"))
        try "#!/bin/sh\n/usr/bin/printf '%s\\n' '[{\"pid\":42,\"executable\":\"TmForever.exe\"}]'\n".write(to: original.wine, atomically: true, encoding: .utf8)
        let steam = paths.prefix(environment).appendingPathComponent("drive_c/Program Files (x86)/Steam")
        try FileManager.default.createDirectory(at: steam.appendingPathComponent("steamapps/common/Demo"), withIntermediateDirectories: true)
        try Data().write(to: steam.appendingPathComponent("steam.exe"))
        let acf = "\"AppState\" { \"appid\" \"11020\" \"name\" \"TrackMania\" \"installdir\" \"Demo\" \"StateFlags\" \"4\" }"
        try Data(acf.utf8).write(to: steam.appendingPathComponent("steamapps/appmanifest_11020.acf"))
        for command in [SupervisorRequest.Command.uninstallGame, .verifyGame] {
            do {
                _ = try await SupervisorEngine.execute(SupervisorRequest(root: paths.root, environmentID: environment.id, command: command, appID: "11020"))
                Issue.record("Managing an active game should fail")
            } catch { #expect(error.localizedDescription.contains("Close TrackMania")) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.logs.path).filter { $0.hasPrefix(".launch-") }.isEmpty)
        #expect(FileManager.default.fileExists(atPath: steam.appendingPathComponent("steamapps/appmanifest_11020.acf").path))
        do {
            _ = try await SupervisorEngine.execute(SupervisorRequest(root: paths.root, environmentID: environment.id, command: .launchGame, appID: "11020"))
            Issue.record("Window policy must not be rewritten beneath a running game")
        } catch { #expect(error.localizedDescription.contains("already running")) }
        #expect(!FileManager.default.fileExists(atPath: paths.prefix(environment).appendingPathComponent("drive_c/crossedover/trackmania-windowing.reg").path))
    }
    @Test func managingRunningGameWithoutARecipeIsRejected() async throws {
        let (paths, _, environment, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        try store.put(environment, kind: "environment", id: environment.id.uuidString)
        var manifest = original.manifest; manifest.observerRelativePath = "observer.exe"
        try Data().write(to: original.root.appendingPathComponent("observer.exe"))
        try JSONEncoder().encode(manifest).write(to: original.root.appendingPathComponent("runtime.json"))
        try "#!/bin/sh\n/usr/bin/printf '%s\\n' '[{\"pid\":42,\"executable\":\"unlisted.exe\"}]'\n".write(to: original.wine, atomically: true, encoding: .utf8)
        let steam = paths.prefix(environment).appendingPathComponent("drive_c/Program Files (x86)/Steam")
        let game = steam.appendingPathComponent("steamapps/common/Unlisted/bin/win64")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data().write(to: game.appendingPathComponent("unlisted.exe"))
        try Data().write(to: steam.appendingPathComponent("steam.exe"))
        let acf = "\"AppState\" { \"appid\" \"424242\" \"name\" \"Unlisted Game\" \"installdir\" \"Unlisted\" \"StateFlags\" \"4\" }"
        try Data(acf.utf8).write(to: steam.appendingPathComponent("steamapps/appmanifest_424242.acf"))
        for command in [SupervisorRequest.Command.uninstallGame, .verifyGame] {
            do {
                _ = try await SupervisorEngine.execute(SupervisorRequest(root: paths.root, environmentID: environment.id, command: command, appID: "424242"))
                Issue.record("An active game without a recipe must not be managed")
            } catch { #expect(error.localizedDescription.contains("Close Unlisted Game")) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.logs.path).filter { $0.hasPrefix(".launch-") }.isEmpty)
    }
    @Test func stoppingAnAlreadyStoppedEnvironmentIsSuccessful() async throws {
        let (paths, _, environment, runtime) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        try store.put(environment, kind: "environment", id: environment.id.uuidString)
        try "#!/bin/sh\nif [ \"$1\" = \"-k\" ]; then exit 1; fi\nexit 0\n".write(to: runtime.wineserver, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtime.wineserver.path)
        let reply = try await SupervisorEngine.execute(SupervisorRequest(root: paths.root, environmentID: environment.id, command: .forceStop))
        #expect(reply.success)
    }
    @Test func prefixCreationWaitsForDeferredRegistryWrites() async throws {
        let paths = AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("CrossedOver-deferred-" + UUID().uuidString))
        try paths.prepare(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = try Store(url: paths.root.appendingPathComponent("test.sqlite"))
        let runtime = try makeRuntime(id: "deferred", exitStatus: 0, paths: paths)
        let script = """
        #!/bin/sh
        (
          /bin/sleep 0.25
          /bin/echo 'WINE REGISTRY Version 2' > "$WINEPREFIX/system.reg"
          /bin/echo 'WINE REGISTRY Version 2' > "$WINEPREFIX/user.reg"
        ) &
        exit 0

        """
        try script.write(to: runtime.wine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtime.wine.path)
        let environment = try await EnvironmentManager(paths: paths, store: store).create(runtime: runtime)
        #expect(environment.state == "ready")
        #expect(FileManager.default.fileExists(atPath: paths.prefix(environment).appendingPathComponent("system.reg").path))
    }
}

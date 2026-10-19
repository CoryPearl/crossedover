import Foundation
import Testing
@testable import CrossedOverCore

@Suite struct WindowsAppsTests {
    func fixture() throws -> (AppPaths, Store, ManagedEnvironment, URL) {
        let paths = AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("crossedover-apps-" + UUID().uuidString))
        try paths.prepare()
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        var environment = ManagedEnvironment(runtimeID: "test-runtime"); environment.state = "ready"
        try FileManager.default.createDirectory(at: paths.prefix(environment).appendingPathComponent("drive_c"), withIntermediateDirectories: true)
        try store.put(environment, kind: "environment", id: environment.id.uuidString)
        let source = paths.root.appendingPathComponent("payload")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        return (paths, store, environment, source)
    }
    func pe(at file: URL, machine: UInt16 = 0x8664, dll: Bool = false) throws {
        var data = Data(repeating: 0, count: 512)
        func u16(_ value: UInt16, _ offset: Int) { data[offset] = UInt8(value & 0xff); data[offset + 1] = UInt8(value >> 8) }
        data[0] = 0x4d; data[1] = 0x5a; data[60] = 64
        data[64] = 0x50; data[65] = 0x45
        u16(machine, 68); u16(1, 70); u16(240, 84); u16(dll ? 0x2002 : 2, 86)
        u16(machine == 0x14c ? 0x10b : 0x20b, 88)
        try data.write(to: file)
    }
    @Test func acceptsX86AndX64RejectsARMAndDisguisedFiles() throws {
        let (paths, _, _, folder) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let file = folder.appendingPathComponent("program.EXE")
        for machine: UInt16 in [0x14c, 0x8664] { try pe(at: file, machine: machine); try WindowsApps.validateExecutable(file) }
        try pe(at: file, machine: 0xaa64)
        #expect(throws: (any Error).self) { try WindowsApps.validateExecutable(file) }
        try pe(at: file, dll: true)
        #expect(throws: (any Error).self) { try WindowsApps.validateExecutable(file) }
        try Data("MZ not an executable".utf8).write(to: file)
        #expect(throws: (any Error).self) { try WindowsApps.validateExecutable(file) }
        try pe(at: file)
        let truncated = Data(try Data(contentsOf: file).prefix(100)); try truncated.write(to: file)
        #expect(throws: (any Error).self) { try WindowsApps.validateExecutable(file) }
    }
    @Test func preservesSidecarsAndLibraryChoiceWithoutAffectingSteamGames() throws {
        let (paths, store, environment, folder) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let file = folder.appendingPathComponent("tool ' $().exe"); try pe(at: file)
        let assets = folder.appendingPathComponent("assets"); try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("required asset".utf8).write(to: assets.appendingPathComponent("data.bin"))
        let app = try WindowsApps.add(executable: file, name: "My tool", category: .apps, includeFolder: true, environment: environment, paths: paths, store: store)
        let copied = try WindowsApps.executable(for: app, prefix: paths.prefix(environment))
        #expect(try String(contentsOf: copied.deletingLastPathComponent().appendingPathComponent("assets/data.bin"), encoding: .utf8) == "required asset")
        #expect(try Data(contentsOf: copied) == Data(contentsOf: file))
        try store.replaceGames([], environmentID: environment.id)
        #expect(try store.all(WindowsApp.self, kind: "windowsApp") == [app])
        let standalone = try WindowsApps.add(executable: file, name: "Game", category: .games, includeFolder: false, environment: environment, paths: paths, store: store)
        #expect(standalone.category == .games)
        #expect(!FileManager.default.fileExists(atPath: paths.prefix(environment).appendingPathComponent(standalone.importedDirectory! + "/assets").path))
        try store.remove(kind: "windowsApp", id: app.id.uuidString)
        #expect(FileManager.default.fileExists(atPath: copied.path))
    }
    @Test func installerCanBeRetargetedToInstalledExecutableWithoutCopyingOrChangingIdentity() throws {
        let (paths, store, environment, folder) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let installer = folder.appendingPathComponent("setup.exe"); try pe(at: installer)
        let card = try WindowsApps.add(executable: installer, name: "Tool", category: .apps, includeFolder: false, environment: environment, paths: paths, store: store)
        let installed = paths.prefix(environment).appendingPathComponent("drive_c/Program Files/Tool")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let file = installed.appendingPathComponent("tool.exe"); try pe(at: file)
        let updated = try WindowsApps.add(executable: file, name: "Renamed", category: .games, includeFolder: true, environment: environment, paths: paths, store: store, replacing: card)
        #expect(updated.id == card.id)
        #expect(updated.executablePath == "drive_c/Program Files/Tool/tool.exe")
        #expect(updated.category == .games)
        #expect(try store.all(WindowsApp.self, kind: "windowsApp").count == 1)
        #expect(try WindowsApps.executable(for: updated, prefix: paths.prefix(environment)) == file)
    }
    @Test func rejectsEscapingPathsAndRollsBackIncompleteFolderImports() throws {
        let (paths, store, environment, folder) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let file = folder.appendingPathComponent("tool.exe"); try pe(at: file)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("escape"), withDestinationURL: paths.root)
        #expect(throws: (any Error).self) {
            try WindowsApps.add(executable: file, name: "Tool", category: .apps, includeFolder: true, environment: environment, paths: paths, store: store)
        }
        #expect(try store.all(WindowsApp.self, kind: "windowsApp").isEmpty)
        let imports = paths.prefix(environment).appendingPathComponent("drive_c/crossedover/Apps")
        #expect(try FileManager.default.contentsOfDirectory(atPath: imports.path).isEmpty)
        for path in ["drive_c/../../payload/tool.exe", file.path, "payload/tool.exe"] {
            let app = WindowsApp(environmentID: environment.id, name: "Escape", category: .apps, executablePath: path)
            #expect(throws: (any Error).self) { try WindowsApps.executable(for: app, prefix: paths.prefix(environment)) }
        }
        let link = paths.prefix(environment).appendingPathComponent("drive_c/escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let app = WindowsApp(environmentID: environment.id, name: "Escape", category: .apps, executablePath: "drive_c/escape/tool.exe")
        #expect(throws: (any Error).self) { try WindowsApps.executable(for: app, prefix: paths.prefix(environment)) }
    }
    @Test func workerRunsWithoutSteamUsesAppDirectoryAndReportsFailureAndBoundedLog() throws {
        let (paths, store, environment, folder) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let file = folder.appendingPathComponent("tool ' $().exe"); try pe(at: file)
        let app = try WindowsApps.add(executable: file, name: "Tool", category: .apps, includeFolder: false, environment: environment, paths: paths, store: store)
        let runtimeRoot = paths.runtimes.appendingPathComponent(environment.runtimeID)
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        for name in ["wine", "wineserver"] {
            let script = name == "wine" ? "#!/bin/sh\n/usr/bin/printf '%s\\n' \"$PWD\" \"$1\" \"$CROSSEDOVER_STEAM_BRANDING\"\nexit 7\n" : "#!/bin/sh\nexit 0\n"
            try script.write(to: runtimeRoot.appendingPathComponent(name), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtimeRoot.appendingPathComponent(name).path)
        }
        let manifest = RuntimeManifest(id: environment.runtimeID, name: "Test", version: "test", wineRelativePath: "wine", wineserverRelativePath: "wineserver", sourceURL: "https://example.invalid", sourceSHA256: String(repeating: "0", count: 64))
        try JSONEncoder().encode(manifest).write(to: runtimeRoot.appendingPathComponent("runtime.json"))
        let run = WindowsAppRun(app: app); try store.put(run, kind: "windowsRun", id: run.id.uuidString)
        let request = SupervisorRequest(root: paths.root, environmentID: environment.id, command: .launchWindowsApp, windowsAppID: app.id, runID: run.id)
        let requestFile = paths.logs.appendingPathComponent(".launch-test.json")
        try JSONEncoder().encode(request).write(to: requestFile)
        try SupervisorEngine.runLaunchWorker(requestFile: requestFile)
        let result = try #require(store.all(WindowsAppRun.self, kind: "windowsRun").first)
        #expect(result.state == "failed"); #expect(result.exitCode == 7); #expect(result.endedAt != nil)
        let executable = try WindowsApps.executable(for: app, prefix: paths.prefix(environment))
        let log = paths.logs.appendingPathComponent("windows-app-" + app.id.uuidString + ".log")
        let lines = try String(contentsOf: log, encoding: .utf8).components(separatedBy: "\n")
        #expect(URL(fileURLWithPath: lines[0]).standardizedFileURL == executable.deletingLastPathComponent().standardizedFileURL)
        #expect(lines[1] == executable.path)
        #expect(lines[2].isEmpty) // No Steam branding was inherited.
        // Exercise the custom-app worker's output cap and successful exit path.
        try "#!/bin/sh\n/usr/bin/head -c 1500000 /dev/zero\nexit 0\n".write(to: runtimeRoot.appendingPathComponent("wine"), atomically: true, encoding: .utf8)
        let verbose = WindowsAppRun(app: app)
        try store.put(verbose, kind: "windowsRun", id: verbose.id.uuidString)
        try JSONEncoder().encode(SupervisorRequest(root: paths.root, environmentID: environment.id, command: .launchWindowsApp, windowsAppID: app.id, runID: verbose.id)).write(to: requestFile)
        try SupervisorEngine.runLaunchWorker(requestFile: requestFile)
        #expect(try Data(contentsOf: log).count == 1_048_576)
        #expect(try store.all(WindowsAppRun.self, kind: "windowsRun").first(where: { $0.id == verbose.id })?.state == "exited")
        // A missing executable must also get an actionable persisted failure.
        try FileManager.default.removeItem(at: executable)
        var missing = WindowsAppRun(app: app); missing.workerPID = nil
        try store.put(missing, kind: "windowsRun", id: missing.id.uuidString)
        try JSONEncoder().encode(SupervisorRequest(root: paths.root, environmentID: environment.id, command: .launchWindowsApp, windowsAppID: app.id, runID: missing.id)).write(to: requestFile)
        #expect(throws: (any Error).self) { try SupervisorEngine.runLaunchWorker(requestFile: requestFile) }
        #expect(try store.all(WindowsAppRun.self, kind: "windowsRun").first(where: { $0.id == missing.id })?.state == "failed")
        #expect(!FileManager.default.fileExists(atPath: paths.prefix(environment).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe").path))
    }
}

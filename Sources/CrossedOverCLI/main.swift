import Foundation
import CrossedOverCore

@main struct CLI {
    static func main() async {
        do {
            if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--launch-worker" {
                try SupervisorEngine.runLaunchWorker(requestFile: URL(fileURLWithPath: CommandLine.arguments[2])); return
            }
            try await run()
        }
        catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
    }
    static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
    static func run() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var root: URL?
        if let index = arguments.firstIndex(of: "--root") {
            guard index + 1 < arguments.count else { throw CrossedOverError.message("--root requires a directory.") }
            root = URL(fileURLWithPath: arguments[index + 1]); arguments.removeSubrange(index...index + 1)
        }
        let paths = AppPaths(root: root); try paths.prepare()
        let store = try Store(url: paths.root.appendingPathComponent("crossedover.sqlite"))
        let runtimes = RuntimeManager(paths: paths), environments = EnvironmentManager(paths: paths, store: store)
        let command = arguments.first ?? "help"
        func current() throws -> ManagedEnvironment {
            guard let environment = try store.all(ManagedEnvironment.self, kind: "environment").first else { throw CrossedOverError.message("Create an environment first.") }
            return environment
        }
        switch command {
        case "host": try await printJSON(HostInspector.inspect(at: paths.root))
        case "runtime-list": try await printJSON(runtimes.installed().map(\.manifest))
        case "runtime-install":
            let catalog = try RuntimeManager.catalog()
            let id = arguments.count > 1 ? arguments[1] : catalog[0].id
            guard let item = catalog.first(where: { $0.id == id }) else { throw CrossedOverError.message("Unknown runtime identifier.") }
            let archive = arguments.count > 2 ? URL(fileURLWithPath: arguments[2]) : nil
            let runtime = try await runtimes.install(item, archive: archive); try printJSON(runtime.manifest)
        case "runtime-import":
            guard arguments.count == 2 else { throw CrossedOverError.message("runtime-import requires a directory containing runtime.json.") }
            let runtime = try await runtimes.importLocal(URL(fileURLWithPath: arguments[1])); try printJSON(runtime.manifest)
        case "runtime-use":
            guard arguments.count == 2 else { throw CrossedOverError.message("runtime-use requires an installed runtime ID.") }
            let environment = try current(), old = try await runtimes.resolve(environment.runtimeID), replacement = try await runtimes.resolve(arguments[1])
            try await printJSON(environments.migrate(environment, from: old, to: replacement))
        case "create":
            guard let runtime = try await runtimes.installed().first else { throw CrossedOverError.message("Install a runtime first.") }
            try await printJSON(environments.create(runtime: runtime))
        case "environments": try printJSON(store.all(ManagedEnvironment.self, kind: "environment"))
        case "steam-install":
            let environment = try current(), runtime = try await runtimes.resolve(environment.runtimeID)
            try await SteamService(paths: paths).install(environment: environment, runtime: runtime)
            print("Windows Steam installed.")
        case "steam", "install", "launch", "uninstall", "properties", "verify", "downloads", "stop", "force-stop", "observe":
            let environment = try current()
            let operation: SupervisorRequest.Command = ["steam": .openSteam, "install": .installGame, "launch": .launchGame, "uninstall": .uninstallGame, "properties": .gameProperties, "verify": .verifyGame, "downloads": .openDownloads, "stop": .shutdown, "force-stop": .forceStop, "observe": .observe][command]!
            let appID = arguments.count > 1 ? arguments[1] : nil
            try await printJSON(SupervisorEngine.execute(SupervisorRequest(root: paths.root, environmentID: environment.id, command: operation, appID: appID)))
        case "games":
            let environment = try current()
            try printJSON(SteamDiscovery().discover(environment: environment, prefix: paths.prefix(environment)))
        case "smoke", "benchmark":
            let environment = try current(), runtime = try await runtimes.resolve(environment.runtimeID)
            let prefix = paths.prefix(environment), lock = try EnvironmentLock(prefix: paths.prefix(environment))
            defer { withExtendedLifetime(lock) {} }
            var names = command == "benchmark" ? ["d3d9-benchmark-32.exe"] : ["smoke-32.exe", "smoke-64.exe"]
            if command == "smoke", arguments.contains("--graphics") {
                names += environment.profile == .metal
                    ? ["d3d11-smoke-32.exe", "d3d11-smoke-64.exe"]
                    : ["d3d9-smoke-32.exe", "d3d9-smoke-64.exe", "d3d9-textures-32.exe", "d3d9-textures-64.exe"]
                if environment.profile == .performance,
                   FileManager.default.fileExists(atPath: runtime.root.appendingPathComponent("share/crossedover/d3d9-mapped-copy-32.exe").path) {
                    names += ["d3d9-mapped-copy-32.exe"]
                }
            }
            if command == "smoke", environment.profile == .performance, runtime.manifest.x87RelativePath != nil {
                names += ["x87-smoke-32.exe", "x87-smoke-64.exe"]
            }
            if command == "smoke", let hash = runtime.manifest.fileHashes["audio/i386-windows/OpenAL32.dll"] {
                let source = try FileSafety.containedURL("audio/i386-windows/OpenAL32.dll", in: runtime.root)
                try FileSafety.verify(source, sha256: hash)
                let destination = try FileSafety.containedURL("drive_c/crossedover/openal-soft.dll", in: prefix)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contentsOf: source).write(to: destination, options: .atomic)
                names += ["openal-smoke-32.exe"]
            }
            for name in names {
                let source = try FileSafety.containedURL("share/crossedover/" + name, in: runtime.root)
                guard FileManager.default.fileExists(atPath: source.path) else { throw CrossedOverError.message("This runtime does not include \(name). Build the source runtime first.") }
                let destination = try FileSafety.containedURL("drive_c/crossedover/" + name, in: prefix)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: source, to: destination)
                let result = try await ProcessRunner.run(runtime.wine, arguments: [destination.path], workingDirectory: prefix.appendingPathComponent("drive_c"), environment: WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: environment.profile), timeout: 60)
                print("\(name): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                guard result.status == 0 else { throw CrossedOverError.message("\(name) failed with exit status \(result.status).") }
            }
        case "backup":
            let environment = try current(), runtime = try await runtimes.resolve(environment.runtimeID)
            print(try await environments.backup(environment, runtime: runtime).path)
        case "restore":
            guard arguments.count == 2 else { throw CrossedOverError.message("restore requires a managed backup directory.") }
            try await printJSON(environments.restore(URL(fileURLWithPath: arguments[1]), current: current(), runtimeManager: runtimes))
        case "profile":
            guard arguments.count == 2, let profile = GraphicsProfile(rawValue: arguments[1]) else { throw CrossedOverError.message("profile requires legacy, performance or metal.") }
            let environment = try current(), runtime = try await runtimes.resolve(environment.runtimeID)
            try await printJSON(environments.setProfile(profile, environment: environment, runtime: runtime))
        case "sync":
            guard arguments.count == 2, ["automatic", "server"].contains(arguments[1]) else { throw CrossedOverError.message("sync requires automatic or server. Stop Steam and games first.") }
            let environment = try current(), runtime = try await runtimes.resolve(environment.runtimeID)
            try await environments.setServerSynchronization(arguments[1] == "server", environment: environment, runtime: runtime)
            print("Synchronization: " + arguments[1])
        case "repair":
            let environment = try current(), runtime = try await runtimes.resolve(environment.runtimeID)
            try await printJSON(environments.repair(environment, runtime: runtime))
        case "diagnostics": print(try await DiagnosticsService.preview(paths: paths, store: store, host: HostInspector.inspect(at: paths.root)))
        default:
            print("""
            crossedover \(AppVersion.current)
            Usage: crossedover [--root DIRECTORY] COMMAND
              host                      Inspect this Mac
              runtime-list              List installed runtimes
              runtime-install [ID] [ARCHIVE]  Install a pinned experimental runtime
              runtime-import DIRECTORY  Import an explicitly trusted development runtime
              runtime-use ID            Change runtime without an automatic backup
              create                    Create the managed Steam environment
              environments              Inspect environment metadata
              steam-install             Download and install official Windows Steam
              steam                     Open Windows Steam
              games                     Discover installed games
              smoke [--graphics]        Check 32/64-bit execution and optional GPU readback
              benchmark                 Run a synthetic D3D9 workload (not game FPS)
              install APPID             Open the game's Windows Steam install dialog
              launch APPID              Request launch through Windows Steam
              uninstall APPID           Open Steam's uninstall confirmation
              properties APPID          Open the game's Steam properties
              verify APPID              Request Steam file verification
              downloads                 Open Steam Downloads
              observe                   Observe processes if the runtime supplies a helper
              stop                      Ask Windows Steam to shut down
              force-stop                Stop only the managed Wine environment
              profile legacy|performance|metal  Change graphics after stopping the environment
              sync automatic|server     Change synchronization after stopping the environment
              backup                    Back up a stopped environment
              restore BACKUP_DIRECTORY  Restore prefix and runtime selection together
              repair                    Reinitialize a stopped Wine environment
              diagnostics               Print a redacted report without auth files
            """)
        }
    }
}

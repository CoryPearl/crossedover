import Foundation

/// A lock on the environment directory also serializes independent app/CLI instances.
public final class EnvironmentLock: @unchecked Sendable {
    private var descriptor: Int32
    public init(prefix: URL) throws {
        let url = prefix.deletingLastPathComponent().appendingPathComponent(prefix.lastPathComponent + ".lock")
        descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CrossedOverError.message("Could not open the environment lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); descriptor = -1
            throw CrossedOverError.message("Another crossedover operation is using this environment.")
        }
    }
    deinit { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor) } }
}

public enum WineConfiguration {
    // Prefix-local so the app, detached workers and CLI always agree. Backups
    // preserve the setting alongside the environment it applies to.
    public static let serverSyncMarker = ".crossedover-server-sync"
    public static func environment(runtime: InstalledRuntime, prefix: URL, profile: GraphicsProfile) -> [String: String] {
        var variables = ProcessInfo.processInfo.environment
        for key in ["WINEPREFIX", "WINESERVER", "WINELOADER", "WINEDLLPATH", "WINEDLLOVERRIDES", "DYLD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES", "WINEARCH", "WINEMSYNC", "WINEESYNC", "WINEFSYNC", "DXVK_CONFIG_FILE", "DXVK_LOG_PATH", "DXVK_HUD", "ROSETTA_X87_PATH", "X87_SIDECAR_BOOTSTRAP", "CROSSEDOVER_FRAME_LOG"] { variables.removeValue(forKey: key) }
        variables["WINEPREFIX"] = prefix.path
        variables["WINESERVER"] = runtime.wineserver.path
        variables["WINEDEBUG"] = "-all"
        variables["WINE_D3D_CONFIG"] = "renderer=gl"
        variables["MVK_CONFIG_LOG_LEVEL"] = "1"
        variables["DXMT_LOG_LEVEL"] = "error"
        variables["CROSSEDOVER_STEAM_CEF_COMPAT"] = "1"
        variables["DYLD_FALLBACK_LIBRARY_PATH"] = runtime.root.appendingPathComponent("lib").path + ":/usr/lib"
        variables["WINEDLLOVERRIDES"] = "winemetal,dxgi,d3d11,d3d10core,d3d9=b;mscoree,mshtml="
        let serverSync = FileManager.default.fileExists(atPath: prefix.appendingPathComponent(serverSyncMarker).path)
        variables["WINEMSYNC"] = runtime.manifest.supportsMSync == true && !serverSync ? "1" : "0"
        variables.removeValue(forKey: "CROSSEDOVER_DLL_OVERLAY")
        if profile == .metal {
            variables["WINEDLLPATH"] = runtime.root.appendingPathComponent("dxmt").path
            variables["CROSSEDOVER_DLL_OVERLAY"] = "1"
        }
        if profile == .performance {
            // TrackMania uses DirectDraw for startup windows. Its 3D calls go
            // through native D9VK; avoid initializing a second OpenGL adapter.
            variables["WINE_D3D_CONFIG"] = "renderer=gdi"
            if let helper = runtime.manifest.x87RelativePath {
                variables["ROSETTA_X87_PATH"] = runtime.root.appendingPathComponent(helper).path
            }
            variables["DYLD_FALLBACK_LIBRARY_PATH"] = runtime.root.appendingPathComponent("dxvk").path + ":" + runtime.root.appendingPathComponent("lib").path + ":/usr/lib"
            variables["WINEDLLOVERRIDES"] = "winemetal,dxgi,d3d11,d3d10core=b;d3d9=n;mscoree,mshtml="
            variables["DXVK_CONFIG_FILE"] = "C:\\crossedover\\dxvk.conf"
            variables["DXVK_LOG_PATH"] = "C:\\crossedover\\logs"
            variables["DXVK_LOG_LEVEL"] = "info"
            variables["DXVK_HUD"] = "0"
        }
        variables["PATH"] = runtime.wine.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        return variables
    }
}

public actor EnvironmentManager {
    public let paths: AppPaths
    public let store: Store
    public init(paths: AppPaths, store: Store) { self.paths = paths; self.store = store }
    public func create(runtime: InstalledRuntime) async throws -> ManagedEnvironment {
        guard try store.all(ManagedEnvironment.self, kind: "environment").isEmpty else { throw CrossedOverError.message("Version 1 manages one Steam environment. Repair or restore the existing environment instead.") }
        var environment = ManagedEnvironment(runtimeID: runtime.id)
        if runtime.manifest.profiles.contains(.performance) { environment.profile = .performance }
        let prefix = paths.prefix(environment)
        let lock = try EnvironmentLock(prefix: prefix)
        defer { withExtendedLifetime(lock) {} }
        try store.put(environment, kind: "environment", id: environment.id.uuidString)
        do {
            try FileManager.default.createDirectory(at: prefix.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
            let result = try await ProcessRunner.run(runtime.wine, arguments: ["wineboot", "-u", "-r"], workingDirectory: prefix.appendingPathComponent("drive_c"), environment: WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: environment.profile), timeout: 180)
            guard result.status == 0 else { throw CrossedOverError.message("Wine environment creation failed: \(Redaction.apply(result.output).suffix(1000))") }
            try await Self.waitForRegistry(prefix: prefix)
            try Self.installExtensions(runtime: runtime, prefix: prefix)
            // Remove Wine's broad default filesystem mapping and user-folder links.
            let z = prefix.appendingPathComponent("dosdevices/z:")
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: z.path)) != nil { try FileManager.default.removeItem(at: z) }
            try Self.containUserFolders(prefix: prefix)
            environment.state = "ready"
            try store.put(environment, kind: "environment", id: environment.id.uuidString)
            return environment
        } catch {
            environment.state = "needsRepair"; try? store.put(environment, kind: "environment", id: environment.id.uuidString)
            throw error
        }
    }
    private static func containUserFolders(prefix: URL) throws {
        let users = prefix.appendingPathComponent("drive_c/users")
        if let enumerator = FileManager.default.enumerator(at: users, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true,
                   !url.resolvingSymlinksInPath().path.hasPrefix(prefix.path + "/") {
                    enumerator.skipDescendants(); try FileManager.default.removeItem(at: url)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                }
            }
        }
    }
    private static func installExtensions(runtime: InstalledRuntime, prefix: URL) throws {
        for (profile, overlay, name) in [(GraphicsProfile.metal, "dxmt", "winemetal.dll"), (.performance, "dxvk", "d3d9.dll")] where runtime.manifest.profiles.contains(profile) {
            for (architecture, directory) in [("x86_64-windows", "system32"), ("i386-windows", "syswow64")] {
                let source = try FileSafety.containedURL("\(overlay)/\(architecture)/\(name)", in: runtime.root)
                let destination = try FileSafety.containedURL("drive_c/windows/\(directory)/\(name)", in: prefix)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }
        if runtime.manifest.profiles.contains(.performance) {
            let source = try FileSafety.containedURL("dxvk/dxvk.conf", in: runtime.root)
            let destination = try FileSafety.containedURL("drive_c/crossedover/dxvk.conf", in: prefix)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent().appendingPathComponent("logs"), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }
    private static func waitForRegistry(prefix: URL) async throws {
        // Wineboot can return before wineserver flushes a newly created registry.
        for _ in 0..<120 {
            try Task.checkCancellation()
            let ready = ["system.reg", "user.reg"].allSatisfy { name in
                let attributes = try? FileManager.default.attributesOfItem(atPath: prefix.appendingPathComponent(name).path)
                return (attributes?[.size] as? Int ?? 0) > 0
            }
            if ready { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw CrossedOverError.message("Wine started but did not finish saving the environment registry. Close its windows and repair the environment before retrying.")
    }
    public func isActive(_ environment: ManagedEnvironment, runtime: InstalledRuntime) async throws -> Bool {
        let result = try await ProcessRunner.run(runtime.wineserver, arguments: ["-w"], environment: WineConfiguration.environment(runtime: runtime, prefix: paths.prefix(environment), profile: environment.profile), timeout: 1)
        return result.status != 0
    }
    public func requireStopped(_ environment: ManagedEnvironment, runtime: InstalledRuntime) async throws {
        do {
            let result = try await ProcessRunner.run(runtime.wineserver, arguments: ["-w"], environment: WineConfiguration.environment(runtime: runtime, prefix: paths.prefix(environment), profile: environment.profile), timeout: 3)
            guard result.status == 0 else { throw CrossedOverError.message("Stop Windows Steam and its games before modifying the environment.") }
        } catch { throw CrossedOverError.message("Stop Windows Steam and its games before modifying the environment.") }
    }
    public func setProfile(_ profile: GraphicsProfile, environment: ManagedEnvironment, runtime: InstalledRuntime) async throws -> ManagedEnvironment {
        guard runtime.manifest.profiles.contains(profile) else { throw CrossedOverError.message("This runtime does not include \(profile.title). Import a runtime that advertises this capability.") }
        let lock = try EnvironmentLock(prefix: paths.prefix(environment)); defer { withExtendedLifetime(lock) {} }
        try await requireStopped(environment, runtime: runtime)
        try Self.installExtensions(runtime: runtime, prefix: paths.prefix(environment))
        var updated = environment; updated.profile = profile
        try store.put(updated, kind: "environment", id: updated.id.uuidString)
        return updated
    }
    public func setServerSynchronization(_ enabled: Bool, environment: ManagedEnvironment, runtime: InstalledRuntime) async throws {
        let prefix = paths.prefix(environment), lock = try EnvironmentLock(prefix: paths.prefix(environment))
        defer { withExtendedLifetime(lock) {} }
        try await requireStopped(environment, runtime: runtime)
        let marker = try FileSafety.containedURL(WineConfiguration.serverSyncMarker, in: prefix)
        if enabled { try Data("Standard Wine server synchronization\n".utf8).write(to: marker, options: .atomic) }
        else if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
    }
    public func backup(_ environment: ManagedEnvironment, runtime: InstalledRuntime) async throws -> URL {
        let lock = try EnvironmentLock(prefix: paths.prefix(environment)); defer { withExtendedLifetime(lock) {} }
        try await requireStopped(environment, runtime: runtime)
        return try await makeBackup(environment)
    }
    private func makeBackup(_ environment: ManagedEnvironment) async throws -> URL {
        let destination = paths.backups.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/cp"), arguments: ["-cR", paths.prefix(environment).path, destination.appendingPathComponent("prefix").path], timeout: 1800)
            guard result.status == 0 else { throw CrossedOverError.message("Backup failed: \(result.output)") }
            try JSONEncoder().encode(environment).write(to: destination.appendingPathComponent("environment.json"), options: .atomic)
            return destination
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    public func migrate(_ environment: ManagedEnvironment, from current: InstalledRuntime, to replacement: InstalledRuntime) async throws -> ManagedEnvironment {
        guard current.id != replacement.id else { return environment }
        let prefix = paths.prefix(environment), lock = try EnvironmentLock(prefix: paths.prefix(environment))
        defer { withExtendedLifetime(lock) {} }
        try await requireStopped(environment, runtime: current)
        let backup = try await makeBackup(environment)
        var updated = environment; updated.runtimeID = replacement.id
        if !replacement.manifest.profiles.contains(updated.profile) { updated.profile = .legacy }
        do {
            // Update the prefix without running Steam's Windows startup entry.
            let result = try await ProcessRunner.run(replacement.wine, arguments: ["wineboot", "-u", "-r"], workingDirectory: prefix.appendingPathComponent("drive_c"), environment: WineConfiguration.environment(runtime: replacement, prefix: prefix, profile: updated.profile), timeout: 180)
            guard result.status == 0 else { throw CrossedOverError.message("The replacement runtime could not upgrade the prefix.") }
            try Self.installExtensions(runtime: replacement, prefix: prefix)
            try Self.containUserFolders(prefix: prefix)
            let z = prefix.appendingPathComponent("dosdevices/z:")
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: z.path)) != nil { try FileManager.default.removeItem(at: z) }
            updated.state = "ready"; try store.put(updated, kind: "environment", id: updated.id.uuidString)
            return updated
        } catch {
            _ = try? await ProcessRunner.run(replacement.wineserver, arguments: ["-k"], environment: WineConfiguration.environment(runtime: replacement, prefix: prefix, profile: updated.profile), timeout: 15)
            let failed = paths.environments.appendingPathComponent(".failed-upgrade-" + UUID().uuidString)
            do {
                try FileManager.default.moveItem(at: prefix, to: failed)
                let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/cp"), arguments: ["-cR", backup.appendingPathComponent("prefix").path, prefix.path], timeout: 1800)
                guard result.status == 0 else { throw CrossedOverError.message("Rollback copy failed.") }
                try store.put(environment, kind: "environment", id: environment.id.uuidString)
                try? FileManager.default.removeItem(at: failed)
            } catch {
                throw CrossedOverError.message("Upgrade failed and automatic recovery could not finish. Your backup is preserved at \(backup.path). Restore it before launching Steam.")
            }
            throw CrossedOverError.message("Runtime upgrade failed. The previous prefix and runtime selection were restored. Backup: \(backup.path)")
        }
    }
    public func restore(_ backup: URL, current: ManagedEnvironment, runtimeManager: RuntimeManager) async throws -> ManagedEnvironment {
        guard backup.deletingLastPathComponent().standardizedFileURL == paths.backups.standardizedFileURL else { throw CrossedOverError.message("Select a managed backup.") }
        let saved = try JSONDecoder().decode(ManagedEnvironment.self, from: Data(contentsOf: backup.appendingPathComponent("environment.json")))
        guard saved.id == current.id else { throw CrossedOverError.message("This backup belongs to a different environment.") }
        let currentRuntime = try await runtimeManager.resolve(current.runtimeID)
        _ = try await runtimeManager.resolve(saved.runtimeID)
        let prefix = paths.prefix(current), lock = try EnvironmentLock(prefix: paths.prefix(current))
        defer { withExtendedLifetime(lock) {} }
        try await requireStopped(current, runtime: currentRuntime)
        let stage = paths.environments.appendingPathComponent(".restore-" + UUID().uuidString)
        let previous = paths.environments.appendingPathComponent(".previous-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/cp"), arguments: ["-cR", backup.appendingPathComponent("prefix").path, stage.path], timeout: 1800)
        guard result.status == 0 else { throw CrossedOverError.message("Could not stage the backup; your current environment was preserved.") }
        try FileManager.default.moveItem(at: prefix, to: previous)
        do {
            try FileManager.default.moveItem(at: stage, to: prefix)
            try store.put(saved, kind: "environment", id: saved.id.uuidString)
        } catch {
            try? FileManager.default.removeItem(at: prefix); try? FileManager.default.moveItem(at: previous, to: prefix); throw error
        }
        try? FileManager.default.removeItem(at: previous)
        return saved
    }
    public func repair(_ environment: ManagedEnvironment, runtime: InstalledRuntime) async throws -> ManagedEnvironment {
        let lock = try EnvironmentLock(prefix: paths.prefix(environment)); defer { withExtendedLifetime(lock) {} }
        try await requireStopped(environment, runtime: runtime)
        let result = try await ProcessRunner.run(runtime.wine, arguments: ["wineboot", "-u", "-r"], workingDirectory: paths.prefix(environment).appendingPathComponent("drive_c"), environment: WineConfiguration.environment(runtime: runtime, prefix: paths.prefix(environment), profile: environment.profile), timeout: 180)
        guard result.status == 0 else { throw CrossedOverError.message("Wine repair failed: \(Redaction.apply(result.output).suffix(1000))") }
        try await Self.waitForRegistry(prefix: paths.prefix(environment))
        try Self.installExtensions(runtime: runtime, prefix: paths.prefix(environment))
        try Self.containUserFolders(prefix: paths.prefix(environment))
        let z = paths.prefix(environment).appendingPathComponent("dosdevices/z:")
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: z.path)) != nil { try FileManager.default.removeItem(at: z) }
        var updated = environment; updated.state = "ready"
        try store.put(updated, kind: "environment", id: updated.id.uuidString); return updated
    }
}

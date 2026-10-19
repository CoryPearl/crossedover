import Foundation

/// Windows Epic only. Never resolves or opens the user's separate native Mac launcher.
public actor EpicService {
    public let paths: AppPaths
    public init(paths: AppPaths) { self.paths = paths }
    public static let installerURL = URL(string: "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi")!
    public static let libraryURI = "com.epicgames.launcher://store/library"

    public static func executable(prefix: URL) throws -> URL {
        for directory in ["Program Files (x86)", "Program Files"] {
            for architecture in ["Win64", "Win32"] {
                let url = try FileSafety.containedURL("drive_c/\(directory)/Epic Games/Launcher/Portal/Binaries/\(architecture)/EpicGamesLauncher.exe", in: prefix)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        throw CrossedOverError.message("Set up Windows Epic Games in this environment first.")
    }
    public static func requireSupportedRuntime(_ runtime: InstalledRuntime) throws {
        guard runtime.manifest.profiles.contains(.metal) else { throw CrossedOverError.message("Windows Epic needs a runtime with Metal DirectX 11 support. Import the included runtime in Settings → Advanced.") }
    }
    public static func gamesFolder(prefix: URL) throws -> URL {
        try FileSafety.containedURL("drive_c/Program Files/Epic Games", in: prefix)
    }
    public static func environment(runtime: InstalledRuntime, prefix: URL, profile: GraphicsProfile) -> [String: String] {
        var variables = WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: runtime.manifest.profiles.contains(.metal) ? .metal : profile)
        variables.removeValue(forKey: "CROSSEDOVER_STEAM_BRANDING")
        variables.removeValue(forKey: "CROSSEDOVER_STEAM_CEF_COMPAT")
        variables.removeValue(forKey: "WINEPRELOADERAPPNAME")
        if runtime.manifest.profiles.contains(.performance) {
            // Do not force the launcher's D3D9 path onto the game (or vice
            // versa). The scoped registry policy selects each executable.
            variables["WINEDLLOVERRIDES"] = "winemetal,dxgi,d3d11,d3d10core=b;mscoree,mshtml="
            variables["DYLD_FALLBACK_LIBRARY_PATH"] = runtime.root.appendingPathComponent("dxvk").path + ":" + runtime.root.appendingPathComponent("lib").path + ":/usr/lib"
            variables["DXVK_CONFIG_FILE"] = "C:\\crossedover\\dxvk.conf"
            variables["DXVK_LOG_PATH"] = "C:\\crossedover\\logs"
            variables["DXVK_LOG_LEVEL"] = "error"
            variables["DXVK_HUD"] = "0"
        }
        // Current Epic uses a D3D11 UI. Its tree has Metal plus scoped D3D9
        // choices; Steam and directly imported apps retain their selected profile.
        return variables
    }
    public static let graphicsRegistry = """
    Windows Registry Editor Version 5.00

    [HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\EpicGamesLauncher.exe\\DllOverrides]
    "d3d9"="builtin"
    [HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\EpicWebHelper.exe\\DllOverrides]
    "d3d9"="builtin"
    [HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\upc.exe\\DllOverrides]
    "d3d9"="builtin"
    [HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\UplayWebCore.exe\\DllOverrides]
    "d3d9"="builtin"
    [HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\Brawlhalla.exe\\DllOverrides]
    "d3d9"="native,builtin"

    [HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\Brawlhalla.exe\\Mac Driver]
    "ForceWindowControls"="Y"
    "NativeFullscreen"="Y"
    "FullscreenIgnoreMaxSize"="Y"
    "AllowImmovableWindows"="N"
    "AllowCursorClipping"="N"
    "CursorClippingLocksWindows"="N"
    "CaptureDisplaysForFullscreen"="N"
    "WindowsFloatWhenInactive"="none"
    "LeftCommandIsCtrl"="N"
    "RightCommandIsCtrl"="N"

    """
    public static func prepareGraphics(runtime: InstalledRuntime, prefix: URL, profile: GraphicsProfile) async throws {
        guard runtime.manifest.profiles.contains(.performance) else { return }
        let file = try FileSafety.containedURL("drive_c/crossedover/launcher-graphics.reg", in: prefix)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var bytes = Data([0xff, 0xfe]); bytes.append(graphicsRegistry.data(using: .utf16LittleEndian)!)
        try bytes.write(to: file, options: .atomic)
        let result = try await ProcessRunner.run(runtime.wine, arguments: ["regedit", "/S", "C:\\crossedover\\launcher-graphics.reg"],
            environment: environment(runtime: runtime, prefix: prefix, profile: profile), timeout: 15)
        guard result.status == 0 else { throw CrossedOverError.message("Could not prepare launcher and game graphics.") }
    }
    public static func launchURI(for game: GameInstallation) throws -> String {
        guard game.store == .epic, EpicDiscovery.validIdentifier(game.appID) else { throw CrossedOverError.message("Invalid Epic game identifier.") }
        var parts = [game.appID]
        if let namespace = game.epicNamespace, let item = game.epicCatalogItemID {
            guard EpicDiscovery.validIdentifier(namespace), EpicDiscovery.validIdentifier(item) else { throw CrossedOverError.message("Invalid Epic catalog identifier.") }
            parts = [namespace, item, game.appID]
        }
        return "com.epicgames.launcher://apps/" + parts.joined(separator: "%3A") + "?action=launch&silent=false"
    }
    public static func validateInstaller(_ file: URL, finalURL: URL) throws {
        let host = finalURL.host?.lowercased() ?? ""
        let official = host == "epicgames.com" || host.hasSuffix(".epicgames.com") || host == "unrealengine.com" || host.hasSuffix(".unrealengine.com") || host == "epicgames-download1.akamaized.net"
        guard finalURL.scheme == "https", official else { throw CrossedOverError.message("The Epic installer must come directly from Epic over HTTPS.") }
        let size = (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        guard size > 100_000, size < 1_073_741_824,
              try handle.read(upToCount: 8) == Data([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]) else {
            throw CrossedOverError.message("The Epic download is not a valid Windows MSI installer.")
        }
    }
    public func install(environment: ManagedEnvironment, runtime: InstalledRuntime) async throws {
        try Self.requireSupportedRuntime(runtime)
        guard environment.state == "ready" else { throw CrossedOverError.message("Repair the Windows environment before setting up Epic.") }
        let prefix = paths.prefix(environment), lock = try EnvironmentLock(prefix: paths.prefix(environment))
        defer { withExtendedLifetime(lock) {} }
        let (temporary, response) = try await URLSession.shared.download(from: Self.installerURL)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let finalURL = response.url else { throw CrossedOverError.message("Could not download Epic's Windows installer.") }
        try Self.validateInstaller(temporary, finalURL: finalURL)
        try Task.checkCancellation()
        let installer = try FileSafety.containedURL("drive_c/crossedover/EpicInstaller.msi", in: prefix)
        let logs = try FileSafety.containedURL("drive_c/crossedover/logs", in: prefix)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: installer.path) { try FileManager.default.removeItem(at: installer) }
        try FileManager.default.copyItem(at: temporary, to: installer)
        defer { try? FileManager.default.removeItem(at: installer) }
        let result = try await ProcessRunner.run(runtime.wine,
            arguments: ["msiexec", "/i", "C:\\crossedover\\EpicInstaller.msi", "/qn", "/norestart", "SHOULDRUNLAUNCHER=0", "/L*V", "C:\\crossedover\\logs\\epic-install.log"],
            workingDirectory: prefix.appendingPathComponent("drive_c"),
            environment: Self.environment(runtime: runtime, prefix: prefix, profile: environment.profile), timeout: 600)
        guard [0, 3010, 194].contains(result.status) else {
            throw CrossedOverError.message("Epic installation failed (code \(result.status)). Its installer log is in C:\\crossedover\\logs\\epic-install.log. \(Redaction.apply(result.output).suffix(600))")
        }
        _ = try Self.executable(prefix: prefix)
        try FileManager.default.createDirectory(at: Self.gamesFolder(prefix: prefix), withIntermediateDirectories: true)
    }
}

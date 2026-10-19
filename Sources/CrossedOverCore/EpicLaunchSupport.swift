import Foundation

/// Epic's external launch handler requires EOSH. Its bundled installer uses
/// managed MSI custom actions even though the launcher itself is native.
public enum EpicLaunchSupport {
    public static let monoURL = URL(string: "https://github.com/wine-mono/wine-mono/releases/download/wine-mono-10.4.1/wine-mono-10.4.1-x86.msi")!
    // Matches this Wine source's appwiz.cpl/addons.c, not a moving latest release.
    public static let monoSHA256 = "071f4b2887e1c97a11d791ff3d65be9429eed6dec4c2708888bfd546ba358e23"
    public static let repairMessage = "Epic’s launch helper is missing or outdated. Quit Windows games and launchers, then choose Settings → Windows Epic Games → Repair launch support."

    static func supportedVersion(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 256 else { return false }
        let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)[0].split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return false }
        return [major, minor, patch].lexicographicallyPrecedes([5, 3, 0]) == false
    }
    static func registeredVersion(_ registry: String) -> String? {
        var selected = false
        let sections = ["software\\wow6432node\\epic games\\eos\\mainservice", "software\\epic games\\eos\\mainservice"]
        for line in registry.split(whereSeparator: \.isNewline) {
            if line.first == "[" {
                selected = false
                if let end = line.firstIndex(of: "]") {
                    let name = line.dropFirst().prefix(upTo: end).replacingOccurrences(of: "\\\\", with: "\\").lowercased()
                    selected = sections.contains(name)
                }
            } else if selected, line.hasPrefix("\"Version\"="),
                      let version = try? JSONDecoder().decode(String.self, from: Data(line.dropFirst(10).utf8)),
                      supportedVersion(version) { return version }
        }
        return nil
    }
    static func host(prefix: URL) throws -> URL? {
        for base in ["Program Files (x86)", "Program Files"] {
            let file = try FileSafety.containedURL("drive_c/\(base)/Epic Games/Epic Online Services/service/EpicOnlineServicesHost.exe", in: prefix)
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return file }
        }
        return nil
    }
    public static func installedVersion(prefix: URL) throws -> String? {
        guard try host(prefix: prefix) != nil else { return nil }
        let registry = try FileSafety.containedURL("system.reg", in: prefix)
        guard let length = try? registry.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              length <= 64 * 1024 * 1024 else { return nil }
        return registeredVersion(try String(contentsOf: registry, encoding: .utf8))
    }
    static func installerEnvironment(runtime: InstalledRuntime, prefix: URL, profile: GraphicsProfile) -> [String: String] {
        var variables = EpicService.environment(runtime: runtime, prefix: prefix, profile: profile)
        // Respect a pre-existing native .NET installation; otherwise use Mono.
        variables["WINEDLLOVERRIDES"] = "winemetal,dxgi,d3d11,d3d10core=b;mscoree=n,b;mshtml="
        return variables
    }
    static func hasManagedRuntime(prefix: URL) throws -> Bool {
        for path in ["windows/mono/mono-2.0/lib/mono/4.5/mscorlib.dll",
                     "windows/Microsoft.NET/Framework/v4.0.30319/mscorlib.dll",
                     "windows/Microsoft.NET/Framework64/v4.0.30319/mscorlib.dll"] {
            let file = try FileSafety.containedURL("drive_c/" + path, in: prefix)
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return true }
        }
        return false
    }
    static func requireStopped(runtime: InstalledRuntime, prefix: URL, profile: GraphicsProfile) async throws {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let result = try await ProcessRunner.run(runtime.wineserver, arguments: ["-w"],
                    environment: WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: profile), timeout: 3)
                if result.status == 0 { return }
            } catch is CancellationError { throw CancellationError() }
            catch { /* Allow the idle Wine services to finish exiting. */ }
            if attempt < 2 { try await Task.sleep(for: .milliseconds(200)) }
        }
        throw CrossedOverError.message("Quit Steam, Epic, Ubisoft Connect, and Windows games/apps before repairing Epic launch support. Nothing was changed.")
    }
    /// Query the live registry after install/at launch: Wine may not have flushed
    /// system.reg yet. Never query account keys or include arbitrary output in UI.
    public static func requireReady(runtime: InstalledRuntime, prefix: URL, profile: GraphicsProfile) async throws {
        guard try host(prefix: prefix) != nil else { throw CrossedOverError.message(repairMessage) }
        let result = try await ProcessRunner.run(runtime.wine,
            arguments: ["reg.exe", "query", "HKLM\\Software\\Epic Games\\EOS\\MainService", "/v", "Version", "/reg:32"],
            workingDirectory: prefix.appendingPathComponent("drive_c"),
            environment: EpicService.environment(runtime: runtime, prefix: prefix, profile: profile), timeout: 15)
        let versions = result.output.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, fields[0] == "Version", fields[1] == "REG_SZ" else { return nil }
            return String(fields[2])
        }
        guard result.status == 0, versions.contains(where: supportedVersion) else { throw CrossedOverError.message(repairMessage) }
    }
}

extension EpicService {
    /// Explicit repair and fresh setup use the same vendor installer. No client
    /// or game is killed, and the ordinary Steam/game DLL overrides stay intact.
    public func repairLaunchSupport(environment: ManagedEnvironment, runtime: InstalledRuntime) async throws {
        try Self.requireSupportedRuntime(runtime)
        let prefix = paths.prefix(environment)
        let installer = try FileSafety.containedURL("Extras/EOS/EpicOnlineServicesInstaller.exe",
            in: Self.executable(prefix: prefix).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        guard (try? installer.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw CrossedOverError.message("Epic’s prerequisite installer is missing. Repair Windows Epic before retrying launch support.")
        }
        let lock = try EnvironmentLock(prefix: prefix)
        defer { withExtendedLifetime(lock) {} }
        try await EpicLaunchSupport.requireStopped(runtime: runtime, prefix: prefix, profile: environment.profile)
        let variables = EpicLaunchSupport.installerEnvironment(runtime: runtime, prefix: prefix, profile: environment.profile)
        let staging = try FileSafety.containedURL("drive_c/crossedover", in: prefix)
        let logs = try FileSafety.containedURL("logs", in: staging)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        if try !EpicLaunchSupport.hasManagedRuntime(prefix: prefix) {
            let (temporary, response) = try await URLSession.shared.download(from: EpicLaunchSupport.monoURL)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https",
                  (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) == 85_504_000 else {
                throw CrossedOverError.message("Could not download Epic’s managed-runtime prerequisite.")
            }
            try FileSafety.verify(temporary, sha256: EpicLaunchSupport.monoSHA256)
            try Task.checkCancellation()
            // A client may have been opened outside crossedover during download.
            try await EpicLaunchSupport.requireStopped(runtime: runtime, prefix: prefix, profile: environment.profile)
            let name = "mono-" + UUID().uuidString + ".msi"
            let msi = try FileSafety.containedURL(name, in: staging)
            try FileManager.default.copyItem(at: temporary, to: msi)
            defer { try? FileManager.default.removeItem(at: msi) }
            let result = try await ProcessRunner.run(runtime.wine,
                arguments: ["msiexec", "/i", "C:\\crossedover\\" + name, "/qn", "/norestart", "/L*V", "C:\\crossedover\\logs\\mono-install.log"],
                workingDirectory: staging, environment: variables, timeout: 180)
            guard [0, 194].contains(result.status) else { throw CrossedOverError.message("Epic’s managed-runtime prerequisite could not be installed (code \(result.status)). The local installer log is in C:\\crossedover\\logs\\mono-install.log.") }
        }
        try Task.checkCancellation()
        let result = try await ProcessRunner.run(runtime.wine,
            arguments: [installer.path, "/install", "productid=EpicGamesLauncher", "/quiet"],
            workingDirectory: installer.deletingLastPathComponent(), environment: variables, timeout: 180)
        guard [0, 194].contains(result.status) else { throw CrossedOverError.message("Epic’s launch helper installation failed (code \(result.status)). Its installer logs are in C:\\ProgramData\\Epic\\EpicOnlineServices\\EOSInstaller\\Logs.") }
        try await EpicLaunchSupport.requireReady(runtime: runtime, prefix: prefix, profile: environment.profile)
    }
}

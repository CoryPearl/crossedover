import Foundation

public actor SteamService {
    public let paths: AppPaths
    public init(paths: AppPaths) { self.paths = paths }
    public static func steamExecutable(prefix: URL) throws -> URL {
        for path in ["drive_c/Program Files (x86)/Steam/steam.exe", "drive_c/Program Files/Steam/steam.exe"] {
            let url = try FileSafety.containedURL(path, in: prefix)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        throw CrossedOverError.message("Install Windows Steam in this environment first.")
    }
    public static func gamesFolder(prefix: URL) throws -> URL {
        let steam = try steamExecutable(prefix: prefix).deletingLastPathComponent()
        let relative = String(steam.path.dropFirst(prefix.resolvingSymlinksInPath().path.count + 1))
        return try FileSafety.containedURL(relative + "/steamapps/common", in: prefix)
    }
    public func install(environment: ManagedEnvironment, runtime: InstalledRuntime) async throws {
        let prefix = paths.prefix(environment)
        let lock = try EnvironmentLock(prefix: prefix); defer { withExtendedLifetime(lock) {} }
        let download = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
        let (temporary, response) = try await URLSession.shared.download(from: download)
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https" else { throw CrossedOverError.message("Could not download the official Steam installer.") }
        let data = try Data(contentsOf: temporary)
        guard data.count > 100_000, data.count < 20_000_000, data.prefix(2) == Data([0x4d, 0x5a]) else { throw CrossedOverError.message("The Steam download is not a valid Windows installer.") }
        let installer = try FileSafety.containedURL("drive_c/crossedover/SteamSetup.exe", in: prefix)
        try FileManager.default.createDirectory(at: installer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: installer, options: .atomic)
        let result = try await ProcessRunner.run(runtime.steamLoader, arguments: [installer.path, "/S"], workingDirectory: prefix.appendingPathComponent("drive_c"), environment: WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: environment.profile), timeout: 300)
        guard result.status == 0 else { throw CrossedOverError.message("Steam installation failed: \(Redaction.apply(result.output).suffix(1200))") }
        _ = try Self.steamExecutable(prefix: prefix)
    }
}

import Foundation

/// Epic can delegate a game to Ubisoft Connect. These games have Ubisoft
/// install records rather than Epic .item manifests; keep their real source.
public struct UbisoftDiscovery: Sendable {
    public init() {}
    public static func executable(prefix: URL) throws -> URL {
        for directory in ["Program Files (x86)", "Program Files"] {
            // This is Ubisoft's registered uplay: handler. upc.exe is an
            // internal client and does not provide the same URL dispatch.
            let file = try FileSafety.containedURL("drive_c/\(directory)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe", in: prefix)
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return file }
        }
        throw CrossedOverError.message("Ubisoft Connect is not installed in this Windows environment. Open the game in Epic to complete its launcher setup.")
    }
    public static func launchURI(_ id: String) throws -> String {
        guard SteamDiscovery.validAppID(id) else { throw CrossedOverError.message("Invalid Ubisoft game identifier.") }
        return "uplay://launch/" + id + "/0"
    }
    public static func environment(runtime: InstalledRuntime, prefix: URL, profile: GraphicsProfile) -> [String: String] {
        EpicService.environment(runtime: runtime, prefix: prefix, profile: profile)
    }
    public func discover(environment: ManagedEnvironment, prefix: URL) throws -> [GameInstallation] {
        guard (try? Self.executable(prefix: prefix)) != nil else { return [] }
        let registry = try FileSafety.containedURL("system.reg", in: prefix)
        guard FileManager.default.fileExists(atPath: registry.path) else { return [] }
        guard (try registry.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 64 * 1024 * 1024 else { throw CrossedOverError.message("The Windows installation registry is too large to scan.") }
        let records = Self.installRecords(try String(contentsOf: registry, encoding: .utf8))
        var games: [GameInstallation] = []
        for (id, fields) in records.sorted(by: { $0.key < $1.key }) {
            guard let location = fields["InstallDir"] ?? fields["InstallLocation"],
                  let directory = try? EpicDiscovery.windowsPath(location, prefix: prefix),
                  (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = fields["DisplayName"] ?? directory.lastPathComponent
            guard !name.isEmpty, name.count <= 512 else { continue }
            // A registration alone is not enough: require an installed program.
            var game = GameInstallation(appID: id, environmentID: environment.id, name: name, directory: directory.path, sizeBytes: 0)
            game.source = .ubisoft
            if id == "16382" {
                let exe = try FileSafety.containedURL("Brawlhalla.exe", in: directory)
                guard (try? exe.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                game.launchExecutable = "Brawlhalla.exe"
            } else { guard !(try GameProcessDetection.executableNames(for: game, recipe: nil)).isEmpty else { continue } }
            for relative in ["icons/desktop128.png", ".egstore/cover.png"] {
                if let image = try? FileSafety.containedURL(relative, in: directory), FileManager.default.fileExists(atPath: image.path) { game.artworkPath = image.path; break }
            }
            games.append(game)
        }
        return games
    }
    /// Decode only the installation/uninstall sections, never account caches.
    static func installRecords(_ registry: String) -> [String: [String: String]] {
        var records: [String: [String: String]] = [:], current: String?
        let prefixes = ["software\\wow6432node\\ubisoft\\launcher\\installs\\", "software\\ubisoft\\launcher\\installs\\",
                        "software\\wow6432node\\microsoft\\windows\\currentversion\\uninstall\\uplay install ", "software\\microsoft\\windows\\currentversion\\uninstall\\uplay install "]
        for line in registry.split(whereSeparator: \.isNewline) {
            if line.first == "[" {
                current = nil
                guard let end = line.firstIndex(of: "]") else { continue }
                let section = line[line.index(after: line.startIndex)..<end].replacingOccurrences(of: "\\\\", with: "\\").lowercased()
                for prefix in prefixes where section.hasPrefix(prefix) {
                    let id = String(section.dropFirst(prefix.count))
                    if SteamDiscovery.validAppID(id), records.count < 5000 { current = id }
                }
            } else if let current, let split = line.firstIndex(of: "="),
                      let key = try? JSONDecoder().decode(String.self, from: Data(line[..<split].utf8)),
                      ["InstallDir", "InstallLocation", "DisplayName"].contains(key),
                      let value = try? JSONDecoder().decode(String.self, from: Data(line[line.index(after: split)...].utf8)), value.utf8.count < 32768 {
                records[current, default: [:]][key] = value
            }
        }
        return records
    }
}

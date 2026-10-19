import Foundation

public struct EpicDiscovery: Sendable {
    public init() {}
    public static let manifestsPath = "drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests"
    public static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.unicodeScalars.allSatisfy {
            (65...90).contains($0.value) || (97...122).contains($0.value) || (48...57).contains($0.value) || [45, 46, 95].contains($0.value)
        } && value != "." && value != ".."
    }
    public static func windowsPath(_ value: String, prefix: URL) throws -> URL {
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
        guard normalized.lowercased().hasPrefix("c:/"), normalized.utf8.count < 32_768 else { throw CrossedOverError.message("Epic games must be installed inside this Windows C: drive.") }
        return try FileSafety.containedURL("drive_c/" + normalized.dropFirst(3), in: prefix)
    }
    public func discover(environment: ManagedEnvironment, prefix: URL) throws -> [GameInstallation] {
        let fm = FileManager.default
        let manifests = try FileSafety.containedURL(Self.manifestsPath, in: prefix)
        let files = fm.fileExists(atPath: manifests.path) ? try fm.contentsOfDirectory(at: manifests, includingPropertiesForKeys: [.fileSizeKey]).filter { $0.pathExtension.lowercased() == "item" } : []
        guard files.count <= 5000 else { throw CrossedOverError.message("Epic has too many manifests to scan safely.") }
        var games: [String: GameInstallation] = [:]
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let contained = try FileSafety.containedURL(file.lastPathComponent, in: manifests)
            guard (try contained.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8_388_608 else { throw CrossedOverError.message("An Epic manifest is too large.") }
            guard let item = try JSONSerialization.jsonObject(with: Data(contentsOf: contained)) as? [String: Any] else { throw CrossedOverError.message("An Epic install manifest is incomplete. Retry after the download finishes.") }
            guard let appID = item["AppName"] as? String, Self.validIdentifier(appID),
                  let name = item["DisplayName"] as? String, !name.isEmpty, name.count <= 512,
                  let location = item["InstallLocation"] as? String,
                  let launch = item["LaunchExecutable"] as? String, !launch.isEmpty,
                  item["bIsIncompleteInstall"] as? Bool != true, item["bIsDLC"] as? Bool != true,
                  !appID.hasPrefix("UE_") else { continue }
            if let main = item["MainGameAppName"] as? String, !main.isEmpty, main != appID { continue }
            // Unsupported external-drive installs and invalid entries do not become cards.
            guard let directory = try? Self.windowsPath(location, prefix: prefix),
                  fm.fileExists(atPath: directory.path),
                  let executable = try? FileSafety.containedURL(launch.replacingOccurrences(of: "\\", with: "/"), in: directory),
                  (try? executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  !["epicgameslauncher.exe", "epicwebhelper.exe", "epiconlineservicesinstaller.exe"].contains(executable.lastPathComponent.lowercased()) else { continue }
            let namespace = item["CatalogNamespace"] as? String, catalog = item["CatalogItemId"] as? String
            guard namespace.map(Self.validIdentifier) ?? true, catalog.map(Self.validIdentifier) ?? true else { continue }
            var game = GameInstallation(appID: appID, environmentID: environment.id, name: name,
                directory: directory.path, sizeBytes: max(0, (item["InstallSize"] as? NSNumber)?.int64Value ?? 0))
            game.source = .epic; game.epicNamespace = namespace; game.epicCatalogItemID = catalog
            game.launchExecutable = launch.replacingOccurrences(of: "\\", with: "/")
            // Epic launch manifests do not guarantee local cover art. Use an extracted local icon/cover when present.
            for relative in [".egstore/cover.png", ".egstore/cover.jpg"] {
                if let cover = try? FileSafety.containedURL(relative, in: directory), fm.fileExists(atPath: cover.path) { game.artworkPath = cover.path; break }
            }
            games[appID] = game
        }
        // Epic deliberately stores externally managed games in this differently
        // named directory, without a normal .item installation manifest.
        let partners = try FileSafety.containedURL("drive_c/ProgramData/Epic/EpicGamesLauncher/Data/ThirPartyManagedApps", in: prefix)
        if fm.fileExists(atPath: partners.path) {
            let files = try fm.contentsOfDirectory(at: partners, includingPropertiesForKeys: [.fileSizeKey]).filter { $0.pathExtension.lowercased() == "json" }
            guard files.count <= 5000 else { throw CrossedOverError.message("Epic has too many partner installation records.") }
            let installed = try UbisoftDiscovery().discover(environment: environment, prefix: prefix)
            for file in files {
                let file = try FileSafety.containedURL(file.lastPathComponent, in: partners)
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_048_576,
                      let item = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else {
                    throw CrossedOverError.message("An Epic partner installation record is incomplete. Refresh after setup finishes.")
                }
                guard item["Provider"] as? String == "UbisoftConnect", item["RegistryKey"] as? String == "InstallDir",
                      let id = item["GameID"] as? String, SteamDiscovery.validAppID(id),
                      let appName = item["AppName"] as? String, Self.validIdentifier(appName),
                      let namespace = item["Namespace"] as? String, Self.validIdentifier(namespace),
                      let catalog = item["CatalogID"] as? String, Self.validIdentifier(catalog),
                      var game = installed.first(where: { $0.appID == id }) else { continue }
                // Never execute arbitrary AdditionalCommandArgs or registry paths
                // from metadata. Resolve the install from our fixed registry roots.
                game.appID = appName; game.source = .epic
                game.epicNamespace = namespace; game.epicCatalogItemID = catalog
                game.epicPartnerGameID = id
                games[appName] = game
            }
        }
        return games.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// A transient rewrite in one launcher must not erase the other store's library.
public enum GameLibrary {
    public static func discover(environment: ManagedEnvironment, prefix: URL, previous: [GameInstallation] = [], refreshSizes: Bool = false) -> [GameInstallation] {
        let steam = (try? SteamDiscovery().discover(environment: environment, prefix: prefix)) ?? previous.filter { $0.store == .steam && $0.environmentID == environment.id }
        let epic = (try? EpicDiscovery().discover(environment: environment, prefix: prefix)) ?? previous.filter { $0.store == .epic && $0.environmentID == environment.id }
        let ubisoft = (try? UbisoftDiscovery().discover(environment: environment, prefix: prefix)) ?? previous.filter { $0.store == .ubisoft && $0.environmentID == environment.id }
        let partners = ubisoft.filter { partner in !epic.contains { URL(fileURLWithPath: $0.directory).standardizedFileURL == URL(fileURLWithPath: partner.directory).standardizedFileURL } }
        return (steam + epic + partners).map { installation in
            var game = installation
            if game.sizeBytes <= 0,
               let bytes = GameInstallationSize.shared.size(in: URL(fileURLWithPath: game.directory), refresh: refreshSizes) {
                game.sizeBytes = bytes
            }
            return game
        }.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}

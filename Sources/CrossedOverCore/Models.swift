import Foundation

public enum CrossedOverError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { text } else { "Unknown error" } }
}

public enum GraphicsProfile: String, Codable, CaseIterable, Sendable, Identifiable {
    case legacy, performance, metal, combined
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .legacy: "OpenGL fallback"
        case .performance: "DirectX 9"
        case .metal: "DirectX 10–11"
        case .combined: "DirectX 9–11"
        }
    }
    public var explanation: String {
        switch self {
        case .legacy: "Uses Wine’s OpenGL renderer for older DirectX software. Try this if a Metal renderer has visual errors or fails to start. Performance and feature support are more limited."
        case .performance: "Uses DXVK and Metal for DirectX 9 apps and games. Choose this when software requires DirectX 9 and does not need DirectX 10 or 11."
        case .metal: "Uses DXMT to translate DirectX 10 and 11 to Metal. Choose this for software that requires either version; DirectX 9 uses the OpenGL fallback."
        case .combined: "Uses DXVK for DirectX 9 and DXMT for DirectX 10–11, both through Metal. Useful for mixed libraries or software with components that use different DirectX versions. Try a dedicated mode if compatibility differs."
        }
    }
    public var subtitle: String {
        switch self {
        case .legacy: "WineD3D · OpenGL"
        case .performance: "DXVK · Metal"
        case .metal: "DXMT · Metal"
        case .combined: "DXVK + DXMT · Metal"
        }
    }
}

public struct RuntimeManifest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var version: String
    public var architecture: String
    public var minimumMacOS: Int
    public var wineRelativePath: String
    public var wineserverRelativePath: String
    public var steamLoaderRelativePath: String?
    public var observerRelativePath: String?
    public var profiles: [GraphicsProfile]
    public var sourceURL: String
    public var sourceSHA256: String
    public var experimental: Bool
    public var fileHashes: [String: String]
    public var supportsMSync: Bool?
    public var x87RelativePath: String?
    /// Combined mode composes two existing backends; it does not require a new
    /// binary or change the on-disk runtime manifest's advertised components.
    public func supports(_ profile: GraphicsProfile) -> Bool {
        if profile == .combined { return profiles.contains(.performance) && profiles.contains(.metal) }
        return profiles.contains(profile)
    }
    public var graphicsProfiles: [GraphicsProfile] {
        [.combined, .metal, .performance, .legacy].filter(supports)
    }
    public init(id: String, name: String, version: String, wineRelativePath: String, wineserverRelativePath: String,
                profiles: [GraphicsProfile] = [.legacy], sourceURL: String, sourceSHA256: String,
                experimental: Bool = true, fileHashes: [String: String] = [:], observerRelativePath: String? = nil, supportsMSync: Bool = false, x87RelativePath: String? = nil, steamLoaderRelativePath: String? = nil) {
        schemaVersion = 1; self.id = id; self.name = name; self.version = version; architecture = "x86_64"
        minimumMacOS = 15; self.wineRelativePath = wineRelativePath; self.wineserverRelativePath = wineserverRelativePath
        self.profiles = profiles; self.sourceURL = sourceURL; self.sourceSHA256 = sourceSHA256
        self.experimental = experimental; self.fileHashes = fileHashes; self.observerRelativePath = observerRelativePath
        self.supportsMSync = supportsMSync
        self.x87RelativePath = x87RelativePath
        self.steamLoaderRelativePath = steamLoaderRelativePath
    }
}

public struct InstalledRuntime: Identifiable, Sendable, Equatable {
    public let manifest: RuntimeManifest
    public let root: URL
    public var id: String { manifest.id }
    public var wine: URL { root.appendingPathComponent(manifest.wineRelativePath) }
    public var wineserver: URL { root.appendingPathComponent(manifest.wineserverRelativePath) }
    public var steamLoader: URL { root.appendingPathComponent(manifest.steamLoaderRelativePath ?? manifest.wineRelativePath) }
}

public struct ManagedEnvironment: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var runtimeID: String
    public var profile: GraphicsProfile
    public var createdAt: Date
    public var state: String
    public init(runtimeID: String) {
        id = UUID(); name = "Windows"; self.runtimeID = runtimeID; profile = .legacy; createdAt = Date(); state = "creating"
    }
}

public enum GameStore: String, Codable, CaseIterable, Sendable, Identifiable {
    case steam, epic, ubisoft
    public var id: String { rawValue }
    public var title: String { switch self { case .steam: "Steam"; case .epic: "Epic Games"; case .ubisoft: "Ubisoft Connect" } }
}

public struct GameInstallation: Codable, Sendable, Identifiable, Equatable {
    public var appID: String
    public var environmentID: UUID
    public var name: String
    public var directory: String
    public var sizeBytes: Int64
    public var artworkPath: String? = nil
    // Optional on disk so existing Steam records decode without a migration.
    public var source: GameStore? = nil
    public var epicNamespace: String? = nil
    public var epicCatalogItemID: String? = nil
    public var epicPartnerGameID: String? = nil
    public var launchExecutable: String? = nil
    public var store: GameStore { source ?? .steam }
    public var managementStore: GameStore { epicPartnerGameID == nil ? store : .ubisoft }
    public var sessionAppID: String { store == .steam ? appID : store.rawValue + ":" + appID }
    public var id: String { "\(environmentID.uuidString):\(sessionAppID)" }
}

public struct GameRecipe: Codable, Sendable, Identifiable {
    public var appID: String
    public var name: String
    public var profile: GraphicsProfile
    public var executableNames: [String]
    public var status: String
    public var notes: String
    public var compatibleProfiles: [GraphicsProfile]?
    public var launchArguments: [String]? = nil
    public var id: String { appID }
}

public struct LaunchSession: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var appID: String
    public var environmentID: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var state: String
    public var detail: String?
    public init(id: UUID = UUID(), appID: String, environmentID: UUID, startedAt: Date = Date(), endedAt: Date? = nil, state: String, detail: String? = nil) {
        self.id = id; self.appID = appID; self.environmentID = environmentID; self.startedAt = startedAt
        self.endedAt = endedAt; self.state = state; self.detail = detail
    }
}

public struct OperationRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var kind: String
    public var state: String
    public var detail: String
    public var updatedAt: Date
    public var statusTitle: String {
        if state == "requested" || (state == "completed" && kind.hasPrefix("Launch ")) { return "Request sent" }
        if state == "started" { return "Running" }
        return state.capitalized
    }
    public init(kind: String, state: String, detail: String) {
        id = UUID(); self.kind = kind; self.state = state; self.detail = detail; updatedAt = Date()
    }
}

public struct ProcessObservation: Codable, Sendable {
    public var pid: UInt32
    public var executable: String
}

public struct AppPaths: Sendable {
    public var root: URL
    public var runtimes: URL { root.appendingPathComponent("Runtimes", isDirectory: true) }
    public var environments: URL { root.appendingPathComponent("Environments", isDirectory: true) }
    public var downloads: URL { root.appendingPathComponent("Downloads", isDirectory: true) }
    public var backups: URL { root.appendingPathComponent("Backups", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CrossedOver", isDirectory: true)
    }
    public func prefix(_ environment: ManagedEnvironment) -> URL { environments.appendingPathComponent(environment.id.uuidString, isDirectory: true) }
    public func prepare() throws {
        for url in [root, runtimes, environments, downloads, backups, logs] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}

public enum ResourceCatalog {
    static var bundle: Bundle {
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent("CrossedOver_CrossedOverCore.bundle")) { return bundle }
        return Bundle.module
    }
    public static func recipes() throws -> [GameRecipe] {
        try JSONDecoder().decode([GameRecipe].self, from: Data(contentsOf: bundle.url(forResource: "recipes", withExtension: "json")!))
    }
}

import Foundation

public struct RendererRecommendation: Sendable, Equatable {
    public let profile: GraphicsProfile?
    public let basis: String
    public let detail: String
    public var title: String { profile?.title ?? "DirectX 12 unavailable" }
    public var summary: String { "\(basis): \(title)" }

    public static func startingPoint(for game: GameInstallation, recipes: [GameRecipe]) -> Self {
        if game.store == .steam, let recipe = recipes.first(where: { $0.appID == game.appID }) {
            return Self(profile: recipe.profile, basis: "Recommended", detail: recipe.notes)
        }
        if game.managementStore == .ubisoft, game.launchExecutable?.lowercased() == "brawlhalla.exe" {
            return Self(profile: .performance, basis: "Recommended", detail: "Brawlhalla uses the DirectX 9 path selected by its launcher policy. Epic/Ubisoft manage that policy automatically; changing Steam's shared renderer is unnecessary.")
        }
        return Self(profile: .combined, basis: "Starting point", detail: "DirectX 9–11 covers mixed libraries. No specific graphics API was identified in the bounded executable check. This is a starting point, not a compatibility or performance guarantee. Games can load their renderer dynamically.")
    }

    static func from(imports: Set<String>) -> Self? {
        let dx9 = imports.contains("d3d9.dll")
        let dx11 = !imports.isDisjoint(with: ["d3d10.dll", "d3d10_1.dll", "d3d10core.dll", "d3d11.dll"])
        let dx12 = imports.contains("d3d12.dll")
        guard dx9 || dx11 || dx12 else { return nil }
        let api = dx9 && dx11 ? "DirectX 9 and 10–11" : dx9 ? "DirectX 9" : "DirectX 10–11"
        if dx12 && !dx9 && !dx11 {
            return Self(profile: nil, basis: "API detected", detail: "The inspected executable imports DirectX 12. This runtime has no DirectX 12 renderer. Check whether the game offers a DirectX 11 launch option; selecting a renderer here cannot add DirectX 12 support.")
        }
        return Self(profile: dx9 && dx11 ? .combined : dx9 ? .performance : .metal, basis: "Recommended", detail: "The inspected executable imports \(api)." + (dx12 ? " It also imports DirectX 12, which is unavailable here; select the game's DirectX 11 mode if offered." : "") + " Imported APIs are a hint, not proof of compatibility; the game may select another API at runtime.")
    }
}

/// Background-only, bounded discovery. Never scan from a SwiftUI body. Cache
/// unchanged installations and retry unknown results after updates/manual refresh.
public actor RendererRecommendations {
    public static let shared = RendererRecommendations()
    private struct Entry { let game: GameInstallation; let time: Date; let value: RendererRecommendation }
    private var cache: [String: Entry] = [:]

    public func recommendations(for games: [GameInstallation], recipes: [GameRecipe], refresh: Bool = false) -> [String: RendererRecommendation] {
        let ids = Set(games.map(\.id))
        cache = cache.filter { ids.contains($0.key) }
        var result: [String: RendererRecommendation] = [:]
        for game in games {
            let fallback = RendererRecommendation.startingPoint(for: game, recipes: recipes)
            if fallback.basis == "Recommended" {
                result[game.id] = fallback; continue
            }
            if !refresh, let entry = cache[game.id], entry.game == game, Date().timeIntervalSince(entry.time) < 300 {
                result[game.id] = entry.value; continue
            }
            let value = Self.inspect(game) ?? fallback
            cache[game.id] = Entry(game: game, time: Date(), value: value); result[game.id] = value
        }
        return result
    }

    private static func inspect(_ game: GameInstallation) -> RendererRecommendation? {
        let root = URL(fileURLWithPath: game.directory, isDirectory: true).resolvingSymlinksInPath()
        var executables: [URL] = []
        // A manifest's declared executable takes precedence over unrelated tools.
        if let relative = game.launchExecutable {
            guard let url = try? FileSafety.containedURL(relative, in: root) else { return nil }
            executables = [url]
        } else if let scan = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey], options: [.skipsHiddenFiles]) {
            var visited = 0
            for case let url as URL in scan {
                visited += 1; if visited > 1200 || executables.count >= 6 { break }
                if url.pathComponents.count - root.pathComponents.count > 6 { scan.skipDescendants(); continue }
                guard let info = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]), info.isSymbolicLink != true else { continue }
                let name = url.lastPathComponent.lowercased()
                guard info.isRegularFile == true, url.pathExtension.lowercased() == "exe",
                      !["crash", "setup", "redist", "unins", "launcher", "helper", "anticheat"].contains(where: { name.contains($0) }),
                      (try? FileSafety.containedURL(String(url.path.dropFirst(root.path.count + 1)), in: root)) != nil else { continue }
                executables.append(url)
            }
        }
        var imports = Set<String>()
        for url in executables {
            // Read a fixed prefix, not a potentially multi-GB executable/archive.
            guard let file = try? FileHandle(forReadingFrom: url) else { continue }
            let data = try? file.read(upToCount: 16 * 1024 * 1024)
            try? file.close()
            if let data { imports.formUnion(PEGraphicsImports.names(in: data)) }
        }
        return RendererRecommendation.from(imports: imports)
    }
}

/// Normal and RVA-based delay imports, following Microsoft's PE specification:
/// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
/// Invalid/truncated images yield no hint; strings in resources aren't imports.
enum PEGraphicsImports {
    static func names(in data: Data) -> Set<String> {
        func u16(_ p: Int) -> Int? {
            guard p >= 0, p <= data.count - 2 else { return nil }
            return Int(data[p]) | Int(data[p + 1]) << 8
        }
        func u32(_ p: Int) -> Int? {
            guard let a = u16(p), let b = u16(p + 2) else { return nil }
            return a | b << 16
        }
        guard data.count >= 64, u16(0) == 0x5a4d, let pe = u32(60), pe >= 64,
              u32(pe) == 0x4550, let machine = u16(pe + 4), [0x14c, 0x8664].contains(machine),
              let count = u16(pe + 6), (1...96).contains(count), let optionalSize = u16(pe + 20),
              let magic = u16(pe + 24), (machine == 0x14c && magic == 0x10b) || (machine == 0x8664 && magic == 0x20b) else { return [] }
        let optional = pe + 24, directory = optional + (magic == 0x20b ? 112 : 96)
        let sections = optional + optionalSize
        guard optionalSize >= directory - optional + 16, sections + count * 40 <= data.count,
              let directoryCount = u32(directory - 4), let headersSize = u32(optional + 60) else { return [] }
        func offset(_ rva: Int, length: Int) -> Int? {
            guard rva > 0 else { return nil }
            if rva < headersSize, rva + length <= min(headersSize, data.count) { return rva }
            for i in 0..<count {
                let p = sections + i * 40
                guard let va = u32(p + 12), let size = u32(p + 16), let raw = u32(p + 20), rva >= va else { continue }
                let delta = rva - va
                if delta + length <= size, raw + delta + length <= data.count { return raw + delta }
            }
            return nil
        }
        var names = Set<String>()
        for (index, stride, nameField) in [(1, 20, 12), (13, 32, 4)] {
            guard index < directoryCount, directory + (index + 1) * 8 <= sections,
                  let rva = u32(directory + index * 8), let size = u32(directory + index * 8 + 4), size >= stride else { continue }
            for i in 0..<min(size / stride, 256) {
                guard let p = offset(rva + i * stride, length: stride), let nameRVA = u32(p + nameField), nameRVA != 0 else { break }
                // Old delay tables can use absolute VAs; don't interpret as RVAs.
                if index == 13 && u32(p) != 1 { continue }
                guard offset(nameRVA, length: 1) != nil else { continue }
                var bytes: [UInt8] = []
                for j in 0..<128 {
                    guard let pos = offset(nameRVA + j, length: 1) else { break }
                    let byte = data[pos]
                    if byte == 0 {
                        if !bytes.isEmpty, let name = String(bytes: bytes, encoding: .ascii) { names.insert(name.lowercased()) }
                        break
                    }
                    bytes.append(byte)
                }
            }
        }
        return names
    }
}

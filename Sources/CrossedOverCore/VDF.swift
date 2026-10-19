import Foundation

public indirect enum VDFValue: Equatable, Sendable {
    case string(String), object([String: VDFValue])
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var object: [String: VDFValue]? { if case .object(let value) = self { value } else { nil } }
}

public enum VDF {
    public static func parse(_ input: String) throws -> [String: VDFValue] {
        guard input.utf8.count <= 8 * 1024 * 1024 else { throw CrossedOverError.message("Steam manifest is too large.") }
        var parser = Parser(Array(input))
        return try parser.object(depth: 0, nested: false)
    }
    private struct Parser {
        let characters: [Character]
        var cursor = 0
        init(_ characters: [Character]) { self.characters = characters }
        mutating func whitespace() {
            while cursor < characters.count {
                if characters[cursor].isWhitespace { cursor += 1 }
                else if characters[cursor] == "/", cursor + 1 < characters.count, characters[cursor + 1] == "/" {
                    while cursor < characters.count, characters[cursor] != "\n" { cursor += 1 }
                } else { break }
            }
        }
        mutating func token() throws -> String {
            whitespace()
            guard cursor < characters.count else { throw CrossedOverError.message("Incomplete Steam manifest.") }
            if characters[cursor] == "\"" {
                cursor += 1; var result = ""
                while cursor < characters.count {
                    let c = characters[cursor]; cursor += 1
                    if c == "\"" { return result }
                    if c == "\\", cursor < characters.count {
                        let next = characters[cursor]; cursor += 1
                        if next == "\\" || next == "\"" { result.append(next) }
                        else { result.append("\\"); result.append(next) }
                    } else { result.append(c) }
                }
                throw CrossedOverError.message("Unterminated Steam manifest string.")
            }
            var value = ""
            while cursor < characters.count, !characters[cursor].isWhitespace, characters[cursor] != "{", characters[cursor] != "}" {
                value.append(characters[cursor]); cursor += 1
            }
            guard !value.isEmpty else { throw CrossedOverError.message("Unexpected manifest token.") }
            return value
        }
        mutating func object(depth: Int, nested: Bool) throws -> [String: VDFValue] {
            guard depth < 32 else { throw CrossedOverError.message("Steam manifest nesting limit exceeded.") }
            var result: [String: VDFValue] = [:]
            while true {
                whitespace()
                if cursor == characters.count {
                    guard !nested else { throw CrossedOverError.message("Incomplete Steam manifest object.") }
                    return result
                }
                if characters[cursor] == "}" {
                    guard nested else { throw CrossedOverError.message("Unexpected manifest closing brace.") }
                    cursor += 1; return result
                }
                let key = try token().lowercased(); whitespace()
                if cursor < characters.count, characters[cursor] == "{" {
                    cursor += 1; result[key] = .object(try object(depth: depth + 1, nested: true))
                } else { result[key] = .string(try token()) }
            }
        }
    }
}

public struct SteamDiscovery: Sendable {
    public init() {}
    public func discover(environment: ManagedEnvironment, prefix: URL) throws -> [GameInstallation] {
        let fm = FileManager.default
        let roots = ["drive_c/Program Files (x86)/Steam", "drive_c/Program Files/Steam"]
        var libraries = Set<URL>()
        var steamRoots: [URL] = []
        for relative in roots {
            let steam = try FileSafety.containedURL(relative, in: prefix)
            if fm.fileExists(atPath: steam.path) { libraries.insert(steam); steamRoots.append(steam) }
            let file = steam.appendingPathComponent("steamapps/libraryfolders.vdf")
            if fm.fileExists(atPath: file.path) {
                let document = try VDF.parse(String(contentsOf: file, encoding: .utf8))
                for value in document["libraryfolders"]?.object?.values ?? Dictionary<String, VDFValue>().values {
                    guard let path = value.object?["path"]?.string, let converted = Self.windowsPath(path) else { continue }
                    libraries.insert(try FileSafety.containedURL(converted, in: prefix))
                }
            }
        }
        var games: [String: GameInstallation] = [:]
        for library in libraries {
            let steamapps = library.appendingPathComponent("steamapps")
            guard fm.fileExists(atPath: steamapps.path) else { continue }
            for file in try fm.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil) where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                let state = try VDF.parse(String(contentsOf: file, encoding: .utf8))["appstate"]?.object
                guard let appID = state?["appid"]?.string, Self.validAppID(appID),
                      let name = state?["name"]?.string, let directory = state?["installdir"]?.string,
                      let flags = Int(state?["stateflags"]?.string ?? ""), flags & 4 != 0 else { continue }
                let game = try FileSafety.containedURL("steamapps/common/" + directory, in: library)
                guard fm.fileExists(atPath: game.path) else { continue }
                var installation = GameInstallation(appID: appID, environmentID: environment.id, name: name, directory: game.path, sizeBytes: Int64(state?["sizeondisk"]?.string ?? "0") ?? 0)
                for steam in steamRoots {
                    for suffix in ["_library_600x900.jpg", "_library_hero.jpg", "_header.jpg"] {
                        guard let artwork = try? FileSafety.containedURL("appcache/librarycache/" + appID + suffix, in: steam) else { continue }
                        if fm.fileExists(atPath: artwork.path) { installation.artworkPath = artwork.path; break }
                    }
                    if installation.artworkPath != nil { break }
                }
                games[appID] = installation
            }
        }
        return games.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    public static func validAppID(_ value: String) -> Bool { !value.isEmpty && value.count <= 10 && value.allSatisfy(\.isNumber) && UInt32(value) != nil && value != "0" }
    private static func windowsPath(_ path: String) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard normalized.lowercased().hasPrefix("c:/") else { return nil }
        return "drive_c/" + normalized.dropFirst(3)
    }
}

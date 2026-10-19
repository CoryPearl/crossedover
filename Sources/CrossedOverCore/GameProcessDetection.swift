import Foundation

/// The Wine observer reports executable basenames, so unknown games use a
/// conservative inventory of their installed executables. This identifies
/// processes; it does not establish game compatibility.
public enum GameProcessDetection {
    public static func executableNames(for game: GameInstallation, recipe: GameRecipe?) throws -> [String] {
        if let recipe, recipe.appID == game.appID, !recipe.executableNames.isEmpty {
            return recipe.executableNames.map { $0.lowercased() }
        }
        let root = URL(fileURLWithPath: game.directory, isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        var scanError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, error in
            scanError = error; return false
        }) else { throw CrossedOverError.message("Could not read the game's installed files.") }
        var names = Set<String>()
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            guard visited <= 50_000 else { throw CrossedOverError.message("This game has too many files to track automatically. Use Windows Steam to manage it.") }
            let values = try url.resourceValues(forKeys: Set(keys))
            // Directory enumeration does not traverse symlinks. Calling
            // skipDescendants here can instead skip the next real directory.
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true, url.pathExtension.lowercased() == "exe" {
                names.insert(url.lastPathComponent.lowercased())
            }
        }
        if let scanError { throw scanError }
        return names.sorted()
    }
}

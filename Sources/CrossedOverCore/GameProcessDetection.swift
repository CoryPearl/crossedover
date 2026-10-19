import Foundation

/// The Wine observer reports executable basenames, so unknown games use a
/// conservative inventory of their installed executables. This identifies
/// processes; it does not establish game compatibility.
public enum GameProcessDetection {
    public static func executableNames(for game: GameInstallation, recipe: GameRecipe?) throws -> [String] {
        if game.store == .steam, let recipe, recipe.appID == game.appID, !recipe.executableNames.isEmpty {
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
            guard visited <= 50_000 else { throw CrossedOverError.message("This game has too many files to track automatically. Use its Windows launcher to manage it.") }
            let values = try url.resourceValues(forKeys: Set(keys))
            // Directory enumeration does not traverse symlinks. Calling
            // skipDescendants here can instead skip the next real directory.
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true, url.pathExtension.lowercased() == "exe" {
                let name = url.lastPathComponent.lowercased()
                if game.store != .steam && ["upc.exe", "ubisoftconnect.exe", "uplaywebcore.exe", "ubisoftgamelauncher.exe", "easyanticheat_eos_setup.exe", "epicgameslauncher.exe", "epicwebhelper.exe", "crashreportclient.exe", "unitycrashhandler64.exe", "ueprereqsetup_x64.exe", "dxsetup.exe", "vc_redist.x64.exe", "vc_redist.x86.exe"].contains(name) { continue }
                names.insert(name)
            }
        }
        if let scanError { throw scanError }
        return names.sorted()
    }
}

import Foundation

/// Builds removal targets without following links into other applications or libraries.
/// The app supplies its fixed Application Support location, even with a custom data-root override.
public enum ManagedStorage {
    public static func dataRoot(_ root: URL, expected: URL) throws -> URL {
        let root = root.standardizedFileURL, expected = expected.standardizedFileURL
        guard root == expected, root.pathComponents.count > 3,
              root.resolvingSymlinksInPath() == root,
              root != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL else {
            throw CrossedOverError.message("Removal is only available for crossedover's own data folder. A custom or linked data location must be managed in Finder.")
        }
        return root
    }
    public static func backups(in root: URL, expected: URL) throws -> URL {
        let root = try dataRoot(root, expected: expected)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: backups.path)) == nil else {
            throw CrossedOverError.message("The backups folder is a link. Manage it in Finder so current games and other data cannot be removed by mistake.")
        }
        return try FileSafety.containedURL("Backups", in: root)
    }
    public static func application(_ bundle: URL, identifier: String?) throws -> URL {
        let bundle = bundle.standardizedFileURL
        guard identifier == "org.crossedover.CrossedOver", bundle.pathExtension == "app",
              bundle.resolvingSymlinksInPath() == bundle,
              FileManager.default.isDeletableFile(atPath: bundle.path) else {
            throw CrossedOverError.message("Run crossedover from a writable Applications folder to uninstall it. Eject any installation disk image first.")
        }
        return bundle
    }
}

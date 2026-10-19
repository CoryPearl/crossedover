import Foundation

enum TrackManiaAudio {
    static let component = "audio/i386-windows/OpenAL32.dll"

    static func prepare(runtime: InstalledRuntime, game: GameInstallation, prefix: URL) throws {
        // Older runtimes remain usable. A manifest hash advertises this optional,
        // fixed-location component; never load an unlisted DLL from a runtime.
        guard let hash = runtime.manifest.fileHashes[component] else { return }
        let source = try FileSafety.containedURL(component, in: runtime.root)
        let directory = URL(fileURLWithPath: game.directory).standardizedFileURL
        let root = prefix.resolvingSymlinksInPath().standardizedFileURL
        guard directory.path.hasPrefix(root.path + "/") else { throw CrossedOverError.message("TrackMania's folder is outside its managed environment.") }
        let relative = String(directory.path.dropFirst(root.path.count + 1)) + "/OpenAL32.dll"
        try install(source: source, hash: hash, relativeDestination: relative, prefix: prefix)
    }

    static func install(source: URL, hash: String, relativeDestination: String, prefix: URL) throws {
        try FileSafety.verify(source, sha256: hash)
        let destination = try FileSafety.containedURL(relativeDestination, in: prefix)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        for file in [source, destination] {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? Int, size > 0, size < 32 * 1024 * 1024 else {
                throw CrossedOverError.message("The TrackMania audio library is not a supported file.")
            }
        }
        let originalHash = try FileSafety.sha256(destination)
        guard originalHash != hash else { return }
        // Keep every distinct original, including a later Steam repair/update.
        let backup = try FileSafety.containedURL("drive_c/crossedover/backups/trackmania-audio/\(originalHash).dll", in: prefix)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: backup.path) { try FileSafety.verify(backup, sha256: originalHash) }
        else { try Data(contentsOf: destination).write(to: backup, options: .withoutOverwriting) }
        try Data(contentsOf: source).write(to: destination, options: .atomic)
    }
}

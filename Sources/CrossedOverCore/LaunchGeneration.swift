import Foundation

/// Access under EnvironmentLock. A stopped environment must reject workers
/// that were queued before the stop, even if they have not started Wine yet.
enum LaunchGeneration {
    static func current(prefix: URL) throws -> String {
        let file = try FileSafety.containedURL(".crossedover-launch-generation", in: prefix)
        guard FileManager.default.fileExists(atPath: file.path) else { return "initial" }
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func invalidate(prefix: URL) throws {
        let file = try FileSafety.containedURL(".crossedover-launch-generation", in: prefix)
        try Data(UUID().uuidString.utf8).write(to: file, options: .atomic)
    }

    static func check(_ generation: String?, prefix: URL) throws {
        guard try (generation ?? "initial") == current(prefix: prefix) else {
            throw CrossedOverError.message("This launch was cancelled when the Windows environment stopped.")
        }
    }
}

import Foundation

/// Locations shared by Windows games and Finder. No per-game mod path is assumed.
public enum GameFiles {
    public static func documents(prefix: URL, userName: String = NSUserName()) throws -> URL {
        let users = try FileSafety.containedURL("drive_c/users", in: prefix)
        let candidates = [userName] + ((try? FileManager.default.contentsOfDirectory(atPath: users.path)) ?? [])
            .filter { ![userName, "Public", "Default", "Default User", "All Users"].contains($0) && !$0.hasPrefix(".") }
            .sorted()
        for user in candidates {
            for name in ["Documents", "My Documents"] {
                let folder = try FileSafety.containedURL("drive_c/users/\(user)/\(name)", in: prefix)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue { return folder }
            }
        }
        throw CrossedOverError.message("Windows Documents isn't available yet. Set up Steam first, then launch the game once so it can create its folders.")
    }
}

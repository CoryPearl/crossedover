import Foundation

public enum CS2WindowSettings {
    /// A one-time migration from borderless to a framed desktop window. Later
    /// user changes are preserved; Wine's fullscreen policy handles the green button.
    public static func prepare(prefix: URL) throws {
        let steam = try SteamService.steamExecutable(prefix: prefix).deletingLastPathComponent()
        let users = try FileSafety.containedURL("userdata", in: steam)
        guard FileManager.default.fileExists(atPath: users.path) else { return }
        for account in try FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil) {
            guard let file = try? FileSafety.containedURL("userdata/" + account.lastPathComponent + "/730/local/cfg/cs2_video.txt", in: steam),
                  FileManager.default.fileExists(atPath: file.path) else { continue }
            try prepare(file: file)
        }
    }

    static func prepare(file: URL) throws {
        try prepareWindow(file: file)
        try prepareClarity(file: file)
    }

    private static func prepareWindow(file: URL) throws {
        let marker = file.appendingPathExtension("crossedover-native-window-v2")
        let backup = file.appendingPathExtension("crossedover-native-window-v2.bak")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: marker.path) else { return }
        let original = try Data(contentsOf: file)
        guard original.count <= 1_048_576, var text = String(data: original, encoding: .utf8) else {
            throw CrossedOverError.message("Could not read CS2's video settings.")
        }
        for (key, value) in [("setting.fullscreen", "0"), ("setting.nowindowborder", "0"), ("setting.defaultres", "1280"), ("setting.defaultresheight", "720")] {
            let expression = try NSRegularExpression(pattern: "\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*\"([^\"]*)\"")
            guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else {
                throw CrossedOverError.message("CS2's video settings are incomplete. Open the game once before applying its window controls.")
            }
            text.replaceSubrange(range, with: value)
        }
        if !fm.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
        try Data(text.utf8).write(to: file, options: .atomic)
        try Data("Native window controls configured.\n".utf8).write(to: marker, options: .atomic)
    }

    /// Disable the game's internal low-resolution upscaler once. Value zero is
    /// FSR Disabled in CS2's shipped settings_video.xml; no display-wide DPI change.
    private static func prepareClarity(file: URL) throws {
        let marker = file.appendingPathExtension("crossedover-clarity-v1")
        let backup = file.appendingPathExtension("crossedover-clarity-v1.bak")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: marker.path) else { return }
        let original = try Data(contentsOf: file)
        guard original.count <= 1_048_576, var text = String(data: original, encoding: .utf8) else {
            throw CrossedOverError.message("Could not read CS2's video settings.")
        }
        let expression = try NSRegularExpression(pattern: "\"setting\\.videocfg_fsr_detail\"\\s*\"([0-4])\"")
        guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return }
        text.replaceSubrange(range, with: "0")
        if !fm.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
        try Data(text.utf8).write(to: file, options: .atomic)
        try Data("Internal FSR upscaling disabled. Later user choices are preserved.\n".utf8).write(to: marker, options: .atomic)
    }
}

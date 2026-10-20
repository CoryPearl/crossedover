import Foundation

public enum CS2WindowSettings {
    /// A one-time migration from borderless to a framed desktop window. Later
    /// user changes are preserved; Wine's fullscreen policy handles the green button.
    public static func prepare(prefix: URL) throws {
        let steam = try SteamService.steamExecutable(prefix: prefix).deletingLastPathComponent()
        let config = try FileSafety.containedURL("drive_c/crossedover/cs2-presentation.conf", in: prefix)
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# crossedover CS2 presentation policy; other executables keep defaults.\n[cs2.exe]\nd3d11.preferredMaxFrameRate = 60\n".utf8).write(to: config, options: .atomic)
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
        try preparePerformance(file: file)
        try prepareResolution(file: file)
    }

    /// Upgrade the old 720p preset once. Preserve higher/custom dimensions and
    /// every later in-game resolution choice; launch arguments no longer force 720p.
    private static func prepareResolution(file: URL) throws {
        let marker = file.appendingPathExtension("crossedover-resolution-v1")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let original = try Data(contentsOf: file)
        guard original.count <= 1_048_576, var text = String(data: original, encoding: .utf8) else {
            throw CrossedOverError.message("Could not read CS2's video settings.")
        }
        let width = try NSRegularExpression(pattern: "\"setting\\.defaultres\"\\s*\"([0-9]+)\"")
        let height = try NSRegularExpression(pattern: "\"setting\\.defaultresheight\"\\s*\"([0-9]+)\"")
        guard let w = width.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let h = height.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let wr = Range(w.range(at: 1), in: text), let hr = Range(h.range(at: 1), in: text) else { return }
        if text[wr] == "1280", text[hr] == "720" {
            // Work backwards so replacing one number cannot shift the other range.
            for (range, value) in [(w.range(at: 1), "1600"), (h.range(at: 1), "900")].sorted(by: { $0.0.location > $1.0.location }) {
                text.replaceSubrange(Range(range, in: text)!, with: value)
            }
            let backup = file.appendingPathExtension("crossedover-resolution-v1.bak")
            if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
            try Data(text.utf8).write(to: file, options: .atomic)
        }
        try Data("Resolution policy checked; later resolution choices preserved.\n".utf8).write(to: marker, options: .atomic)
    }

    /// Lower scene-rendering cost once, without resetting window/input settings or
    /// repeatedly overriding the user's later choices. Values match the game's
    /// shipped settings_video.xml. Keep all dynamic shadows for opponent visibility.
    private static func preparePerformance(file: URL) throws {
        let marker = file.appendingPathExtension("crossedover-performance-v1")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let original = try Data(contentsOf: file)
        guard original.count <= 1_048_576, var text = String(data: original, encoding: .utf8) else {
            throw CrossedOverError.message("Could not read CS2's video settings.")
        }
        let settings = [
            "setting.msaa_samples": "0", "setting.r_csgo_cmaa_enable": "0",
            "setting.videocfg_shadow_quality": "0", "setting.videocfg_dynamic_shadows": "1",
            "setting.videocfg_texture_detail": "0", "setting.videocfg_particle_detail": "0",
            "setting.videocfg_ao_detail": "0", "setting.shaderquality": "0",
            "setting.videocfg_hdr_detail": "3", "setting.mat_vsync": "0"
        ]
        var found = false
        for (key, value) in settings.sorted(by: { $0.key < $1.key }) {
            let expression = try NSRegularExpression(pattern: "\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*\"(-?[0-9]+)\"")
            guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            text.replaceSubrange(range, with: value); found = true
        }
        // Don't mark a pre-install/incomplete configuration as tuned.
        guard found else { return }
        let backup = file.appendingPathExtension("crossedover-performance-v1.bak")
        if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
        try Data(text.utf8).write(to: file, options: .atomic)
        try Data("60 FPS target: low scene detail, MSAA/AO off, dynamic shadows retained. Later user choices are preserved.\n".utf8).write(to: marker, options: .atomic)
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

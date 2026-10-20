import Foundation
import Testing
@testable import CrossedOverCore

struct CS2WindowSettingsTests {
    @Test func performanceMigrationReducesSceneCostOnceAndKeepsWindowAudioAndClarity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cs2_video.txt")
        let original = """
        "video.cfg"
        {
            "setting.msaa_samples" "2"
            "setting.videocfg_texture_detail" "1"
            "setting.videocfg_particle_detail" "1"
            "setting.videocfg_shadow_quality" "1"
            "setting.videocfg_dynamic_shadows" "1"
            "setting.videocfg_ao_detail" "3"
            "setting.videocfg_fsr_detail" "0"
            "setting.fullscreen" "1"
            "setting.defaultres" "1920"
            "setting.defaultresheight" "1080"
            "setting.audio_unknown" "preserve"
        }
        """
        try Data(original.utf8).write(to: file)
        try Data().write(to: file.appendingPathExtension("crossedover-native-window-v2"))
        try CS2WindowSettings.prepare(file: file)
        let first = try String(contentsOf: file, encoding: .utf8)
        for key in ["msaa_samples", "videocfg_texture_detail", "videocfg_particle_detail", "videocfg_shadow_quality", "videocfg_ao_detail"] {
            #expect(first.contains("\"setting.\(key)\" \"0\""))
        }
        #expect(first.contains("\"setting.videocfg_dynamic_shadows\" \"1\""))
        #expect(first.contains("\"setting.fullscreen\" \"1\""))
        #expect(first.contains("\"setting.defaultres\" \"1920\""))
        #expect(first.contains("\"setting.videocfg_fsr_detail\" \"0\""))
        #expect(first.contains("\"setting.audio_unknown\" \"preserve\""))
        let backup = file.appendingPathExtension("crossedover-performance-v1.bak")
        #expect(try Data(contentsOf: backup) == Data(original.utf8))
        let later = first.replacingOccurrences(of: "\"setting.msaa_samples\" \"0\"", with: "\"setting.msaa_samples\" \"4\"")
        try Data(later.utf8).write(to: file)
        try CS2WindowSettings.prepare(file: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == later)
        #expect(try Data(contentsOf: backup) == Data(original.utf8))
    }
    @Test func clarityMigrationKeepsExistingFullscreenResolutionAndBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cs2_video.txt")
        let original = "\"setting.fullscreen\" \"1\"\n\"setting.defaultres\" \"1920\"\n\"setting.defaultresheight\" \"1080\"\n\"setting.videocfg_fsr_detail\" \"2\"\n"
        try Data(original.utf8).write(to: file)
        try Data().write(to: file.appendingPathExtension("crossedover-native-window-v2"))
        try CS2WindowSettings.prepare(file: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == original.replacingOccurrences(of: "\"setting.videocfg_fsr_detail\" \"2\"", with: "\"setting.videocfg_fsr_detail\" \"0\""))
        #expect(try Data(contentsOf: file.appendingPathExtension("crossedover-clarity-v1.bak")) == Data(original.utf8))
    }

    @Test func borderlessMigrationPreservesUnknownSettingsBackupAndLaterUserChoices() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cs2_video.txt")
        let original = """
        "video.cfg"
        {
            "setting.fullscreen" "0"
            "setting.nowindowborder" "1"
            "setting.defaultres" "1512"
            "setting.defaultresheight" "982"
            "setting.videocfg_fsr_detail" "2"
            "setting.unknown_future_quality" "keep-this"
        }
        """
        try Data(original.utf8).write(to: file)
        // Existing installations already have the first migration marker.
        // It must not prevent the new framed-window repair or lose its backup.
        try Data().write(to: file.appendingPathExtension("crossedover-native-window-v1"))
        let oldBackup = file.appendingPathExtension("crossedover-native-window-v1.bak")
        try Data("earlier settings backup".utf8).write(to: oldBackup)
        try CS2WindowSettings.prepare(file: file)
        let first = try String(contentsOf: file, encoding: .utf8)
        #expect(first.contains("\"setting.nowindowborder\" \"0\""))
        #expect(first.contains("\"setting.defaultres\" \"1280\""))
        #expect(first.contains("\"setting.defaultresheight\" \"720\""))
        #expect(first.contains("\"setting.videocfg_fsr_detail\" \"0\""))
        #expect(first.contains("\"setting.unknown_future_quality\" \"keep-this\""))
        let backup = file.appendingPathExtension("crossedover-native-window-v2.bak")
        #expect(try Data(contentsOf: backup) == Data(original.utf8))
        #expect(try String(contentsOf: oldBackup, encoding: .utf8) == "earlier settings backup")
        let userChoice = first.replacingOccurrences(of: "\"1280\"", with: "\"1440\"")
            .replacingOccurrences(of: "\"setting.videocfg_fsr_detail\" \"0\"", with: "\"setting.videocfg_fsr_detail\" \"1\"")
        try Data(userChoice.utf8).write(to: file)
        try CS2WindowSettings.prepare(file: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == userChoice)
        #expect(try Data(contentsOf: backup) == Data(original.utf8))
    }
}

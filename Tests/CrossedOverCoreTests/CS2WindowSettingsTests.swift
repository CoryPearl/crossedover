import Foundation
import Testing
@testable import CrossedOverCore

struct CS2WindowSettingsTests {
    @Test func presentationPolicyIsScopedToCS2AndLaterResolutionChoicesSurviveLaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let steam = root.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        let file = steam.appendingPathComponent("userdata/123/730/local/cfg/cs2_video.txt")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let registry = root.appendingPathComponent("user.reg")
        let registryBefore = Data("Owned fixture: preserve Steam registry state.\n".utf8)
        try registryBefore.write(to: registry)
        try Data().write(to: steam.appendingPathComponent("steam.exe"))
        try Data("\"setting.defaultres\" \"1280\"\n\"setting.defaultresheight\" \"720\"\n".utf8).write(to: file)
        try Data().write(to: file.appendingPathExtension("crossedover-native-window-v2"))
        try CS2WindowSettings.prepare(prefix: root)
        #expect(try Data(contentsOf: registry) == registryBefore)
        let first = try String(contentsOf: file, encoding: .utf8)
        #expect(first.contains("\"setting.defaultres\" \"1600\""))
        #expect(first.contains("\"setting.defaultresheight\" \"900\""))
        let config = try String(contentsOf: root.appendingPathComponent("drive_c/crossedover/cs2-presentation.conf"), encoding: .utf8)
        #expect(config.contains("[cs2.exe]\nd3d11.preferredMaxFrameRate = 60"))
        #expect(!config.contains("metalfx"))
        let later = first.replacingOccurrences(of: "1600", with: "1920").replacingOccurrences(of: "900", with: "1080")
        try Data(later.utf8).write(to: file)
        try CS2WindowSettings.prepare(prefix: root)
        #expect(try String(contentsOf: file, encoding: .utf8) == later)
        let runtime = InstalledRuntime(manifest: RuntimeManifest(id: "fixture", name: "Fixture", version: "1", wineRelativePath: "wine", wineserverRelativePath: "wineserver", sourceURL: "fixture", sourceSHA256: "fixture"), root: root)
        #expect(WineConfiguration.environment(runtime: runtime, prefix: root, profile: .metal)["DXMT_CONFIG_FILE"] == "C:\\crossedover\\cs2-presentation.conf")
        #expect(WineConfiguration.environment(runtime: runtime, prefix: root, profile: .performance)["DXMT_CONFIG_FILE"] == nil)
        let recipe = try #require(ResourceCatalog.recipes().first { $0.appID == "730" })
        #expect(recipe.launchArguments?.contains("-w") == false)
        #expect(recipe.launchArguments?.contains("-h") == false)
        #expect(recipe.launchArguments?.suffix(2) == ["+fps_max", "60"])
        #expect(recipe.launchArguments?.contains("-insecure") == false)
        #expect(recipe.launchArguments?.contains("-allow_third_party_software") == false)
        let policy = try #require(GameWindowingPolicy.registry(for: "730"))
        #expect(policy.contains("\"gameoverlayrenderer\"=-"))
        #expect(policy.contains("\"gameoverlayrenderer64\"=-"))
        #expect(!policy.contains("\"gameoverlayrenderer64\"=\"\""))
    }
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
        #expect(first.contains("\"setting.defaultres\" \"1600\""))
        #expect(first.contains("\"setting.defaultresheight\" \"900\""))
        #expect(first.contains("\"setting.videocfg_fsr_detail\" \"0\""))
        #expect(first.contains("\"setting.unknown_future_quality\" \"keep-this\""))
        let backup = file.appendingPathExtension("crossedover-native-window-v2.bak")
        #expect(try Data(contentsOf: backup) == Data(original.utf8))
        #expect(try String(contentsOf: oldBackup, encoding: .utf8) == "earlier settings backup")
        let userChoice = first.replacingOccurrences(of: "\"1600\"", with: "\"1920\"")
            .replacingOccurrences(of: "\"setting.videocfg_fsr_detail\" \"0\"", with: "\"setting.videocfg_fsr_detail\" \"1\"")
        try Data(userChoice.utf8).write(to: file)
        try CS2WindowSettings.prepare(file: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == userChoice)
        #expect(try Data(contentsOf: backup) == Data(original.utf8))
    }
}

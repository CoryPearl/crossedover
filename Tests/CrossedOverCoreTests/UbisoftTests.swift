import Foundation
import Testing
@testable import CrossedOverCore

@Suite struct UbisoftTests {
    @Test func discoversEpicHandoffFromInstallRegistryAndRemovesUninstalledGame() throws {
        let (paths, _, environment, runtime) = try EpicTests().fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let prefix = paths.prefix(environment)
        let launcher = prefix.appendingPathComponent("drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: launcher)
        let folder = launcher.deletingLastPathComponent().appendingPathComponent("games/Brawlhalla")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("icons"), withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("Brawlhalla.exe"))
        try Data().write(to: folder.appendingPathComponent("icons/desktop128.png"))
        let registry = #"""
        WINE REGISTRY Version 2
        [Software\\Wow6432Node\\Ubisoft\\Launcher\\Installs\\16382] 1
        "InstallDir"="C:/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/games/Brawlhalla/"
        [Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Uplay Install 16382] 1
        "DisplayName"="Brawlhalla"
        [Software\\Ubisoft\\Account] 1
        "DisplayName"="Not a game"
        "InstallDir"="C:/somewhere"
        "exchangeCode"="never-export-this"
        """#
        try registry.write(to: prefix.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
        let games = try UbisoftDiscovery().discover(environment: environment, prefix: prefix)
        let game = try #require(games.first)
        #expect(games.count == 1); #expect(game.source == .ubisoft)
        #expect(game.name == "Brawlhalla"); #expect(game.sessionAppID == "ubisoft:16382")
        #expect(game.launchExecutable == "Brawlhalla.exe"); #expect(game.artworkPath?.hasSuffix("desktop128.png") == true)
        #expect(GameLibrary.discover(environment: environment, prefix: prefix).contains { $0.id == game.id })
        #expect(UbisoftDiscovery.installRecords(registry)["16382"]?["exchangeCode"] == nil)
        let partnerFolder = prefix.appendingPathComponent("drive_c/ProgramData/Epic/EpicGamesLauncher/Data/ThirPartyManagedApps")
        try FileManager.default.createDirectory(at: partnerFolder, withIntermediateDirectories: true)
        let partner = partnerFolder.appendingPathComponent("partner.json")
        try JSONSerialization.data(withJSONObject: ["Provider": "UbisoftConnect", "RegistryKey": "InstallDir", "GameID": "16382", "AppName": "epic-brawl", "Namespace": "epic-ns", "CatalogID": "epic-item", "AdditionalCommandArgs": ";touch /tmp/not-a-command", "RegistryPath": "arbitrary/untrusted"]).write(to: partner)
        let merged = GameLibrary.discover(environment: environment, prefix: prefix)
        #expect(merged.count == 1)
        let epic = try #require(merged.first)
        #expect(epic.source == .epic); #expect(epic.epicPartnerGameID == "16382")
        #expect(epic.directory == game.directory)
        #expect(try EpicService.launchURI(for: epic) == "com.epicgames.launcher://apps/epic-ns%3Aepic-item%3Aepic-brawl?action=launch&silent=false")
        // Keep the Epic card identity while dispatching to the installed
        // Ubisoft URL bootstrapper, even with a stale cold-Epic hint.
        let original = try String(contentsOf: runtime.wine, encoding: .utf8)
        try original.replacingOccurrences(of: "#!/bin/sh\n", with: "#!/bin/sh\n/usr/bin/printf '%s\\n' \"$@\" >> \"$WINEPREFIX/launch-order.txt\"\n").write(to: runtime.wine, atomically: true, encoding: .utf8)
        var request = SupervisorRequest(root: paths.root, environmentID: environment.id, command: .launchEpicGame, appID: epic.appID)
        request.primeEpic = true
        let requestFile = paths.logs.appendingPathComponent(".launch-partner.json")
        try JSONEncoder().encode(request).write(to: requestFile)
        try SupervisorEngine.runLaunchWorker(requestFile: requestFile)
        let actual = try String(contentsOf: prefix.appendingPathComponent("launch-order.txt"), encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(actual == [launcher.path, "uplay://launch/16382/0"])
        try FileManager.default.removeItem(at: folder)
        #expect(try UbisoftDiscovery().discover(environment: environment, prefix: prefix).isEmpty)
        #expect(try EpicDiscovery().discover(environment: environment, prefix: prefix).isEmpty)
    }
    @Test func rejectsTraversalExternalDrivesAndLinksInPartnerInstallRecords() throws {
        let (paths, _, environment, _) = try EpicTests().fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let prefix = paths.prefix(environment)
        let launcher = prefix.appendingPathComponent("drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: launcher)
        let outside = paths.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data().write(to: outside.appendingPathComponent("Brawlhalla.exe"))
        try FileManager.default.createSymbolicLink(at: prefix.appendingPathComponent("drive_c/linked"), withDestinationURL: outside)
        for location in ["D:/outside", "C:/../../outside", "C:/linked"] {
            let registry = "[Software\\\\Ubisoft\\\\Launcher\\\\Installs\\\\16382]\n\"InstallDir\"=\"\(location)\"\n"
            try registry.write(to: prefix.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
            #expect(try UbisoftDiscovery().discover(environment: environment, prefix: prefix).isEmpty)
        }
        #expect(throws: Error.self) { try UbisoftDiscovery.launchURI("16382;echo bad") }
        #expect(try UbisoftDiscovery.launchURI("16382") == "uplay://launch/16382/0")
    }
    @Test func partnerGraphicsRetainsMetalAndEnablesD3D9WithoutSteamBranding() throws {
        let (paths, _, environment, original) = try EpicTests().fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var manifest = original.manifest; manifest.profiles = [.legacy, .performance, .metal]
        let runtime = InstalledRuntime(manifest: manifest, root: original.root)
        let variables = UbisoftDiscovery.environment(runtime: runtime, prefix: paths.prefix(environment), profile: .legacy)
        #expect(variables["WINEDLLOVERRIDES"]?.contains("d3d9=") == false)
        #expect(variables["WINEDLLPATH"]?.hasSuffix("dxmt") == true)
        #expect(variables["CROSSEDOVER_STEAM_BRANDING"] == nil)
        #expect(variables["DXVK_HUD"] == "0")
        #expect(environment.profile == .legacy)
        #expect(!WineConfiguration.environment(runtime: runtime, prefix: paths.prefix(environment), profile: .legacy)["WINEDLLOVERRIDES"]!.contains("d3d9=n"))
    }
    @Test func thirdPartyExchangeCodesAreRedactedInFull() {
        let redacted = Redaction.apply("safe\nuplay://launch/1?exchangeCode=private&epicuid=other\nAuthorization: secret\nremaining")
        #expect(!redacted.contains("private")); #expect(!redacted.contains("other")); #expect(!redacted.contains("secret"))
        #expect(redacted.contains("safe")); #expect(redacted.contains("remaining"))
    }
}

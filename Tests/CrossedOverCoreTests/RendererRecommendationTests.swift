import Foundation
import Testing
@testable import CrossedOverCore

struct RendererRecommendationTests {
    private func image(name: String = "D3D11.dll", wide: Bool = true, delay: Bool = false) -> Data {
        var d = Data(repeating: 0, count: 2048)
        func put(_ at: Int, _ value: Int, bytes: Int = 4) { for i in 0..<bytes { d[at + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) } }
        put(0, 0x5a4d, bytes: 2); put(60, 128); put(128, 0x4550)
        put(132, wide ? 0x8664 : 0x14c, bytes: 2); put(134, 1, bytes: 2)
        let optionalSize = wide ? 240 : 224, optional = 152
        put(148, optionalSize, bytes: 2); put(optional, wide ? 0x20b : 0x10b, bytes: 2)
        put(optional + 60, 512)
        let directories = optional + (wide ? 112 : 96), section = optional + optionalSize
        put(directories - 4, 16)
        put(directories + (delay ? 13 : 1) * 8, 0x1000)
        put(directories + (delay ? 13 : 1) * 8 + 4, delay ? 64 : 40)
        put(section + 12, 0x1000); put(section + 16, 1024); put(section + 20, 512)
        if delay { put(512, 1) }
        put(512 + (delay ? 4 : 12), 0x1100)
        d.replaceSubrange(768..<(768 + name.utf8.count), with: name.utf8)
        return d
    }

    @Test func parsesBothArchitecturesAndDelayImportsWithoutSearchingArbitraryStrings() {
        for wide in [true, false] {
            for delay in [true, false] {
                #expect(PEGraphicsImports.names(in: image(wide: wide, delay: delay)) == ["d3d11.dll"])
            }
        }
        var resourceOnly = image(name: "kernel32.dll")
        resourceOnly.replaceSubrange(1600..<1609, with: "d3d12.dll".utf8)
        #expect(!PEGraphicsImports.names(in: resourceOnly).contains("d3d12.dll"))
        #expect(PEGraphicsImports.names(in: Data("MZ d3d11.dll".utf8)).isEmpty)
    }

    @Test func malformedHeadersRvasAndTruncationAreSafe() {
        let valid = image()
        for count in [0, 1, 63, 128, 155, 400, 512, 770] {
            #expect(PEGraphicsImports.names(in: Data(valid.prefix(count))).isEmpty)
        }
        var bad = valid
        bad[60] = 0xff; bad[61] = 0xff; bad[62] = 0xff; bad[63] = 0xff
        #expect(PEGraphicsImports.names(in: bad).isEmpty)
        bad = valid; bad[524] = 0xff; bad[525] = 0xff; bad[526] = 0xff; bad[527] = 0xff
        #expect(PEGraphicsImports.names(in: bad).isEmpty)
        bad = image(delay: true); bad[512] = 0 // VA based delay descriptor unsupported
        #expect(PEGraphicsImports.names(in: bad).isEmpty)
    }

    @Test func recommendationsMatchApisWithoutClaimingDirectX12Support() {
        #expect(RendererRecommendation.from(imports: ["d3d9.dll"])?.profile == .performance)
        #expect(RendererRecommendation.from(imports: ["d3d11.dll"])?.profile == .metal)
        #expect(RendererRecommendation.from(imports: ["d3d9.dll", "d3d11.dll"])?.profile == .combined)
        #expect(RendererRecommendation.from(imports: ["d3d12.dll"])?.profile == nil)
        #expect(RendererRecommendation.from(imports: ["d3d12.dll"])?.title == "DirectX 12 unavailable")
        #expect(RendererRecommendation.from(imports: ["d3d11.dll", "d3d12.dll"])?.detail.contains("DirectX 11 mode") == true)
        #expect(RendererRecommendation.from(imports: ["dxgi.dll"]) == nil)
    }

    @Test func recipeIDsDoNotLeakAcrossStoresAndNewGamesReceiveAStartingPoint() async throws {
        let recipes = try ResourceCatalog.recipes()
        var game = GameInstallation(appID: "730", environmentID: UUID(), name: "Game", directory: "/does-not-exist", sizeBytes: 0)
        #expect(RendererRecommendation.startingPoint(for: game, recipes: recipes).profile == .metal)
        game.source = .epic
        let values = await RendererRecommendations().recommendations(for: [game], recipes: recipes)
        #expect(values[game.id]?.profile == .combined)
        #expect(values[game.id]?.basis == "Starting point")
        game.epicPartnerGameID = "known-partner"; game.launchExecutable = "Brawlhalla.exe"
        #expect(RendererRecommendation.startingPoint(for: game, recipes: recipes).profile == .performance)
    }

    @Test func declaredExecutableWinsOverOtherToolsAndManualRefreshInvalidatesCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exe = root.appendingPathComponent("game.exe")
        try image(name: "d3d9.dll", wide: false).write(to: exe)
        try image(name: "d3d12.dll").write(to: root.appendingPathComponent("tool.exe"))
        var game = GameInstallation(appID: "example", environmentID: UUID(), name: "Game", directory: root.path, sizeBytes: 0)
        game.source = .epic; game.launchExecutable = "game.exe"
        let service = RendererRecommendations()
        let first = await service.recommendations(for: [game], recipes: [])
        #expect(first[game.id]?.profile == .performance)
        try image().write(to: exe)
        let cached = await service.recommendations(for: [game], recipes: [])
        #expect(cached == first)
        let updated = await service.recommendations(for: [game], recipes: [], refresh: true)
        #expect(updated[game.id]?.profile == .metal)
        game.launchExecutable = "../outside.exe"
        let escaped = await service.recommendations(for: [game], recipes: [], refresh: true)
        // Invalid manifest paths must never broaden into a directory scan.
        #expect(escaped[game.id]?.basis == "Starting point")
    }
}

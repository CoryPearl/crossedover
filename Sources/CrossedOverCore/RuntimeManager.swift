import CArchive
import Foundation

public struct RuntimeDownload: Codable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var url: URL
    public var sha256: String
    public var archiveRoot: String
    public var wineRelativePath: String
    public var wineserverRelativePath: String
    public var sourceURL: String
    public var warning: String
}

public enum ArchiveExtractor {
    public static func extract(_ archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        guard (try FileManager.default.contentsOfDirectory(atPath: destination.path)).isEmpty else {
            throw CrossedOverError.message("Archive extraction requires an empty staging directory.")
        }
        var error = [CChar](repeating: 0, count: 2048)
        let status = crossedover_extract(archive.resolvingSymlinksInPath().path, destination.resolvingSymlinksInPath().path, &error, error.count)
        guard status == 0 else { throw CrossedOverError.message(String(decoding: error.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)) }
    }
}

public actor RuntimeManager {
    public let paths: AppPaths
    public init(paths: AppPaths) { self.paths = paths }
    public static func catalog() throws -> [RuntimeDownload] {
        try JSONDecoder().decode([RuntimeDownload].self, from: Data(contentsOf: ResourceCatalog.bundle.url(forResource: "runtimes", withExtension: "json")!))
    }
    public func installed() throws -> [InstalledRuntime] {
        try FileManager.default.contentsOfDirectory(at: paths.runtimes, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }.compactMap { root in
                guard let data = try? Data(contentsOf: root.appendingPathComponent("runtime.json")) else { return nil }
                let manifest = try JSONDecoder().decode(RuntimeManifest.self, from: data)
                try Self.validate(manifest, root: root, verifyHashes: false)
                return InstalledRuntime(manifest: manifest, root: root)
            }
    }
    public func resolve(_ id: String) throws -> InstalledRuntime {
        guard let runtime = try installed().first(where: { $0.id == id }) else { throw CrossedOverError.message("Install the selected runtime first.") }
        return runtime
    }
    public func install(_ item: RuntimeDownload, archive localArchive: URL? = nil) async throws -> InstalledRuntime {
        guard !item.id.contains("/"), !item.id.hasPrefix("."), !item.id.isEmpty else { throw CrossedOverError.message("Invalid runtime identifier.") }
        let destination = try FileSafety.containedURL(item.id, in: paths.runtimes)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return try resolve(item.id) }
        let archive = localArchive ?? paths.downloads.appendingPathComponent(item.id + ".tar.xz")
        if localArchive == nil, !FileManager.default.fileExists(atPath: archive.path) {
            guard item.url.scheme == "https" else { throw CrossedOverError.message("Runtime downloads must use HTTPS.") }
            let (temporary, response) = try await URLSession.shared.download(from: item.url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https" else { throw CrossedOverError.message("The runtime download failed.") }
            try FileManager.default.moveItem(at: temporary, to: archive)
        }
        do { try FileSafety.verify(archive, sha256: item.sha256) }
        catch { if localArchive == nil { try? FileManager.default.removeItem(at: archive) }; throw error }
        try Task.checkCancellation()
        let stage = paths.runtimes.appendingPathComponent(".staging-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        try await Task.detached { try ArchiveExtractor.extract(archive, to: stage) }.value
        try Task.checkCancellation()
        let root = item.archiveRoot == "." ? stage : try FileSafety.containedURL(item.archiveRoot, in: stage)
        let wine = try FileSafety.containedURL(item.wineRelativePath, in: root)
        let server = try FileSafety.containedURL(item.wineserverRelativePath, in: root)
        let manifest = RuntimeManifest(id: item.id, name: item.name, version: item.version,
            wineRelativePath: item.wineRelativePath, wineserverRelativePath: item.wineserverRelativePath,
            sourceURL: item.sourceURL, sourceSHA256: item.sha256,
            fileHashes: [item.wineRelativePath: try FileSafety.sha256(wine), item.wineserverRelativePath: try FileSafety.sha256(server)])
        try Self.validate(manifest, root: root, verifyHashes: true)
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("runtime.json"), options: .atomic)
        try FileManager.default.moveItem(at: root, to: destination)
        return InstalledRuntime(manifest: manifest, root: destination)
    }
    public func importLocal(_ source: URL) throws -> InstalledRuntime {
        let manifest = try JSONDecoder().decode(RuntimeManifest.self, from: Data(contentsOf: source.appendingPathComponent("runtime.json")))
        try Self.validate(manifest, root: source, verifyHashes: true)
        let destination = try FileSafety.containedURL(manifest.id, in: paths.runtimes)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CrossedOverError.message("This runtime is already installed.") }
        let stage = paths.runtimes.appendingPathComponent(".staging-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.copyItem(at: source, to: stage)
        try Self.validate(manifest, root: stage, verifyHashes: true)
        try FileManager.default.moveItem(at: stage, to: destination)
        return InstalledRuntime(manifest: manifest, root: destination)
    }
    public static func validate(_ manifest: RuntimeManifest, root: URL, verifyHashes: Bool) throws {
        guard manifest.schemaVersion == 1, manifest.architecture == "x86_64", !manifest.profiles.isEmpty,
              manifest.minimumMacOS <= ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
              !manifest.id.isEmpty, manifest.id != ".", !manifest.id.hasPrefix("."), !manifest.id.contains("/"), !manifest.id.contains("\\") else {
            throw CrossedOverError.message("This runtime manifest is unsupported.")
        }
        for path in [manifest.wineRelativePath, manifest.wineserverRelativePath] + [manifest.x87RelativePath, manifest.steamLoaderRelativePath].compactMap({ $0 }) {
            let executable = try FileSafety.containedURL(path, in: root)
            guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw CrossedOverError.message("Runtime executable missing: \(path)") }
        }
        if manifest.profiles.contains(.combined), !manifest.supports(.combined) {
            throw CrossedOverError.message("Combined graphics requires both DirectX 9 and DirectX 10–11 components.")
        }
        if let observer = manifest.observerRelativePath { _ = try FileSafety.containedURL(observer, in: root) }
        if manifest.profiles.contains(.metal) {
            for path in ["dxmt/x86_64-windows/d3d11.dll", "dxmt/x86_64-windows/dxgi.dll", "dxmt/x86_64-windows/winemetal.dll", "dxmt/i386-windows/winemetal.dll", "lib/wine/x86_64-unix/winemetal.so"] {
                guard FileManager.default.fileExists(atPath: try FileSafety.containedURL(path, in: root).path) else { throw CrossedOverError.message("Metal runtime is missing its DXMT overlay or Unix component.") }
            }
        }
        if manifest.profiles.contains(.performance) {
            for path in ["dxvk/i386-windows/d3d9.dll", "dxvk/x86_64-windows/d3d9.dll", "dxvk/libMoltenVK.dylib", "dxvk/dxvk.conf"] {
                guard FileManager.default.fileExists(atPath: try FileSafety.containedURL(path, in: root).path) else { throw CrossedOverError.message("Performance runtime is missing its Direct3D 9 backend.") }
            }
        }
        if verifyHashes {
            for (path, hash) in manifest.fileHashes { try FileSafety.verify(FileSafety.containedURL(path, in: root), sha256: hash) }
        }
    }
}

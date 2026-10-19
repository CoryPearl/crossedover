import Foundation
import Darwin

public enum LibraryCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case games, apps
    public var id: String { rawValue }
    public var title: String { self == .games ? "Games" : "Apps" }
}

/// A local Windows executable. Paths are relative to the environment, never to a Mac download.
public struct WindowsApp: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var environmentID: UUID
    public var name: String
    public var category: LibraryCategory
    public var executablePath: String
    public var importedDirectory: String?
    public var addedAt: Date
    public init(id: UUID = UUID(), environmentID: UUID, name: String, category: LibraryCategory,
                executablePath: String, importedDirectory: String? = nil) {
        self.id = id; self.environmentID = environmentID; self.name = name; self.category = category
        self.executablePath = executablePath; self.importedDirectory = importedDirectory; addedAt = Date()
    }
}

public struct WindowsAppRun: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var appID: UUID
    public var environmentID: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var state: String
    public var detail: String?
    public var workerPID: Int32?
    public var exitCode: Int32?
    public var isActive: Bool { state == "requested" || state == "running" }
    public init(id: UUID = UUID(), app: WindowsApp) {
        self.id = id; appID = app.id; environmentID = app.environmentID; startedAt = Date(); state = "requested"
    }
    /// A worker outlives the GUI. Recover only when its process has actually gone away.
    public var workerIsMissing: Bool {
        if let pid = workerPID { return pid > 0 && kill(pid, 0) != 0 && errno == ESRCH }
        return Date().timeIntervalSince(startedAt) > 90
    }
}

public enum WindowsApps {
    /// Validate the PE image headers, not just its filename or DOS signature.
    /// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
    public static func validateExecutable(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "exe",
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CrossedOverError.message("Choose a Windows .exe file.")
        }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let dos = try handle.read(upToCount: 64) ?? Data()
        func u16(_ data: Data, _ index: Int) -> UInt16 { UInt16(data[index]) | UInt16(data[index + 1]) << 8 }
        func u32(_ data: Data, _ index: Int) -> UInt32 { UInt32(u16(data, index)) | UInt32(u16(data, index + 2)) << 16 }
        guard dos.count == 64, dos[0] == 0x4d, dos[1] == 0x5a else { throw CrossedOverError.message("This file is not a Windows PE executable.") }
        let offset = UInt64(u32(dos, 60))
        guard offset >= 64, offset + 26 <= size else { throw CrossedOverError.message("The executable header is incomplete.") }
        try handle.seek(toOffset: offset)
        let pe = try handle.read(upToCount: 26) ?? Data()
        guard pe.count == 26, pe.prefix(4) == Data([0x50, 0x45, 0, 0]) else { throw CrossedOverError.message("This file has no valid Windows PE signature.") }
        let machine = u16(pe, 4), sections = u16(pe, 6), headerSize = u16(pe, 20), flags = u16(pe, 22), magic = u16(pe, 24)
        guard machine == 0x14c || machine == 0x8664 else { throw CrossedOverError.message("Choose an x86 or x64 Windows app. Windows ARM executables are not supported by this runtime.") }
        guard flags & 0x2000 == 0, flags & 0x0002 != 0,
              sections > 0, sections <= 96,
              (machine == 0x14c && magic == 0x10b && headerSize >= 96) || (machine == 0x8664 && magic == 0x20b && headerSize >= 112),
              offset + 24 + UInt64(headerSize) + UInt64(sections) * 40 <= size else {
            throw CrossedOverError.message("This is a DLL, incomplete image, or unsupported executable.")
        }
    }

    public static func executable(for app: WindowsApp, prefix: URL) throws -> URL {
        guard app.executablePath.hasPrefix("drive_c/") else { throw CrossedOverError.message("The app must be inside its Windows C: drive.") }
        let url = try FileSafety.containedURL(app.executablePath, in: prefix)
        try validateExecutable(url)
        return url
    }

    /// Copy only an explicitly selected payload. Files already in C: are referenced in place.
    public static func add(executable source: URL, name: String, category: LibraryCategory, includeFolder: Bool,
                           environment: ManagedEnvironment, paths: AppPaths, store: Store, replacing: WindowsApp? = nil) throws -> WindowsApp {
        guard environment.state == "ready" else { throw CrossedOverError.message("Repair the Windows environment before adding an app.") }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 120 else { throw CrossedOverError.message("Enter a name of 1–120 characters.") }
        let lock = try EnvironmentLock(prefix: paths.prefix(environment)); defer { withExtendedLifetime(lock) {} }
        guard replacing == nil || replacing?.environmentID == environment.id else { throw CrossedOverError.message("The app belongs to another Windows environment.") }
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        try validateExecutable(source)
        let prefix = paths.prefix(environment).resolvingSymlinksInPath()
        var app = replacing ?? WindowsApp(environmentID: environment.id, name: cleanName, category: category, executablePath: "")
        app.name = cleanName; app.category = category
        let base = try canonicalPath(prefix) + "/"
        let sourcePath = try canonicalPath(source)
        var created: URL?
        do {
            if sourcePath.hasPrefix(base + "drive_c/") {
                app.executablePath = String(sourcePath.dropFirst(base.count))
            } else {
                let directory = "drive_c/crossedover/Apps/" + UUID().uuidString
                let destination = try FileSafety.containedURL(directory, in: prefix)
                let payload = includeFolder ? source.deletingLastPathComponent() : source
                // Never recursively copy the destination into itself.
                guard !base.hasPrefix(try canonicalPath(payload) + "/") else { throw CrossedOverError.message("Choose a folder containing only this Windows app.") }
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                created = destination
                if includeFolder { try copyFolder(payload, to: destination) }
                else { try copyFile(source, to: destination.appendingPathComponent(source.lastPathComponent)) }
                app.executablePath = directory + "/" + source.lastPathComponent
                // Keep prior imported installer files if the card is retargeted; removal is explicit.
                if app.importedDirectory == nil { app.importedDirectory = directory }
            }
            _ = try executable(for: app, prefix: prefix)
            try Task.checkCancellation()
            try store.put(app, kind: "windowsApp", id: app.id.uuidString)
            return app
        } catch {
            if let created { try? FileManager.default.removeItem(at: created) }
            throw error
        }
    }

    private static func canonicalPath(_ url: URL) throws -> String {
        guard let path = realpath(url.path, nil) else { throw CrossedOverError.message("The selected file or folder no longer exists.") }
        defer { free(path) }
        return String(cString: path)
    }
    private static func copyFolder(_ source: URL, to destination: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
        var enumerationError: (any Error)?
        guard let files = FileManager.default.enumerator(at: source, includingPropertiesForKeys: keys, errorHandler: { _, error in enumerationError = error; return false }) else {
            throw CrossedOverError.message("The app folder couldn't be read.")
        }
        let sourcePath = try canonicalPath(source) + "/"
        for case let file as URL in files {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw CrossedOverError.message("The selected folder contains symbolic links. Extract a self-contained Windows app folder first.") }
            let path = try canonicalPath(file)
            guard path.hasPrefix(sourcePath) else { throw CrossedOverError.message("An imported file escaped its selected folder.") }
            let relative = String(path.dropFirst(sourcePath.count))
            let target = try FileSafety.containedURL(relative, in: destination)
            if values.isDirectory == true { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
            else if values.isRegularFile == true { try copyFile(file, to: target) }
            else { throw CrossedOverError.message("The app folder contains a file that can't be imported.") }
        }
        if let enumerationError { throw enumerationError }
    }
    private static func copyFile(_ source: URL, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CrossedOverError.message("Couldn't create the imported file.") }
        let output = try FileHandle(forWritingTo: destination); defer { try? output.close() }
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty { try Task.checkCancellation(); try output.write(contentsOf: data) }
    }
}

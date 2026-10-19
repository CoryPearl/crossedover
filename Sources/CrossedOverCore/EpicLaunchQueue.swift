import Foundation

/// Epic's partner-game restart path reads this public launch-link queue. Wine's
/// shell handoff can start Epic with -forwarduri but lose the queued link.
/// Keep Epic in charge of authentication and its fresh Ubisoft exchange code.
public enum EpicLaunchQueue {
    static let key = #"HKCU\Software\Epic Games\EpicGamesLauncher"#
    static let receiptName = ".crossedover-epic-pending.json"
    struct Receipt: Codable { var payload: String; var generation: String }

    static func payload(uri: String, now: Date = Date()) throws -> String {
        let prefix = "com.epicgames.launcher://apps/", suffix = "?action=launch&silent=false"
        guard uri.hasPrefix(prefix), uri.hasSuffix(suffix), uri.count < 2048 else {
            throw CrossedOverError.message("Invalid Epic game launch link.")
        }
        let path = String(uri.dropFirst(prefix.count).dropLast(suffix.count))
        let ids = path.components(separatedBy: "%3A")
        guard [1, 3].contains(ids.count), ids.allSatisfy(EpicDiscovery.validIdentifier),
              now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 >= 0,
              now.timeIntervalSince1970 < 10_000_000_000 else {
            throw CrossedOverError.message("Invalid Epic game launch link.")
        }
        return "\(Int64(now.timeIntervalSince1970))|\(uri)"
    }

    static func receipt(prefix: URL) throws -> Receipt? {
        let file = try FileSafety.containedURL(receiptName, in: prefix)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8192 else {
            throw CrossedOverError.message("Epic's saved launch request needs attention. It was preserved.")
        }
        let record = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: file))
        let parts = record.payload.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, let seconds = Int64(parts[0]), seconds >= 0,
              try payload(uri: String(parts[1]), now: Date(timeIntervalSince1970: Double(seconds))) == record.payload else {
            throw CrossedOverError.message("Epic's saved launch request is invalid. It was preserved.")
        }
        return record
    }

    static func registryValue(_ output: String) -> String? {
        // Swift treats CRLF as one Character; splitting on "\n" alone misses
        // Wine reg.exe's Windows line endings and can leave a cancelled queue.
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.count == 3, fields[0] == "PendingUri", fields[1] == "REG_SZ" {
                return fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    static func run(_ args: [String], runtime: InstalledRuntime, prefix: URL, profile: GraphicsProfile) async throws -> ProcessResult {
        try await ProcessRunner.run(runtime.wine, arguments: ["reg.exe"] + args,
            workingDirectory: prefix.appendingPathComponent("drive_c"),
            environment: EpicService.environment(runtime: runtime, prefix: prefix, profile: profile), timeout: 15)
    }

    /// Called while holding the same environment lock as launch/Stop. Existing
    /// requests from Epic or another source are preserved, without logging them.
    static func enqueue(uri: String, generation: String, runtime: InstalledRuntime, prefix: URL, profile: GraphicsProfile) async throws {
        let previous = try receipt(prefix: prefix)
        let query = try await run(["query", key, "/v", "PendingUri"], runtime: runtime, prefix: prefix, profile: profile)
        if query.status == 0 {
            guard let previous, registryValue(query.output) == previous.payload else {
                throw CrossedOverError.message("Epic already has a pending launch. Finish it in Epic, then try Play again.")
            }
        }
        let record = Receipt(payload: try payload(uri: uri), generation: generation)
        let file = try FileSafety.containedURL(receiptName, in: prefix)
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let result = try await run(["add", key, "/v", "PendingUri", "/t", "REG_SZ", "/d", record.payload, "/f"],
                                   runtime: runtime, prefix: prefix, profile: profile)
        guard result.status == 0 else { throw CrossedOverError.message("Could not queue the game's launch in Epic. Try Play again.") }
    }

    static func cancelOwned(runtime: InstalledRuntime, prefix: URL, profile: GraphicsProfile) async throws {
        guard let record = try receipt(prefix: prefix) else { return }
        let query = try await run(["query", key, "/v", "PendingUri"], runtime: runtime, prefix: prefix, profile: profile)
        if query.status == 0, registryValue(query.output) == record.payload {
            let deletion = try await run(["delete", key, "/v", "PendingUri", "/f"], runtime: runtime, prefix: prefix, profile: profile)
            guard deletion.status == 0 else { throw CrossedOverError.message("Epic's pending game launch could not be cancelled.") }
        }
        // A newer external value is untouched. A consumed queue needs no delete.
        try FileManager.default.removeItem(at: FileSafety.containedURL(receiptName, in: prefix))
    }
}

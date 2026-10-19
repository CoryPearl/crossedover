import Foundation

/// Fallback for launchers whose install records omit a size. Measurements are
/// file lengths, matching Steam/Epic's installed-size metadata, not APFS allocation.
/// Call from discovery's background task, never while rendering a card.
final class GameInstallationSize: @unchecked Sendable {
    static let shared = GameInstallationSize()
    private struct Entry {
        let bytes: Int64?
        let measuredAt: TimeInterval
        let modifiedAt: Date?
    }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func size(in directory: URL, refresh: Bool = false,
              now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int64? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let values = try? directory.resourceValues(forKeys: keys),
              values.isDirectory == true, values.isSymbolicLink != true else { return nil }
        let key = directory.standardizedFileURL.path
        if !refresh, let cached = lock.withLock({ entries[key] }),
           cached.modifiedAt == values.contentModificationDate,
           now - cached.measuredAt < (cached.bytes == nil ? 30 : 300) {
            return cached.bytes
        }
        let bytes = measure(directory)
        lock.withLock {
            // Bound memory even when a long-lived client sees many uninstalls.
            if entries.count >= 512 { entries.removeAll() }
            entries[key] = Entry(bytes: bytes, measuredAt: now, modifiedAt: values.contentModificationDate)
        }
        return bytes
    }

    private func measure(_ directory: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var failed = false
        guard let files = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, _ in failed = true; return false }) else { return nil }
        var total: Int64 = 0, count = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        for case let file as URL in files {
            count += 1
            // Do not turn an unusually large or changing tree into an unbounded
            // scan, or advertise a partial total as the installed size.
            guard count <= 200_000, ProcessInfo.processInfo.systemUptime < deadline,
                  let values = try? file.resourceValues(forKeys: keys) else { return nil }
            // DirectoryEnumerator does not descend through symbolic links.
            // skipDescendants() on a non-directory can skip the next real folder.
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            guard let length = values.fileSize, length >= 0 else { return nil }
            let result = total.addingReportingOverflow(Int64(length))
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return failed ? nil : total
    }
}

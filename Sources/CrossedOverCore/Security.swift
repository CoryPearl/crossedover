import CryptoKit
import Foundation

public enum FileSafety {
    public static func containedURL(_ relative: String, in root: URL) throws -> URL {
        try resolve(relative, root: root, depth: 0)
    }
    private static func resolve(_ relative: String, root: URL, depth: Int) throws -> URL {
        guard depth < 40 else { throw CrossedOverError.message("Too many symbolic links in a managed path.") }
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\\"), !relative.contains("\0"),
              !relative.split(separator: "/").contains("..") else { throw CrossedOverError.message("Unsafe relative path: \(relative)") }
        let canonical = realpath(root.path, nil)
        let base: URL
        if let canonical { base = URL(fileURLWithPath: String(cString: canonical)); free(canonical) }
        else { base = root.resolvingSymlinksInPath().standardizedFileURL }
        // Resolve every existing ancestor: Foundation does not reliably resolve an
        // intermediate symlink when the final leaf does not exist yet.
        var result = base
        let components = relative.split(separator: "/").filter { $0 != "." }
        for (index, component) in components.enumerated() {
            result.appendPathComponent(String(component))
            if let link = try? FileManager.default.destinationOfSymbolicLink(atPath: result.path) {
                let target = (link.hasPrefix("/") ? URL(fileURLWithPath: link) : result.deletingLastPathComponent().appendingPathComponent(link)).standardizedFileURL
                guard target.path == base.path || target.path.hasPrefix(base.path + "/") else { throw CrossedOverError.message("A symbolic link escapes its managed directory.") }
                let suffix = target.path == base.path ? "." : String(target.path.dropFirst(base.path.count + 1))
                let remainder = components.dropFirst(index + 1).joined(separator: "/")
                return try resolve(suffix + (remainder.isEmpty ? "" : "/" + remainder), root: base, depth: depth + 1)
            }
            guard result.path.hasPrefix(base.path + "/") else { throw CrossedOverError.message("A path escapes its managed directory.") }
        }
        return result.standardizedFileURL
    }
    public static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func verify(_ url: URL, sha256 expected: String) throws {
        guard expected.count == 64, expected.allSatisfy({ $0.isHexDigit }), try sha256(url) == expected.lowercased() else {
            throw CrossedOverError.message("SHA-256 verification failed for \(url.lastPathComponent). The file was not installed.")
        }
    }
}

public enum Redaction {
    public static func apply(_ input: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
        var text = input.replacingOccurrences(of: home, with: "~")
        // Auth-bearing lines are removed in full; do not try to guess token boundaries.
        let pattern = "(?im)^.*(?:password|passwd|authorization|access[_-]?token|refresh[_-]?token|exchange[_-]?code|epicuid|ubi[_-]?ticket|cookie|steamlogin|loginusers|shared_secret|identity_secret|sessionid|accountname|steamid).*$"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[sensitive line removed]")
        }
        return text
    }
}

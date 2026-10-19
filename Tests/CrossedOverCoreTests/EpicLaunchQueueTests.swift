import Foundation
import Testing
@testable import CrossedOverCore

struct EpicLaunchQueueTests {
    let uri = "com.epicgames.launcher://apps/ns%3Aitem%3AExample?action=launch&silent=false"
    @Test func savedLinkUsesEpicTimestampDelimiterAndRejectsOtherActions() throws {
        #expect(try EpicLaunchQueue.payload(uri: uri, now: Date(timeIntervalSince1970: 12345.9)) == "12345|" + uri)
        for bad in ["uplay://launch/1/0", uri + "&token=secret", uri.replacingOccurrences(of: "action=launch", with: "action=uninstall"),
                    uri.replacingOccurrences(of: "Example", with: "bad|name"), uri.replacingOccurrences(of: "ns%3Aitem%3A", with: "ns%3A")] {
            #expect(throws: (any Error).self) { try EpicLaunchQueue.payload(uri: bad) }
        }
        #expect(throws: (any Error).self) { try EpicLaunchQueue.payload(uri: uri, now: Date(timeIntervalSince1970: .nan)) }
        let windows = "\r\nHKEY_CURRENT_USER\\Software\\Epic Games\\EpicGamesLauncher\r\n    PendingUri    REG_SZ    12345|" + uri + "\r\n\r\n"
        #expect(EpicLaunchQueue.registryValue(windows) == "12345|" + uri)
    }

    @Test func ownedQueueCanBeReplacedAndCancelledWithoutTouchingANewerExternalLink() async throws {
        let (paths, _, environment, runtime) = try EpicTests().fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let prefix = paths.prefix(environment), state = prefix.appendingPathComponent("pending-test.txt")
        // Tiny registry stand-in. This checks Core ownership decisions; the real
        // Wine registry/client handoff is covered by epic-integration.py.
        let script = #"""
        #!/bin/sh
        state="$WINEPREFIX/pending-test.txt"
        case "$2" in
          query) test -f "$state" || exit 1; printf '    PendingUri    REG_SZ    '; cat "$state"; printf '\n' ;;
          add) printf '%s' "$9" > "$state" ;;
          delete) rm "$state" ;;
          *) exit 9 ;;
        esac
        """#
        try script.write(to: runtime.wine, atomically: true, encoding: .utf8)
        try await EpicLaunchQueue.enqueue(uri: uri, generation: "one", runtime: runtime, prefix: prefix, profile: .performance)
        let saved = try EpicLaunchQueue.receipt(prefix: prefix)
        let first = try #require(saved)
        #expect(try String(contentsOf: state, encoding: .utf8) == first.payload)
        try await EpicLaunchQueue.enqueue(uri: uri, generation: "two", runtime: runtime, prefix: prefix, profile: .performance)
        #expect(try EpicLaunchQueue.receipt(prefix: prefix)?.generation == "two")
        try await EpicLaunchQueue.cancelOwned(runtime: runtime, prefix: prefix, profile: .performance)
        #expect(!FileManager.default.fileExists(atPath: state.path))
        #expect(try EpicLaunchQueue.receipt(prefix: prefix) == nil)
        try await EpicLaunchQueue.enqueue(uri: uri, generation: "three", runtime: runtime, prefix: prefix, profile: .performance)
        try "external-private-sentinel".write(to: state, atomically: true, encoding: .utf8)
        do {
            try await EpicLaunchQueue.enqueue(uri: uri, generation: "four", runtime: runtime, prefix: prefix, profile: .performance)
            Issue.record("An external queued link must be preserved")
        } catch { #expect(!error.localizedDescription.contains("private-sentinel")) }
        try await EpicLaunchQueue.cancelOwned(runtime: runtime, prefix: prefix, profile: .performance)
        #expect(try String(contentsOf: state, encoding: .utf8) == "external-private-sentinel")
    }
}

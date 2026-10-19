import Foundation

public enum DiagnosticsService {
    public static func preview(paths: AppPaths, store: Store, host: HostReport?) throws -> String {
        var sections = ["crossedover diagnostic report", "Generated: \(ISO8601DateFormatter().string(from: Date()))", "Application: \(AppVersion.current)"]
        if let host { sections += ["macOS: \(host.osVersion)", "GPU: \(host.gpu)", "Memory: \(host.memoryGB) GiB", "Translation available: \(host.translationAvailable)"] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let environments = try store.all(ManagedEnvironment.self, kind: "environment")
        sections += ["Environments", String(decoding: try encoder.encode(environments), as: UTF8.self)]
        let sessions = try store.all(LaunchSession.self, kind: "session").sorted { $0.startedAt > $1.startedAt }.prefix(15)
        sections += ["Recent sessions", String(decoding: try encoder.encode(Array(sessions)), as: UTF8.self)]
        let appRuns = try store.all(WindowsAppRun.self, kind: "windowsRun").sorted { $0.startedAt > $1.startedAt }.prefix(15)
        sections += ["Recent Windows app launches", String(decoding: try encoder.encode(Array(appRuns)), as: UTF8.self)]
        let operations = try store.all(OperationRecord.self, kind: "operation").sorted { $0.updatedAt > $1.updatedAt }.prefix(15)
        sections += ["Recent operations", String(decoding: try encoder.encode(Array(operations)), as: UTF8.self)]
        sections += ["Steam and Epic authentication files, account configuration, cookies, and raw runtime logs are excluded.", "No information is uploaded automatically."]
        return Redaction.apply(sections.joined(separator: "\n\n"))
    }
}

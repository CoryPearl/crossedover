import Foundation
import Metal

public struct HostReport: Codable, Sendable {
    public var osVersion: String
    public var architecture: String
    public var gpu: String
    public var memoryGB: Int
    public var freeGB: Int
    public var translationAvailable: Bool
    public var blockers: [String]
    public var notes: [String]
    public var supported: Bool { blockers.isEmpty }
}

public enum HostInspector {
    public static func inspect(at root: URL) async -> HostReport {
        let info = ProcessInfo.processInfo
        let os = info.operatingSystemVersion
        let architecture = "arm64"
        let translation = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/arch"), arguments: ["-x86_64", "/usr/bin/true"], timeout: 10)
        let device = MTLCreateSystemDefaultDevice()
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = Int((values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_073_741_824)
        var blockers: [String] = []
        var notes: [String] = []
        #if !arch(arm64)
        blockers.append("Version 1 requires an Apple silicon Mac.")
        #endif
        if os.majorVersion < 15 { blockers.append("macOS 15 or later is required.") }
        if device == nil { blockers.append("A Metal graphics device is required.") }
        if translation?.status != 0 { blockers.append("Intel translation is unavailable. Install Rosetta using Apple's system prompt before continuing.") }
        if free < 8 { blockers.append("At least 8 GiB of free storage is required for Windows setup. Apps and games need additional space.") }
        if os.majorVersion >= 28 { blockers.append("This runtime has not been validated for the reduced Rosetta support in macOS 28 or later.") }
        if ![15, 26].contains(os.majorVersion) { notes.append("This macOS version is experimental.") }
        notes.append("Windows app and game compatibility is experimental. Windows programs run with your user permissions.")
        return HostReport(osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", architecture: architecture,
            gpu: device?.name ?? "Unavailable", memoryGB: Int(info.physicalMemory / 1_073_741_824), freeGB: free,
            translationAvailable: translation?.status == 0, blockers: blockers, notes: notes)
    }
}

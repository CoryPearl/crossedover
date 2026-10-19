import Foundation
import Testing
@testable import CrossedOverCore

struct EpicLaunchSupportTests {
    @Test func helperVersionChecksAreScopedAndRejectMalformedOrOldVersions() {
        for version in ["", "-", "5", "5.3", "5.3.0.1", "5.2.99", "Unknown", "5..3", "-5.3.0", "five.3.0"] {
            #expect(!EpicLaunchSupport.supportedVersion(version))
        }
        for version in ["5.3.0", "5.8.1-58751156+++UE5+Release-EOSH-5.5-62c6c8", "6.0.0"] {
            #expect(EpicLaunchSupport.supportedVersion(version))
        }
        let registry = #"""
        [Software\\Unrelated]
        "Version"="99.0.0"
        [Software\\Wow6432Node\\Epic Games\\EOS\\MainService]
        "Version"="5.8.1-58751156+++UE5+Release-EOSH-5.5"
        """#
        #expect(EpicLaunchSupport.registeredVersion(registry) == "5.8.1-58751156+++UE5+Release-EOSH-5.5")
        #expect(EpicLaunchSupport.registeredVersion(registry.replacingOccurrences(of: "MainService", with: "Account")) == nil)
    }
    @Test func missingHelperFailsBeforeAProcessLaunchAndManagedOverridesStayScoped() async throws {
        let (paths, _, environment, runtime) = try EpicTests().fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let prefix = paths.prefix(environment)
        await #expect(throws: (any Error).self) {
            try await EpicLaunchSupport.requireReady(runtime: runtime, prefix: prefix, profile: .performance)
        }
        let installer = EpicLaunchSupport.installerEnvironment(runtime: runtime, prefix: prefix, profile: .performance)
        #expect(installer["WINEDLLOVERRIDES"]?.contains("mscoree=n,b") == true)
        #expect(WineConfiguration.environment(runtime: runtime, prefix: prefix, profile: .performance)["WINEDLLOVERRIDES"]?.contains("mscoree,mshtml=") == true)
        #expect(EpicService.environment(runtime: runtime, prefix: prefix, profile: .performance)["WINEDLLOVERRIDES"]?.contains("mscoree,mshtml=") == true)
    }
    @Test func versionRegistrationAloneDoesNotPretendTheHelperIsInstalled() throws {
        let (paths, _, environment, _) = try EpicTests().fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let prefix = paths.prefix(environment)
        try #"""
        [Software\\Wow6432Node\\Epic Games\\EOS\\MainService]
        "Version"="5.8.1"
        """#.write(to: prefix.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
        #expect(try EpicLaunchSupport.installedVersion(prefix: prefix) == nil)
        let helper = prefix.appendingPathComponent("drive_c/Program Files (x86)/Epic Games/Epic Online Services/service/EpicOnlineServicesHost.exe")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: helper)
        #expect(try EpicLaunchSupport.installedVersion(prefix: prefix) == "5.8.1")
        let native = prefix.appendingPathComponent("drive_c/windows/Microsoft.NET/Framework/v4.0.30319/mscorlib.dll")
        try FileManager.default.createDirectory(at: native.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: native)
        #expect(try EpicLaunchSupport.hasManagedRuntime(prefix: prefix))
    }
    @Test func launchUsesTheLiveHelperVersionRatherThanAStaleHive() async throws {
        let (paths, _, environment, runtime) = try EpicTests().fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let prefix = paths.prefix(environment)
        let helper = prefix.appendingPathComponent("drive_c/Program Files (x86)/Epic Games/Epic Online Services/service/EpicOnlineServicesHost.exe")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: helper)
        for version in ["5.8.1", "5.2.0"] {
            try "#!/bin/sh\necho '    Version    REG_SZ    \(version)'\n".write(to: runtime.wine, atomically: true, encoding: .utf8)
            if version == "5.8.1" {
                try await EpicLaunchSupport.requireReady(runtime: runtime, prefix: prefix, profile: .metal)
            } else {
                await #expect(throws: (any Error).self) {
                    try await EpicLaunchSupport.requireReady(runtime: runtime, prefix: prefix, profile: .metal)
                }
            }
        }
    }
}

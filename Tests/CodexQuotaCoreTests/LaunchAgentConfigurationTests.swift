import Foundation
import Testing
@testable import CodexQuotaCore

struct LaunchAgentConfigurationTests {
    @Test func createsUserLaunchAgentPlist() throws {
        let executable = URL(fileURLWithPath: "/Users/me/Library/Application Support/CodexQuotaMenu/bin/codex-quota-menu")
        let codex = URL(fileURLWithPath: "/Users/me/.nvm/bin/codex")

        let data = try LaunchAgentConfiguration.plistData(executableURL: executable, codexURL: codex)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(plist["Label"] as? String == "com.codex.quota-menu")
        #expect(plist["ProgramArguments"] as? [String] == [executable.path])
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect((plist["EnvironmentVariables"] as? [String: String])?["CODEX_QUOTA_MENU_CODEX_PATH"] == codex.path)
    }
}

import Foundation

public enum LaunchAgentConfiguration {
    public static let label = "com.codex.quota-menu"
    public static let plistName = "com.codex.quota-menu.plist"

    public static func plistData(executableURL: URL, codexURL: URL?) throws -> Data {
        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]
        if let codexURL {
            plist["EnvironmentVariables"] = ["CODEX_QUOTA_MENU_CODEX_PATH": codexURL.path]
        }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}

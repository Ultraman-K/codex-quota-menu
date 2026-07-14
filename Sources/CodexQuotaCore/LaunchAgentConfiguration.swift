import Foundation

public enum LaunchAgentConfiguration {
    public static let label = "com.codex.quota-menu"
    public static let plistName = "com.codex.quota-menu.plist"
    public static let logDirectory = URL(fileURLWithPath: "logs")

    public static func plistData(
        executableURL: URL,
        codexURL: URL?,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> Data {
        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "WorkingDirectory": workingDirectory.path,
            "StandardOutPath": "logs/launchagent.out.log",
            "StandardErrorPath": "logs/launchagent.err.log"
        ]
        var environment = ["CODEX_QUOTA_MENU_LOG_DIR": "logs"]
        if let codexURL {
            environment["CODEX_QUOTA_MENU_CODEX_PATH"] = codexURL.path
        }
        plist["EnvironmentVariables"] = environment
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}

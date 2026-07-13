import Foundation
import CodexQuotaCore

actor LaunchAtLoginManager {
    private let executableURL: URL
    private let codexURL: URL?
    private let plistURL: URL

    init(executableURL: URL, codexURL: URL?, homeURL: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        self.executableURL = executableURL
        self.codexURL = codexURL
        plistURL = homeURL.appending(path: "Library/LaunchAgents/\(LaunchAgentConfiguration.plistName)")
    }

    func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func setEnabled(_ enabled: Bool) throws -> Bool {
        if enabled {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try LaunchAgentConfiguration.plistData(executableURL: executableURL, codexURL: codexURL)
            try data.write(to: plistURL, options: .atomic)
            try runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path], allowAlreadyLoaded: true)
        } else {
            try runLaunchctl(["bootout", "gui/\(getuid())/\(LaunchAgentConfiguration.label)"], allowNotFound: true)
            try? FileManager.default.removeItem(at: plistURL)
        }
        return isEnabled()
    }

    private func runLaunchctl(
        _ arguments: [String],
        allowAlreadyLoaded: Bool = false,
        allowNotFound: Bool = false
    ) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if (allowAlreadyLoaded && error.localizedCaseInsensitiveContains("already")) ||
            (allowNotFound && error.localizedCaseInsensitiveContains("could not find")) {
            return
        }
        throw NSError(domain: "CodexQuotaMenu.LaunchAtLogin", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: error])
    }
}

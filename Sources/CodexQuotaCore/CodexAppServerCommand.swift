import Foundation

struct CodexAppServerCommand {
    let executableURL: URL
    let arguments: [String]

    init(codexURL: URL, fileManager: FileManager = .default) {
        let resolvedCodexURL = codexURL.resolvingSymlinksInPath()
        let nodeURL = codexURL.deletingLastPathComponent().appending(path: "node")
        if resolvedCodexURL.pathExtension == "js", fileManager.isExecutableFile(atPath: nodeURL.path) {
            executableURL = nodeURL
            arguments = [resolvedCodexURL.path, "app-server", "--stdio"]
        } else {
            executableURL = codexURL
            arguments = ["app-server", "--stdio"]
        }
    }
}

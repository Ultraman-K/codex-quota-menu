import Foundation
import Testing
@testable import CodexQuotaCore

struct CodexAppServerCommandTests {
    @Test func runsNvmCodexJavaScriptWithItsSiblingNodeBinary() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bin = root.appending(path: ".nvm/versions/node/v22.22.2/bin")
        let node = bin.appending(path: "node")
        let script = root.appending(path: ".nvm/versions/node/v22.22.2/lib/node_modules/@openai/codex/bin/codex.js")
        let codex = bin.appending(path: "codex")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("node".utf8).write(to: node)
        try Data("script".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        try FileManager.default.createSymbolicLink(atPath: codex.path, withDestinationPath: script.path)

        let command = CodexAppServerCommand(codexURL: codex)

        #expect(command.executableURL == node)
        #expect(command.arguments == [script.path, "app-server", "--stdio"])
    }
}

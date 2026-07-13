import Foundation
import Testing
@testable import CodexQuotaCore

struct CodexExecutableLocatorTests {
    @Test func prioritizesExplicitConfiguredPath() throws {
        let root = try makeTemporaryDirectory()
        let explicit = try makeExecutable(at: root.appending(path: "explicit-codex"))
        _ = try makeExecutable(at: root.appending(path: "path/codex"))

        let result = CodexExecutableLocator(
            environment: [
                "CODEX_QUOTA_MENU_CODEX_PATH": explicit.path,
                "PATH": root.appending(path: "path").path
            ],
            homeURL: root
        ).resolve()

        #expect(result == explicit)
    }

    @Test func usesFirstExecutableInPathOrderAndSkipsNonExecutableFiles() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appending(path: "first")
        let second = root.appending(path: "second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        let expected = try makeExecutable(at: second.appending(path: "codex"))
        try Data("not executable".utf8).write(to: first.appending(path: "codex"))

        let result = CodexExecutableLocator(
            environment: ["PATH": "\(first.path):\(second.path)"],
            homeURL: root
        ).resolve()

        #expect(result?.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath())
    }

    @Test func findsCodexInstalledByNvmWhenLaunchAgentPathDoesNotContainIt() throws {
        let root = try makeTemporaryDirectory()
        let expected = try makeExecutable(at: root.appending(path: ".nvm/versions/node/v22.22.2/bin/codex"))

        let result = CodexExecutableLocator(
            environment: ["PATH": "/usr/bin:/bin"],
            homeURL: root
        ).resolve()

        #expect(result?.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath())
    }

    @Test func findsSymlinkedCodexInstalledByNvm() throws {
        let root = try makeTemporaryDirectory()
        let target = try makeExecutable(at: root.appending(path: "packages/codex"))
        let expected = root.appending(path: ".nvm/versions/node/v22.22.2/bin/codex")
        try FileManager.default.createDirectory(at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: expected.path, withDestinationPath: target.path)

        let result = CodexExecutableLocator(
            environment: ["PATH": "/usr/bin:/bin"],
            homeURL: root
        ).resolve()

        #expect(result?.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeExecutable(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}

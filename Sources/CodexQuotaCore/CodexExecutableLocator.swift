import Foundation

public struct CodexExecutableLocator {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeURL: URL

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeURL = homeURL
    }

    public func resolve() -> URL? {
        var candidates: [URL] = []

        if let configuredPath = environment["CODEX_QUOTA_MENU_CODEX_PATH"] {
            candidates.append(URL(fileURLWithPath: configuredPath))
        }
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true).appending(path: "codex")
            }
        }
        candidates += [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            homeURL.appending(path: ".local/bin/codex")
        ]
        candidates += nvmCodexCandidates()

        return candidates.first(where: isExecutableRegularFile)
    }

    private func nvmCodexCandidates() -> [URL] {
        let nodeVersionsURL = homeURL.appending(path: ".nvm/versions/node")
        guard let versions = try? fileManager.contentsOfDirectory(
            at: nodeVersionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return versions
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted(by: isNewerNvmVersion)
            .map { $0.appending(path: "bin/codex") }
    }

    private func isNewerNvmVersion(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = versionComponents(for: lhs)
        let right = versionComponents(for: rhs)
        for index in 0..<max(left.count, right.count) {
            let leftComponent = index < left.count ? left[index] : 0
            let rightComponent = index < right.count ? right[index] : 0
            if leftComponent != rightComponent { return leftComponent > rightComponent }
        }
        return lhs.lastPathComponent > rhs.lastPathComponent
    }

    private func versionComponents(for url: URL) -> [Int] {
        url.lastPathComponent
            .drop(while: { $0 == "v" })
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    private func isExecutableRegularFile(_ url: URL) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath()
        guard fileManager.isExecutableFile(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: resolvedURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            return false
        }
        return true
    }
}

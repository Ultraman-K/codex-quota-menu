import Foundation

public protocol QuotaCache: Sendable {
    func load() throws -> QuotaSnapshot?
    func save(_ snapshot: QuotaSnapshot) throws
}

public struct FileQuotaCache: QuotaCache, Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> QuotaSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(QuotaSnapshot.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ snapshot: QuotaSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}

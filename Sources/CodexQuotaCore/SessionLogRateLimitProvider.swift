import Foundation

public actor SessionLogRateLimitProvider: RateLimitProvider {
    public nonisolated let source: QuotaSource = .sessionLog

    private let roots: [URL]
    private let pollInterval: Duration
    private let rescanInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var pollTask: Task<Void, Never>?
    private var updateContinuation: AsyncThrowingStream<RawQuotaSnapshot, Error>.Continuation?
    private var lastYielded: RawQuotaSnapshot?
    private var cachedFile: (url: URL, modifiedAt: Date?)?
    private var lastRescanAt: Date?

    public init(
        roots: [URL] = [
            URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/sessions"),
            URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/archived_sessions")
        ],
        pollInterval: Duration = .seconds(2),
        rescanInterval: TimeInterval = 30,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.roots = roots
        self.pollInterval = pollInterval
        self.rescanInterval = rescanInterval
        self.now = now
    }

    public func fetch() async throws -> RawQuotaSnapshot {
        guard let snapshot = readLatestSnapshot() else {
            throw RateLimitProviderError.noQuotaData
        }
        return snapshot
    }

    public func updates() async -> AsyncThrowingStream<RawQuotaSnapshot, Error> {
        let pair = AsyncThrowingStream<RawQuotaSnapshot, Error>.makeStream()
        updateContinuation = pair.continuation
        if pollTask == nil {
            pollTask = Task { [weak self] in
                await self?.poll()
            }
        }
        return pair.stream
    }

    public func stop() async {
        pollTask?.cancel()
        pollTask = nil
        updateContinuation?.finish()
        updateContinuation = nil
        lastYielded = nil
        cachedFile = nil
        lastRescanAt = nil
    }

    private func poll() async {
        while !Task.isCancelled {
            if let snapshot = try? await fetch(), snapshot != lastYielded {
                lastYielded = snapshot
                updateContinuation?.yield(snapshot)
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func readLatestSnapshot() -> RawQuotaSnapshot? {
        let capturedAt = now()
        guard let file = newestLogFile(at: capturedAt) else { return nil }
        guard let tail = readTail(of: file.url, maximumBytes: 64 * 1024) else { return nil }
        return tail.split(separator: 0x0A, omittingEmptySubsequences: true)
            .reversed()
            .compactMap { SessionLogParser.parse(line: Data($0), capturedAt: file.modifiedAt ?? capturedAt) }
            .first
    }

    private func newestLogFile(at date: Date) -> (url: URL, modifiedAt: Date?)? {
        if let cachedFile,
           let lastRescanAt,
           date.timeIntervalSince(lastRescanAt) < rescanInterval,
           FileManager.default.fileExists(atPath: cachedFile.url.path) {
            return cachedFile
        }

        let fileManager = FileManager.default
        var newest: (url: URL, modifiedAt: Date)?

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                let modifiedAt = values.contentModificationDate ?? .distantPast
                if newest == nil || modifiedAt > newest!.modifiedAt {
                    newest = (url, modifiedAt)
                }
            }
        }
        cachedFile = newest
        lastRescanAt = date
        return newest
    }

    private func readTail(of url: URL, maximumBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(maximumBytes) ? size - UInt64(maximumBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
        return handle.readDataToEndOfFile()
    }
}

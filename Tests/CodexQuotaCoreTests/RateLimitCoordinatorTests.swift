import Foundation
import Testing
@testable import CodexQuotaCore

struct RateLimitCoordinatorTests {
    @Test func usesSessionLogWhenPrimaryFails() async throws {
        let primary = StubProvider(source: .appServer, result: .failure(.processExited(1)))
        let fallback = StubProvider(source: .sessionLog, result: .success(rawSnapshot(used: 20, capturedAt: 40)))
        let cache = MemoryQuotaCache(initial: normalizedSnapshot(resetsAt: 100, freshness: .fresh))
        let coordinator = RateLimitCoordinator(primary: primary, fallback: fallback, cache: cache)

        let snapshot = try await coordinator.refresh()

        #expect(snapshot.source == .sessionLog)
        #expect(snapshot.fiveHour?.remainingPercent == 80)
    }

    @Test func retainsLastPrimaryQuotaWhenLaterPrimaryRefreshFails() async throws {
        let primary = SequencedProvider(
            source: .appServer,
            results: [
                .success(rawSnapshot(used: 40, capturedAt: 10)),
                .failure(.processExited(1))
            ]
        )
        let coordinator = RateLimitCoordinator(primary: primary, cache: MemoryQuotaCache())

        _ = try await coordinator.refresh()
        let snapshot = try await coordinator.refresh()

        #expect(snapshot.source == .appServer)
        #expect(snapshot.fiveHour?.remainingPercent == 60)
    }

    @Test func normalizesPrimaryUpdatesAndPersistsThem() async throws {
        let update = rawSnapshot(used: 25, capturedAt: 40)
        let primary = UpdatingProvider(source: .appServer, update: update)
        let coordinator = RateLimitCoordinator(primary: primary, cache: MemoryQuotaCache())

        let updates = await coordinator.updates()
        var iterator = updates.makeAsyncIterator()
        let snapshot = try #require(await iterator.next())

        #expect(snapshot.source == .appServer)
        #expect(snapshot.fiveHour?.remainingPercent == 75)
    }

    private func rawSnapshot(used: Int, capturedAt: TimeInterval) -> RawQuotaSnapshot {
        .init(
            windows: [.init(windowMinutes: 300, usedPercent: used, resetsAt: nil)],
            capturedAt: .init(timeIntervalSince1970: capturedAt)
        )
    }

    private func normalizedSnapshot(resetsAt: TimeInterval, freshness: QuotaFreshness) -> QuotaSnapshot {
        .init(
            fiveHour: .init(
                kind: .fiveHour,
                windowMinutes: 300,
                usedPercent: 37,
                remainingPercent: 63,
                resetsAt: .init(timeIntervalSince1970: resetsAt),
                alert: .normal
            ),
            weekly: nil,
            source: .cache,
            freshness: freshness,
            updatedAt: .init(timeIntervalSince1970: 5)
        )
    }
}

private actor UpdatingProvider: RateLimitProvider {
    nonisolated let source: QuotaSource
    private let update: RawQuotaSnapshot

    init(source: QuotaSource, update: RawQuotaSnapshot) {
        self.source = source
        self.update = update
    }

    func fetch() async throws -> RawQuotaSnapshot { update }

    func updates() async -> AsyncThrowingStream<RawQuotaSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(update)
            continuation.finish()
        }
    }

    func stop() async {}
}

private actor StubProvider: RateLimitProvider {
    nonisolated let source: QuotaSource
    private let result: Result<RawQuotaSnapshot, RateLimitProviderError>

    init(source: QuotaSource, result: Result<RawQuotaSnapshot, RateLimitProviderError>) {
        self.source = source
        self.result = result
    }

    func fetch() async throws -> RawQuotaSnapshot { try result.get() }
    func updates() async -> AsyncThrowingStream<RawQuotaSnapshot, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }
    func stop() async {}
}

private actor SequencedProvider: RateLimitProvider {
    nonisolated let source: QuotaSource
    private var results: [Result<RawQuotaSnapshot, RateLimitProviderError>]

    init(source: QuotaSource, results: [Result<RawQuotaSnapshot, RateLimitProviderError>]) {
        self.source = source
        self.results = results
    }

    func fetch() async throws -> RawQuotaSnapshot {
        try results.removeFirst().get()
    }

    func updates() async -> AsyncThrowingStream<RawQuotaSnapshot, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }

    func stop() async {}
}

private final class MemoryQuotaCache: QuotaCache, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: QuotaSnapshot?

    init(initial: QuotaSnapshot? = nil) {
        snapshot = initial
    }

    func load() throws -> QuotaSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func save(_ snapshot: QuotaSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        self.snapshot = snapshot
    }
}

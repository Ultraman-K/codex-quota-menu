import Foundation

public actor RateLimitCoordinator {
    private let primary: any RateLimitProvider
    private let cache: any QuotaCache
    private let now: @Sendable () -> Date
    private var latest: QuotaSnapshot?

    public init(
        primary: any RateLimitProvider,
        fallback: (any RateLimitProvider)? = nil,
        cache: any QuotaCache,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.primary = primary
        self.cache = cache
        self.now = now
    }

    public func refresh() async -> QuotaRefreshResult {
        if let snapshot = try? await normalizedSnapshot(from: primary) {
            return .init(snapshot: snapshot, state: .live)
        }
        if let latest {
            return .init(snapshot: latest, state: isPastReset(latest) ? .expired : .lastKnown, failureReason: .unknown)
        }
        if let cached = try? cache.load() {
            let result = copy(
                cached,
                source: .cache,
                freshness: .stale
            )
            latest = result
            return .init(snapshot: result, state: .expired, failureReason: .unknown)
        }
        return .init(snapshot: nil, state: .unavailable, failureReason: .unknown)
    }

    public func current() -> QuotaRefreshResult {
        guard let latest else { return .init(snapshot: nil, state: .unavailable) }
        return .init(snapshot: latest, state: isPastReset(latest) ? .expired : .lastKnown)
    }

    public func updates() async -> AsyncThrowingStream<QuotaSnapshot, Error> {
        let rawUpdates = await primary.updates()
        let source = primary.source
        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                do {
                    for try await raw in rawUpdates {
                        guard let self else { break }
                        let snapshot = await self.normalizedUpdate(raw, source: source)
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stop() async {
        await primary.stop()
    }

    private func normalizedSnapshot(from provider: any RateLimitProvider) async throws -> QuotaSnapshot {
        let raw = try await provider.fetch()
        return normalizedUpdate(raw, source: provider.source)
    }

    private func normalizedUpdate(_ raw: RawQuotaSnapshot, source: QuotaSource) -> QuotaSnapshot {
        let snapshot = QuotaNormalizer.normalize(raw, source: source)
        try? cache.save(snapshot)
        latest = snapshot
        return snapshot
    }

    private func copy(
        _ snapshot: QuotaSnapshot,
        source: QuotaSource,
        freshness: QuotaFreshness
    ) -> QuotaSnapshot {
        .init(
            fiveHour: snapshot.fiveHour,
            weekly: snapshot.weekly,
            source: source,
            freshness: freshness,
            updatedAt: snapshot.updatedAt
        )
    }

    private func isPastReset(_ snapshot: QuotaSnapshot) -> Bool {
        [snapshot.fiveHour?.resetsAt, snapshot.weekly?.resetsAt]
            .compactMap { $0 }
            .contains(where: { $0 <= now() })
    }

}

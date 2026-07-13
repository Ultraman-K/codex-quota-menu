import Foundation
import Testing
@testable import CodexQuotaCore

struct AppServerRateLimitProviderTests {
    @Test func fetchPerformsHandshakeThenReadsQuota() async throws {
        let transport = FakeLineTransport(lines: [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":37,"windowDurationMins":300,"resetsAt":1783665800},"secondary":{"usedPercent":62,"windowDurationMins":10080,"resetsAt":1784252600}}}}"#.utf8)
        ])
        let provider = AppServerRateLimitProvider(transport: transport, now: { Date(timeIntervalSince1970: 10) })

        let snapshot = try await provider.fetch()

        #expect(snapshot.windows.first(where: { $0.windowMinutes == 300 })?.usedPercent == 37)
        #expect(snapshot.windows.first(where: { $0.windowMinutes == 10_080 })?.usedPercent == 62)
        #expect(try await transport.sentMethods() == ["initialize", "initialized", "account/rateLimits/read"])
        await provider.stop()
    }

    @Test func mapsAuthenticationError() async throws {
        let transport = FakeLineTransport(lines: [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"error":{"message":"authentication required"}}"#.utf8)
        ])
        let provider = AppServerRateLimitProvider(transport: transport, now: Date.init)

        await #expect(throws: RateLimitProviderError.self) {
            try await provider.fetch()
        }
        await provider.stop()
    }

    @Test func restartsAfterTheAppServerStreamEnds() async throws {
        let transport = RestartableLineTransport(lines: [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":300}}}}"#.utf8)
        ])
        let provider = AppServerRateLimitProvider(transport: transport, now: Date.init)

        _ = try await provider.fetch()
        try await Task.sleep(for: .milliseconds(20))
        let secondFetch = Task { try? await provider.fetch() }
        try await Task.sleep(for: .milliseconds(20))

        #expect(await transport.startCount() == 2)
        await provider.stop()
        _ = await secondFetch.result
    }
}

private actor FakeLineTransport: LineTransport {
    private var sent: [Data] = []
    private let stream: AsyncThrowingStream<Data, Error>

    init(lines: [Data]) {
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        stream = pair.stream
        for line in lines {
            pair.continuation.yield(line)
        }
        pair.continuation.finish()
    }

    func start() async throws {}

    func send(_ line: Data) async throws {
        sent.append(line)
    }

    func lines() async -> AsyncThrowingStream<Data, Error> {
        stream
    }

    func stop() async {}

    func sentMethods() throws -> [String] {
        try sent.map { data in
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return object?["method"] as? String ?? ""
        }
    }
}

private actor RestartableLineTransport: LineTransport {
    private let linesToYield: [Data]
    private var stream = AsyncThrowingStream<Data, Error> { continuation in continuation.finish() }
    private var starts = 0

    init(lines: [Data]) {
        linesToYield = lines
    }

    func start() async throws {
        starts += 1
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        stream = pair.stream
        for line in linesToYield { pair.continuation.yield(line) }
        pair.continuation.finish()
    }

    func send(_ line: Data) async throws {}

    func lines() async -> AsyncThrowingStream<Data, Error> { stream }

    func stop() async {}

    func startCount() -> Int { starts }
}

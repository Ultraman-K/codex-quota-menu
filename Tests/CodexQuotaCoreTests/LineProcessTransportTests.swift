import Foundation
import Testing
@testable import CodexQuotaCore

struct LineProcessTransportTests {
    @Test func yieldsTrailingPartialLineThenFinishesNormallyForSuccessfulChild() async throws {
        let transport = LineProcessTransport(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf partial"]
        )

        try await transport.start()
        let stream = await transport.lines()
        var iterator = stream.makeAsyncIterator()

        let first = try await iterator.next()
        let end = try await iterator.next()

        #expect(first == Data("partial".utf8))
        #expect(end == nil)
        await transport.stop()
    }
}

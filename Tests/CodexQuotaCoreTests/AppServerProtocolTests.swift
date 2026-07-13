import Foundation
import Testing
@testable import CodexQuotaCore

struct AppServerProtocolTests {
    @Test func decodesRateLimitReadResult() throws {
        let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":37,"windowDurationMins":300,"resetsAt":1783665800},"secondary":{"usedPercent":62,"windowDurationMins":10080,"resetsAt":1784252600}}}}"#

        let message = try AppServerMessageDecoder.decode(Data(json.utf8))
        let raw = try #require(message.snapshot?.toRaw(capturedAt: .init(timeIntervalSince1970: 10)))

        #expect(message.id == 2)
        #expect(message.method == nil)
        #expect(raw.windows.map(\.windowMinutes).sorted() == [300, 10_080])
        #expect(raw.windows.first(where: { $0.windowMinutes == 300 })?.usedPercent == 37)
    }

    @Test func decodesRateLimitUpdateNotification() throws {
        let json = #"{"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":{"usedPercent":84,"windowDurationMins":300,"resetsAt":1783665800}}}}"#

        let message = try AppServerMessageDecoder.decode(Data(json.utf8))

        #expect(message.method == "account/rateLimits/updated")
        #expect(message.snapshot?.primary?.usedPercent == 84)
        #expect(message.snapshot?.secondary == nil)
    }

    @Test func sparseUpdatePreservesAbsentWindow() {
        let base = AppServerWireSnapshot(
            primary: .init(usedPercent: 37, windowDurationMins: 300, resetsAt: 100),
            secondary: .init(usedPercent: 62, windowDurationMins: 10_080, resetsAt: 200)
        )
        let update = AppServerWireSnapshot(
            primary: .init(usedPercent: 40, windowDurationMins: 300, resetsAt: 100),
            secondary: nil
        )

        let merged = base.mergingSparse(update)

        #expect(merged.primary?.usedPercent == 40)
        #expect(merged.secondary?.usedPercent == 62)
    }

    @Test func omitsWindowsWithoutDurationDuringRawConversion() {
        let snapshot = AppServerWireSnapshot(
            primary: .init(usedPercent: 37, windowDurationMins: nil, resetsAt: 100),
            secondary: .init(usedPercent: 62, windowDurationMins: 10_080, resetsAt: 200)
        )

        let raw = snapshot.toRaw(capturedAt: .init(timeIntervalSince1970: 10))

        #expect(raw.windows.count == 1)
        #expect(raw.windows.first?.windowMinutes == 10_080)
    }

    @Test func rejectsMalformedRateLimits() {
        let json = #"{"id":2,"result":{"rateLimits":"invalid"}}"#

        #expect(throws: RateLimitProviderError.self) {
            try AppServerMessageDecoder.decode(Data(json.utf8))
        }
    }
}

import Foundation
import Testing
@testable import CodexQuotaCore

struct QuotaNormalizerTests {
    @Test func mapsWindowsByDurationAndComputesRemaining() {
        let reset = Date(timeIntervalSince1970: 1_783_665_800)
        let raw = RawQuotaSnapshot(windows: [
            .init(windowMinutes: 10_080, usedPercent: 62, resetsAt: reset),
            .init(windowMinutes: 300, usedPercent: 37, resetsAt: reset)
        ], capturedAt: reset)

        let result = QuotaNormalizer.normalize(raw, source: .appServer)

        #expect(result.fiveHour?.remainingPercent == 63)
        #expect(result.weekly?.remainingPercent == 38)
        #expect(result.fiveHour?.kind == .fiveHour)
        #expect(result.weekly?.kind == .weekly)
    }

    @Test func clampsAndClassifiesRemaining() {
        #expect(QuotaNormalizer.remaining(fromUsed: -5) == 100)
        #expect(QuotaNormalizer.remaining(fromUsed: 120) == 0)
        #expect(QuotaNormalizer.remaining(fromUsed: Int.min) == 100)
        #expect(QuotaNormalizer.remaining(fromUsed: Int.max) == 0)
        #expect(QuotaNormalizer.alert(forRemaining: 51) == .normal)
        #expect(QuotaNormalizer.alert(forRemaining: 50) == .warning)
        #expect(QuotaNormalizer.alert(forRemaining: 20) == .warning)
        #expect(QuotaNormalizer.alert(forRemaining: 19) == .danger)
        #expect(QuotaNormalizer.alert(forRemaining: 0) == .danger)
    }
}

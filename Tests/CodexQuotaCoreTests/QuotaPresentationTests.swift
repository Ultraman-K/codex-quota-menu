import Foundation
import Testing
@testable import CodexQuotaCore

struct QuotaPresentationTests {
    @Test func rendersRemainingValuesAndWarningMarker() {
        let snapshot = QuotaSnapshot(
            fiveHour: .init(kind: .fiveHour, windowMinutes: 300, usedPercent: 37, remainingPercent: 63, resetsAt: .init(timeIntervalSince1970: 3_600), alert: .normal),
            weekly: .init(kind: .weekly, windowMinutes: 10_080, usedPercent: 88, remainingPercent: 12, resetsAt: .init(timeIntervalSince1970: 7_200), alert: .warning),
            source: .appServer,
            freshness: .fresh,
            updatedAt: .init(timeIntervalSince1970: 10)
        )

        let display = QuotaPresentation.make(snapshot: snapshot, now: .init(timeIntervalSince1970: 0), timeZone: .gmt)

        #expect(display.menuText == "5h 63% | 7d 12% !")
        #expect(display.tooltip.contains("5 小时：剩余 63%"))
        #expect(display.sourceText == "Codex 实时额度")
        #expect(display.tooltip.contains("一周：剩余 12%"))
        #expect(display.cards.map(\.title) == ["5 小时使用限制", "每周使用限额"])
        #expect(display.cards.map(\.remainingPercent) == [63, 12])
        #expect(display.cards[1].alert == .warning)
    }

    @Test func rendersUnknownWithoutPretendingQuotaIsFull() {
        let display = QuotaPresentation.make(snapshot: nil, now: .init(timeIntervalSince1970: 0), timeZone: .gmt)

        #expect(display.menuText == "5h -- | 7d --")
        #expect(display.tooltip == "Codex 额度数据不可用")
        #expect(display.cards.isEmpty)
    }
}

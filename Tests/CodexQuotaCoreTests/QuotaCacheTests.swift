import Foundation
import Testing
@testable import CodexQuotaCore

struct QuotaCacheTests {
    @Test func roundTripsSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let cache = FileQuotaCache(fileURL: directory.appending(path: "quota-cache.json"))
        let snapshot = makeSnapshot()

        try cache.save(snapshot)

        #expect(try cache.load() == snapshot)
    }

    @Test func missingCacheReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "quota-cache.json")

        #expect(try FileQuotaCache(fileURL: url).load() == nil)
    }

    private func makeSnapshot() -> QuotaSnapshot {
        .init(
            fiveHour: .init(
                kind: .fiveHour,
                windowMinutes: 300,
                usedPercent: 37,
                remainingPercent: 63,
                resetsAt: .init(timeIntervalSince1970: 100),
                alert: .normal
            ),
            weekly: nil,
            source: .appServer,
            freshness: .fresh,
            updatedAt: .init(timeIntervalSince1970: 10)
        )
    }
}

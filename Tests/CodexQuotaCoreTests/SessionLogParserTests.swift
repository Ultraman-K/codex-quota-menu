import Foundation
import Testing
@testable import CodexQuotaCore

struct SessionLogParserTests {
    @Test func parsesTokenCountRateLimits() throws {
        let line = #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":37,"window_minutes":300,"resets_at":1783665800},"secondary":{"used_percent":62,"window_minutes":10080,"resets_at":1784252600}}}}"#

        let snapshot = try #require(SessionLogParser.parse(line: Data(line.utf8), capturedAt: .init(timeIntervalSince1970: 5)))

        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows.first(where: { $0.windowMinutes == 300 })?.usedPercent == 37)
        #expect(snapshot.windows.first(where: { $0.windowMinutes == 10_080 })?.usedPercent == 62)
    }

    @Test func ignoresUnrelatedAndTruncatedLines() {
        let unrelated = Data(#"{"type":"event_msg","payload":{"type":"user_message"}}"#.utf8)
        let truncated = Data(#"{"type":"event_msg""#.utf8)

        #expect(SessionLogParser.parse(line: unrelated, capturedAt: .now) == nil)
        #expect(SessionLogParser.parse(line: truncated, capturedAt: .now) == nil)
    }

    @Test func providerReadsNewestSessionFile() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let sessions = root.appending(path: "sessions/2026/07/10")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let older = sessions.appending(path: "older.jsonl")
        let newest = sessions.appending(path: "newest.jsonl")
        try Data(validLine(used: 10).utf8).write(to: older)
        try Data(validLine(used: 40).utf8).write(to: newest)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 20)], ofItemAtPath: newest.path)

        let provider = SessionLogRateLimitProvider(
            roots: [root.appending(path: "sessions")],
            pollInterval: .seconds(1),
            now: { Date(timeIntervalSince1970: 30) }
        )

        let snapshot = try await provider.fetch()

        #expect(snapshot.windows.first?.usedPercent == 40)
        await provider.stop()
    }

    @Test func reusesNewestCandidateBeforeTheRescanInterval() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let current = root.appending(path: "current.jsonl")
        try Data(validLine(used: 10).utf8).write(to: current)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: current.path)

        let provider = SessionLogRateLimitProvider(
            roots: [root],
            pollInterval: .seconds(1),
            rescanInterval: 60
        )
        let first = try await provider.fetch()

        let newer = root.appending(path: "newer.jsonl")
        try Data(validLine(used: 70).utf8).write(to: newer)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: newer.path)
        let second = try await provider.fetch()

        #expect(first.windows.first?.usedPercent == 10)
        #expect(second.windows.first?.usedPercent == 10)
        await provider.stop()
    }

    private func validLine(used: Int) -> String {
        #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":\#(used),"window_minutes":300,"resets_at":100}}}}"#
    }
}

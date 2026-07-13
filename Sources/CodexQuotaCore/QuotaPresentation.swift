import Foundation

public struct QuotaCardDisplay: Equatable, Sendable {
    public let title: String
    public let resetText: String
    public let remainingPercent: Int
    public let alert: QuotaAlert
}

public struct QuotaDisplay: Equatable, Sendable {
    public let menuText: String
    public let tooltip: String
    public let sourceText: String
    public let isStale: Bool
    public let cards: [QuotaCardDisplay]
}

public enum QuotaPresentation {
    public static func make(
        snapshot: QuotaSnapshot?,
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> QuotaDisplay {
        guard let snapshot else {
            return .init(menuText: "5h -- | 7d --", tooltip: "Codex 额度数据不可用", sourceText: "数据源不可用", isStale: false, cards: [])
        }

        let fiveHour = metric(window: snapshot.fiveHour, label: "5h")
        let weekly = metric(window: snapshot.weekly, label: "7d")
        var lines = [
            tooltipLine(window: snapshot.fiveHour, label: "5 小时", now: now, timeZone: timeZone),
            tooltipLine(window: snapshot.weekly, label: "一周", now: now, timeZone: timeZone)
        ]
        if snapshot.freshness == .stale {
            lines.append("数据可能已过期 · 上次更新 \(format(snapshot.updatedAt, now: now, timeZone: timeZone))")
        }
        let cards = [
            card(window: snapshot.fiveHour, title: "5 小时使用限制", now: now, timeZone: timeZone),
            card(window: snapshot.weekly, title: "每周使用限额", now: now, timeZone: timeZone)
        ].compactMap { $0 }
        return .init(
            menuText: "\(fiveHour) | \(weekly)",
            tooltip: lines.joined(separator: "\n"),
            sourceText: sourceText(snapshot.source),
            isStale: snapshot.freshness == .stale,
            cards: cards
        )
    }

    private static func metric(window: QuotaWindow?, label: String) -> String {
        guard let window else { return "\(label) --" }
        let marker: String
        switch window.alert {
        case .warning: marker = " !"
        case .danger: marker = " ⚠"
        default: marker = ""
        }
        return "\(label) \(window.remainingPercent)%\(marker)"
    }

    private static func tooltipLine(window: QuotaWindow?, label: String, now: Date, timeZone: TimeZone) -> String {
        guard let window else { return "\(label)：剩余 --" }
        let resetText = window.resetsAt.map { "\(format($0, now: now, timeZone: timeZone)) 重置" } ?? "重置时间未知"
        return "\(label)：剩余 \(window.remainingPercent)%，\(resetText)"
    }

    private static func card(window: QuotaWindow?, title: String, now: Date, timeZone: TimeZone) -> QuotaCardDisplay? {
        guard let window else { return nil }
        let resetText = window.resetsAt.map { "\(formatCardReset($0, now: now, timeZone: timeZone)) 重置" } ?? "重置时间未知"
        return .init(title: title, resetText: resetText, remainingPercent: window.remainingPercent, alert: window.alert)
    }

    private static func format(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "'今天' HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private static func formatCardReset(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private static func sourceText(_ source: QuotaSource) -> String {
        switch source {
        case .appServer: "Codex 实时额度"
        case .sessionLog: "Codex 会话日志"
        case .cache: "本地缓存"
        }
    }
}

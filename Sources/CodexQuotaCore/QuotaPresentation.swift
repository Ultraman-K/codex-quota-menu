import Foundation

public enum StatusBarDisplayMode: Equatable, Sendable {
    case full
    case compact
}

public enum StatusBarDisplayModePreference {
    private static let compactModeKey = "CodexQuotaMenu.compactStatusBar"

    public static func load(from defaults: UserDefaults = .standard) -> StatusBarDisplayMode {
        defaults.bool(forKey: compactModeKey) ? .compact : .full
    }

    public static func save(_ mode: StatusBarDisplayMode, to defaults: UserDefaults = .standard) {
        defaults.set(mode == .compact, forKey: compactModeKey)
    }
}

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
    public let state: QuotaDisplayState
    public let detailStatusText: String?
    public let retryText: String?
    public let usesMutedQuotaColors: Bool
}

public enum QuotaPresentation {
    public static func statusText(_ display: QuotaDisplay, mode: StatusBarDisplayMode) -> String {
        guard mode != .compact else { return "5h | 7d" }
        return display.usesMutedQuotaColors ? "◷ \(display.menuText)" : display.menuText
    }

    public static func make(
        snapshot: QuotaSnapshot?,
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> QuotaDisplay {
        make(result: .init(snapshot: snapshot, state: snapshot == nil ? .unavailable : .live), now: now, timeZone: timeZone)
    }

    public static func make(
        result: QuotaRefreshResult,
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> QuotaDisplay {
        let snapshot = result.snapshot
        guard let snapshot else {
            let status = unavailableText(for: result.failureReason)
            return .init(menuText: "5h -- | 7d --", tooltip: status, sourceText: "数据源不可用", isStale: true, cards: [], state: result.state, detailStatusText: status, retryText: retryText(result.nextRetryAt, now: now), usesMutedQuotaColors: true)
        }

        let fiveHour = metric(window: snapshot.fiveHour, label: "5h")
        let weekly = metric(window: snapshot.weekly, label: "7d")
        var lines = [
            tooltipLine(window: snapshot.fiveHour, label: "5 小时", now: now, timeZone: timeZone),
            tooltipLine(window: snapshot.weekly, label: "一周", now: now, timeZone: timeZone)
        ]
        if result.state == .expired || snapshot.freshness == .stale {
            lines.append("数据可能已过期 · 上次更新 \(format(snapshot.updatedAt, now: now, timeZone: timeZone))")
        }
        if let status = detailStatus(result, snapshot: snapshot, now: now, timeZone: timeZone) { lines.append(status) }
        let cards = [
            card(window: snapshot.fiveHour, title: "5 小时使用限制", now: now, timeZone: timeZone),
            card(window: snapshot.weekly, title: "每周使用限额", now: now, timeZone: timeZone)
        ].compactMap { $0 }
        return .init(
            menuText: "\(fiveHour) | \(weekly)",
            tooltip: lines.joined(separator: "\n"),
            sourceText: sourceText(snapshot.source),
            isStale: result.state == .expired || result.state == .lastKnown || snapshot.freshness == .stale,
            cards: cards,
            state: result.state,
            detailStatusText: detailStatus(result, snapshot: snapshot, now: now, timeZone: timeZone),
            retryText: retryText(result.nextRetryAt, now: now),
            usesMutedQuotaColors: result.state == .lastKnown || result.state == .expired || result.state == .unavailable
        )
    }

    private static func detailStatus(_ result: QuotaRefreshResult, snapshot: QuotaSnapshot, now: Date, timeZone: TimeZone) -> String? {
        switch result.state {
        case .live: return snapshot.source == .cache ? "本地缓存 · \(format(snapshot.updatedAt, now: now, timeZone: timeZone))" : "实时 · \(format(snapshot.updatedAt, now: now, timeZone: timeZone))"
        case .refreshing: return "正在更新…"
        case .lastKnown: return "暂无法连接 · \(relativeAge(snapshot.updatedAt, now: now))前数据"
        case .expired: return "数据已过期 · \(format(snapshot.updatedAt, now: now, timeZone: timeZone))"
        case .unavailable: return unavailableText(for: result.failureReason)
        }
    }

    private static func relativeAge(_ date: Date, now: Date) -> String {
        let minutes = max(1, Int(now.timeIntervalSince(date) / 60))
        return "\(minutes) 分钟"
    }

    private static func retryText(_ retryAt: Date?, now: Date) -> String? {
        guard let retryAt else { return nil }
        return "将在 \(max(1, Int(retryAt.timeIntervalSince(now).rounded()))) 秒后自动重试"
    }

    private static func unavailableText(for reason: QuotaFailureReason?) -> String {
        switch reason {
        case .codexNotFound: "未找到 Codex CLI · 请安装并登录 Codex CLI 后重试。"
        case .notAuthenticated: "Codex 未登录 · 请在终端运行：codex login"
        case .timeout: "无法读取 Codex 额度 · 连接超时（10 秒）"
        case .cacheUnreadable: "暂无可用额度数据 · 本地缓存无法读取，正在重新获取。"
        default: "暂未取得额度数据 · 正在连接 Codex…"
        }
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

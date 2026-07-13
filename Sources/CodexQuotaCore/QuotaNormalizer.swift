import Foundation

public enum QuotaNormalizer {
    public static func remaining(fromUsed used: Int) -> Int {
        if used <= 0 { return 100 }
        if used >= 100 { return 0 }
        return 100 - used
    }

    public static func alert(forRemaining remaining: Int) -> QuotaAlert {
        switch remaining {
        case 51...100: .normal
        case 20...50: .warning
        case 0...19: .danger
        default: .unknown
        }
    }

    public static func normalize(
        _ raw: RawQuotaSnapshot,
        source: QuotaSource,
        freshness: QuotaFreshness = .fresh
    ) -> QuotaSnapshot {
        func make(_ kind: QuotaKind, minutes: Int) -> QuotaWindow? {
            guard let rawWindow = raw.windows.first(where: { $0.windowMinutes == minutes }) else { return nil }
            let remaining = remaining(fromUsed: rawWindow.usedPercent)
            return QuotaWindow(
                kind: kind,
                windowMinutes: minutes,
                usedPercent: rawWindow.usedPercent,
                remainingPercent: remaining,
                resetsAt: rawWindow.resetsAt,
                alert: alert(forRemaining: remaining)
            )
        }

        return QuotaSnapshot(
            fiveHour: make(.fiveHour, minutes: 300),
            weekly: make(.weekly, minutes: 10_080),
            source: source,
            freshness: freshness,
            updatedAt: raw.capturedAt
        )
    }
}

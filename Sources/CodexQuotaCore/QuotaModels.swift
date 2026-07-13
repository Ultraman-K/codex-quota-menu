import Foundation

public enum QuotaKind: String, Codable, Sendable { case fiveHour, weekly }
public enum QuotaSource: String, Codable, Sendable { case appServer, sessionLog, cache }
public enum QuotaFreshness: String, Codable, Sendable { case fresh, stale, unavailable }
public enum QuotaAlert: String, Codable, Sendable { case normal, warning, danger, unknown }

public struct RawQuotaWindow: Equatable, Sendable {
    public let windowMinutes: Int
    public let usedPercent: Int
    public let resetsAt: Date?
    public init(windowMinutes: Int, usedPercent: Int, resetsAt: Date?) {
        self.windowMinutes = windowMinutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct RawQuotaSnapshot: Equatable, Sendable {
    public let windows: [RawQuotaWindow]
    public let capturedAt: Date
    public init(windows: [RawQuotaWindow], capturedAt: Date) {
        self.windows = windows
        self.capturedAt = capturedAt
    }
}

public struct QuotaWindow: Codable, Equatable, Sendable {
    public let kind: QuotaKind
    public let windowMinutes: Int
    public let usedPercent: Int
    public let remainingPercent: Int
    public let resetsAt: Date?
    public let alert: QuotaAlert
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let fiveHour: QuotaWindow?
    public let weekly: QuotaWindow?
    public let source: QuotaSource
    public let freshness: QuotaFreshness
    public let updatedAt: Date
}

import Foundation

public enum QuotaKind: String, Codable, Sendable { case fiveHour, weekly }
public enum QuotaSource: String, Codable, Sendable { case appServer, sessionLog, cache }
public enum QuotaFreshness: String, Codable, Sendable { case fresh, stale, unavailable }
public enum QuotaAlert: String, Codable, Sendable { case normal, warning, danger, unknown }
public enum QuotaDisplayState: Equatable, Sendable { case live, refreshing, lastKnown, expired, unavailable }
public enum QuotaFailureReason: Equatable, Sendable { case timeout, codexNotFound, notAuthenticated, processExited, protocolError, networkUnavailable, cacheUnreadable, unknown }

public struct QuotaRefreshResult: Equatable, Sendable {
    public let snapshot: QuotaSnapshot?
    public let state: QuotaDisplayState
    public let failureReason: QuotaFailureReason?
    public let nextRetryAt: Date?

    public init(snapshot: QuotaSnapshot?, state: QuotaDisplayState, failureReason: QuotaFailureReason? = nil, nextRetryAt: Date? = nil) {
        self.snapshot = snapshot
        self.state = state
        self.failureReason = failureReason
        self.nextRetryAt = nextRetryAt
    }
}

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

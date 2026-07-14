import Foundation

public enum RefreshSchedule {
    public static func nextDelay(consecutiveFailures: Int, reason: QuotaFailureReason?) -> Duration {
        if reason == .codexNotFound || reason == .notAuthenticated { return .seconds(300) }
        return switch consecutiveFailures {
        case 0: .seconds(30)
        case 1: .seconds(5)
        case 2: .seconds(10)
        case 3: .seconds(30)
        default: .seconds(60)
        }
    }
}

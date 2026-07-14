import Foundation

public protocol RateLimitProvider: Sendable {
    var source: QuotaSource { get }
    func fetch() async throws -> RawQuotaSnapshot
    func updates() async -> AsyncThrowingStream<RawQuotaSnapshot, Error>
    func stop() async
}

public enum RateLimitProviderError: Error, Equatable {
    case codexNotFound
    case notAuthenticated
    case protocolViolation(String)
    case noQuotaData
    case processExited(Int32)
    case timedOut
}

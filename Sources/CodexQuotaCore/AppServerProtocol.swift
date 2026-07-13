import Foundation

public struct AppServerWireWindow: Codable, Equatable, Sendable {
    public let usedPercent: Int
    public let windowDurationMins: Int?
    public let resetsAt: Int?

    public init(usedPercent: Int, windowDurationMins: Int?, resetsAt: Int?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct AppServerWireSnapshot: Codable, Equatable, Sendable {
    public let primary: AppServerWireWindow?
    public let secondary: AppServerWireWindow?

    public init(primary: AppServerWireWindow?, secondary: AppServerWireWindow?) {
        self.primary = primary
        self.secondary = secondary
    }

    public func mergingSparse(_ update: Self) -> Self {
        .init(
            primary: update.primary ?? primary,
            secondary: update.secondary ?? secondary
        )
    }

    public func toRaw(capturedAt: Date) -> RawQuotaSnapshot {
        let windows = [primary, secondary].compactMap { window -> RawQuotaWindow? in
            guard let window, let duration = window.windowDurationMins else { return nil }
            return .init(
                windowMinutes: duration,
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
        return .init(windows: windows, capturedAt: capturedAt)
    }
}

public struct AppServerDecodedMessage: Sendable {
    public let id: Int?
    public let method: String?
    public let snapshot: AppServerWireSnapshot?
    public let errorMessage: String?
}

public enum AppServerMessageDecoder {
    public static func decode(_ data: Data) throws -> AppServerDecodedMessage {
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            return .init(
                id: envelope.id,
                method: envelope.method,
                snapshot: envelope.result?.rateLimits ?? envelope.params?.rateLimits,
                errorMessage: envelope.error?.message
            )
        } catch {
            throw RateLimitProviderError.protocolViolation("Invalid app-server message: \(error.localizedDescription)")
        }
    }
}

private struct Envelope: Decodable {
    let id: Int?
    let method: String?
    let result: Payload?
    let params: Payload?
    let error: ErrorPayload?
}

private struct Payload: Decodable {
    let rateLimits: AppServerWireSnapshot?
}

private struct ErrorPayload: Decodable {
    let message: String?
}

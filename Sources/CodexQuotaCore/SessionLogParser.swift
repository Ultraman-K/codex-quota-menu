import Foundation

public enum SessionLogParser {
    public static func parse(line: Data, capturedAt: Date) -> RawQuotaSnapshot? {
        guard let event = try? JSONDecoder().decode(Event.self, from: line),
              event.type == "event_msg",
              event.payload?.type == "token_count",
              let limits = event.payload?.rateLimits else {
            return nil
        }

        let windows = [limits.primary, limits.secondary].compactMap { item -> RawQuotaWindow? in
            guard let item else { return nil }
            return .init(
                windowMinutes: item.windowMinutes,
                usedPercent: item.usedPercent,
                resetsAt: item.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
        guard !windows.isEmpty else { return nil }
        return .init(windows: windows, capturedAt: capturedAt)
    }
}

private struct Event: Decodable {
    let type: String
    let payload: Payload?
}

private struct Payload: Decodable {
    let type: String
    let rateLimits: Limits?

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }
}

private struct Limits: Decodable {
    let primary: LogWindow?
    let secondary: LogWindow?
}

private struct LogWindow: Decodable {
    let usedPercent: Int
    let windowMinutes: Int
    let resetsAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

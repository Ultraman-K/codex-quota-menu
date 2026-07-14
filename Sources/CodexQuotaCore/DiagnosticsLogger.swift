import Foundation

public enum DiagnosticsLogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public actor DiagnosticsLogger {
    public static let defaultFileURL = URL(fileURLWithPath: "logs/codex-quota-menu.log")

    private let fileURL: URL
    private let maxBytes: UInt64
    private let formatter: ISO8601DateFormatter

    public init(fileURL: URL = DiagnosticsLogger.defaultFileURL, maxBytes: UInt64 = 1_048_576) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
    }

    public func log(level: DiagnosticsLogLevel, component: String, message: String) {
        let line = "\(formatter.string(from: Date())) \(level.rawValue) [\(component)] \(Self.redact(message))\n"
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try rotateIfNeeded(incomingBytes: UInt64(line.utf8.count))
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: fileURL, options: .atomic)
            }
        } catch {
            // Diagnostics must never break quota refresh or app startup.
        }
    }

    private func rotateIfNeeded(incomingBytes: UInt64) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              UInt64(truncating: size) + incomingBytes > maxBytes else { return }

        let rotatedURL = fileURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: rotatedURL)
        try FileManager.default.moveItem(at: fileURL, to: rotatedURL)
    }

    static func redact(_ message: String) -> String {
        var redacted = message
        let patterns: [(pattern: String, replacement: String)] = [
            (#"(?i)(authorization\s*:\s*bearer\s+)[^\s,}]+"#, "$1[REDACTED]"),
            (#"(?i)(bearer\s+)[^\s,}]+"#, "$1[REDACTED]"),
            (#"(?i)((?:api_key|access_token)\s*[=:]\s*[\"']?)[^\s,}\"']+"#, "$1[REDACTED]"),
            (#"(?i)(\"(?:prompt|content)\"\s*:\s*\")[^\"]*(\")"#, "$1[REDACTED]$2")
        ]
        for item in patterns {
            redacted = redacted.replacingOccurrences(of: item.pattern, with: item.replacement, options: .regularExpression)
        }
        return redacted
    }
}

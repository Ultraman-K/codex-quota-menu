import Foundation

public enum ProxyConfigurationError: Error, Equatable {
    case invalidHost
    case invalidPort
}

public enum ProxyMode: String, Codable, Equatable, Sendable {
    case direct
    case custom
}

public struct ProxyConfiguration: Codable, Equatable, Sendable {
    public let mode: ProxyMode
    public let host: String
    public let port: Int

    public static let direct = ProxyConfiguration(mode: .direct, host: "127.0.0.1", port: 7897)

    public static func custom(host: String, port: Int) throws -> ProxyConfiguration {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty,
              !normalizedHost.contains("://"),
              !normalizedHost.contains("/"),
              !normalizedHost.contains(where: \ .isWhitespace) else {
            throw ProxyConfigurationError.invalidHost
        }
        guard (1...65_535).contains(port) else { throw ProxyConfigurationError.invalidPort }
        return .init(mode: .custom, host: normalizedHost, port: port)
    }

    public var isCustom: Bool { mode == .custom }

    public var menuText: String {
        isCustom ? "Clash 代理端口：\(port)" : "未使用代理"
    }

    public func applying(to base: [String: String]) -> [String: String] {
        var environment = base
        let proxyKeys = ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"]
        proxyKeys.forEach { environment.removeValue(forKey: $0) }
        guard isCustom else { return environment }

        let httpURL = "http://\(host):\(port)"
        let socksURL = "socks5://\(host):\(port)"
        environment["HTTP_PROXY"] = httpURL
        environment["HTTPS_PROXY"] = httpURL
        environment["ALL_PROXY"] = socksURL
        environment["http_proxy"] = httpURL
        environment["https_proxy"] = httpURL
        environment["all_proxy"] = socksURL
        return environment
    }
}

public struct ProxyConfigurationStore {
    private enum Key {
        static let mode = "CodexQuotaMenu.proxy.mode"
        static let host = "CodexQuotaMenu.proxy.host"
        static let port = "CodexQuotaMenu.proxy.port"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ProxyConfiguration {
        guard defaults.string(forKey: Key.mode) == ProxyMode.custom.rawValue,
              let host = defaults.string(forKey: Key.host) else {
            return .direct
        }
        let port = defaults.integer(forKey: Key.port)
        return (try? .custom(host: host, port: port)) ?? .direct
    }

    public func save(_ configuration: ProxyConfiguration) throws {
        if configuration.isCustom {
            let validated = try ProxyConfiguration.custom(host: configuration.host, port: configuration.port)
            defaults.set(validated.mode.rawValue, forKey: Key.mode)
            defaults.set(validated.host, forKey: Key.host)
            defaults.set(validated.port, forKey: Key.port)
        } else {
            defaults.set(ProxyMode.direct.rawValue, forKey: Key.mode)
            defaults.removeObject(forKey: Key.host)
            defaults.removeObject(forKey: Key.port)
        }
    }
}

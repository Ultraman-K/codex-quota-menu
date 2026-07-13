import AppKit
import CodexQuotaCore

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: RateLimitCoordinator?
    private var statusItem: StatusItemController?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    private var launchAtLoginManager: LaunchAtLoginManager?
    private var launchAtLoginEnabled = false
    private var statusBarDisplayMode = StatusBarDisplayModePreference.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let locator = CodexExecutableLocator()
        let fallback = SessionLogRateLimitProvider()
        let primary: any RateLimitProvider
        do {
            primary = try AppServerRateLimitProvider()
        } catch {
            primary = UnavailableProvider(error: error)
        }
        let cacheURL = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/CodexQuotaMenu/quota-cache.json")
        coordinator = RateLimitCoordinator(primary: primary, fallback: fallback, cache: FileQuotaCache(fileURL: cacheURL))
        launchAtLoginManager = LaunchAtLoginManager(
            executableURL: URL(fileURLWithPath: CommandLine.arguments[0]),
            codexURL: locator.resolve()
        )
        statusItem = StatusItemController(
            onRefresh: { [weak self] in self?.refresh() },
            onToggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            onToggleCompactMode: { [weak self] in self?.toggleCompactMode() },
            displayMode: statusBarDisplayMode
        )
        Task { [weak self] in
            let enabled = await self?.launchAtLoginManager?.isEnabled() ?? false
            await MainActor.run {
                self?.launchAtLoginEnabled = enabled
                self?.statusItem?.setLaunchAtLoginEnabled(enabled)
            }
        }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTask?.cancel()
        updatesTask?.cancel()
        guard let coordinator else { return }
        Task { await coordinator.stop() }
    }

    private func refresh() {
        guard refreshTask == nil, let coordinator else { return }
        statusItem?.setRefreshing(true)
        let startedAt = ContinuousClock.now
        refreshTask = Task { [weak self] in
            do {
                let snapshot = try await coordinator.refresh()
                self?.statusItem?.render(snapshot: snapshot)
                self?.statusItem?.setError(nil)
                if snapshot.source == .appServer {
                    self?.startListeningForUpdates()
                }
            } catch {
                self?.statusItem?.render(snapshot: await coordinator.current())
                self?.statusItem?.setError(self?.userMessage(for: error))
            }
            let minimumDisabledDuration = Duration.seconds(1)
            let elapsed = startedAt.duration(to: .now)
            if elapsed < minimumDisabledDuration {
                try? await Task.sleep(for: minimumDisabledDuration - elapsed)
            }
            self?.refreshTask = nil
            self?.statusItem?.setRefreshing(false)
        }
    }

    private func startListeningForUpdates() {
        guard updatesTask == nil, let coordinator else { return }
        updatesTask = Task { [weak self] in
            defer { self?.updatesTask = nil }
            let updates = await coordinator.updates()
            do {
                for try await snapshot in updates {
                    guard !Task.isCancelled else { return }
                    self?.statusItem?.render(snapshot: snapshot)
                    self?.statusItem?.setError(nil)
                }
            } catch {
                self?.statusItem?.setError(self?.userMessage(for: error))
            }
        }
    }

    private func toggleLaunchAtLogin() {
        guard let launchAtLoginManager else { return }
        let requested = !launchAtLoginEnabled
        Task { [weak self] in
            do {
                let enabled = try await launchAtLoginManager.setEnabled(requested)
                self?.launchAtLoginEnabled = enabled
                self?.statusItem?.setLaunchAtLoginEnabled(enabled)
                self?.statusItem?.setError(nil)
            } catch {
                self?.statusItem?.setError("登录时自动启动设置失败")
            }
        }
    }

    private func toggleCompactMode() {
        statusBarDisplayMode = statusBarDisplayMode == .compact ? .full : .compact
        StatusBarDisplayModePreference.save(statusBarDisplayMode)
        statusItem?.setDisplayMode(statusBarDisplayMode)
    }

    private func userMessage(for error: Error) -> String {
        guard let error = error as? RateLimitProviderError else { return "无法刷新额度" }
        return switch error {
        case .codexNotFound: "未找到 Codex CLI"
        case .notAuthenticated: "Codex 未登录"
        case .noQuotaData: "暂无额度数据"
        default: "无法刷新额度"
        }
    }
}

private actor UnavailableProvider: RateLimitProvider {
    nonisolated let source: QuotaSource = .appServer
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func fetch() async throws -> RawQuotaSnapshot { throw error }

    func updates() async -> AsyncThrowingStream<RawQuotaSnapshot, Error> {
        AsyncThrowingStream { continuation in continuation.finish(throwing: error) }
    }

    func stop() async {}
}

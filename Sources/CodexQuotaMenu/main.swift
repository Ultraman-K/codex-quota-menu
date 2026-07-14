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
    private var consecutiveFailures = 0
    private var refreshTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    private var launchAtLoginManager: LaunchAtLoginManager?
    private var launchAtLoginEnabled = false
    private var statusBarDisplayMode = StatusBarDisplayModePreference.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let locator = CodexExecutableLocator()
        let primary: any RateLimitProvider
        do {
            primary = try AppServerRateLimitProvider()
        } catch {
            primary = UnavailableProvider(error: error)
        }
        let cacheURL = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/CodexQuotaMenu/quota-cache.json")
        coordinator = RateLimitCoordinator(primary: primary, cache: FileQuotaCache(fileURL: cacheURL))
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
            defer {
                self?.refreshTask = nil
                self?.statusItem?.setRefreshing(false)
            }
            let result = await coordinator.refresh()
            self?.statusItem?.render(result: result)
            if result.state == .live, result.snapshot?.source == .appServer {
                    self?.startListeningForUpdates()
            }
            let minimumDisabledDuration = Duration.seconds(1)
            let elapsed = startedAt.duration(to: .now)
            if elapsed < minimumDisabledDuration {
                try? await Task.sleep(for: minimumDisabledDuration - elapsed)
            }
            self?.scheduleNextRefresh(for: result)
        }
    }

    private func scheduleNextRefresh(for result: QuotaRefreshResult) {
        refreshTimer?.invalidate()
        if result.state == .live { consecutiveFailures = 0 } else { consecutiveFailures += 1 }
        let delay = RefreshSchedule.nextDelay(consecutiveFailures: consecutiveFailures, reason: result.failureReason)
        let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
        refreshTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
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

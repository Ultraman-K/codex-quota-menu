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
    private let proxyStore = ProxyConfigurationStore()
    private var proxyConfiguration: ProxyConfiguration = .direct
    private var connectionGeneration = 0
    private let logger = DiagnosticsLogger()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await logger.log(level: .info, component: "app", message: "started") }
        let locator = CodexExecutableLocator()
        proxyConfiguration = proxyStore.load()
        coordinator = makeCoordinator()
        launchAtLoginManager = LaunchAtLoginManager(
            executableURL: URL(fileURLWithPath: CommandLine.arguments[0]),
            codexURL: locator.resolve()
        )
        statusItem = StatusItemController(
            onRefresh: { [weak self] in self?.refresh() },
            onToggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            onToggleCompactMode: { [weak self] in self?.toggleCompactMode() },
            onConfigureProxy: { [weak self] in self?.configureProxy() },
            proxyMenuText: proxyConfiguration.menuText,
            displayMode: statusBarDisplayMode
        )
        Task { [weak self] in
            let enabled = await self?.launchAtLoginManager?.isEnabled() ?? false
            await MainActor.run {
                self?.launchAtLoginEnabled = enabled
                self?.statusItem?.setLaunchAtLoginEnabled(enabled)
            }
        }
        Task { [weak self] in
            guard let self, let coordinator = self.coordinator else { return }
            let cached = await coordinator.loadCachedSnapshot()
            if cached.snapshot != nil { self.statusItem?.render(result: cached) }
            self.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await logger.log(level: .info, component: "app", message: "terminating") }
        refreshTimer?.invalidate()
        refreshTask?.cancel()
        updatesTask?.cancel()
        guard let coordinator else { return }
        Task { await coordinator.stop() }
    }

    private func refresh() {
        guard refreshTask == nil, let coordinator else { return }
        let generation = connectionGeneration
        statusItem?.setRefreshing(true)
        refreshTask = Task { [weak self] in
            defer {
                if self?.connectionGeneration == generation {
                    self?.refreshTask = nil
                    self?.statusItem?.setRefreshing(false)
                }
            }
            let refreshed = await coordinator.refresh()
            guard self?.connectionGeneration == generation else { return }
            if let self {
                let level: DiagnosticsLogLevel = refreshed.state == .live ? .info : .error
                let reason = refreshed.failureReason.map(String.init(describing:)) ?? "none"
                Task { await self.logger.log(level: level, component: "refresh", message: "state=\(refreshed.state) reason=\(reason)") }
            }
            let result = self?.scheduleNextRefresh(for: refreshed) ?? refreshed
            self?.statusItem?.render(result: result)
            self?.statusItem?.setError(self?.networkErrorText(for: result))
            if result.state == .live, result.snapshot?.source == .appServer {
                    self?.startListeningForUpdates()
            }
        }
    }

    private func scheduleNextRefresh(for result: QuotaRefreshResult) -> QuotaRefreshResult {
        refreshTimer?.invalidate()
        if result.state == .live { consecutiveFailures = 0 } else { consecutiveFailures += 1 }
        let delay = RefreshSchedule.nextDelay(consecutiveFailures: consecutiveFailures, reason: result.failureReason)
        let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
        let retryAt = Date().addingTimeInterval(seconds)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        guard result.state != .live else { return result }
        return .init(snapshot: result.snapshot, state: result.state, failureReason: result.failureReason, nextRetryAt: retryAt)
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

    private func makeCoordinator() -> RateLimitCoordinator {
        let locator = CodexExecutableLocator()
        let environment = proxyConfiguration.applying(to: ProcessInfo.processInfo.environment)
        let primary: any RateLimitProvider
        do {
            primary = try AppServerRateLimitProvider(locator: locator, environment: environment, logger: logger)
        } catch {
            primary = UnavailableProvider(error: error)
        }
        let cacheURL = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/CodexQuotaMenu/quota-cache.json")
        return RateLimitCoordinator(primary: primary, cache: FileQuotaCache(fileURL: cacheURL))
    }

    private func configureProxy() {
        let alert = NSAlert()
        alert.messageText = "网络代理"
        alert.informativeText = "仅影响本应用读取 Codex 额度。"
        alert.addButton(withTitle: "保存并立即刷新")
        alert.addButton(withTitle: "取消")

        let formWidth: CGFloat = 292
        let labelWidth: CGFloat = 108
        let controlX = labelWidth + 12
        let controlWidth = formWidth - controlX
        let form = NSView(frame: NSRect(x: 0, y: 0, width: formWidth, height: 114))
        form.autoresizingMask = []

        let mode = NSPopUpButton(
            frame: NSRect(x: controlX, y: 78, width: controlWidth, height: 28),
            pullsDown: false
        )
        mode.addItems(withTitles: ["直接连接", "自定义 Clash 代理"])
        mode.selectItem(at: proxyConfiguration.isCustom ? 1 : 0)
        let host = NSTextField(frame: NSRect(x: controlX, y: 39, width: controlWidth, height: 28))
        host.stringValue = proxyConfiguration.host
        let port = NSTextField(frame: NSRect(x: controlX, y: 0, width: controlWidth, height: 28))
        port.stringValue = String(proxyConfiguration.port)

        [mode, host, port].forEach { $0.autoresizingMask = [] }

        addProxyLabel("模式", to: form, y: 83, width: labelWidth)
        addProxyLabel("代理主机", to: form, y: 44, width: labelWidth)
        addProxyLabel("Clash 混合端口", to: form, y: 5, width: labelWidth)
        form.addSubview(mode)
        form.addSubview(host)
        form.addSubview(port)
        alert.accessoryView = form

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let configuration: ProxyConfiguration
            if mode.indexOfSelectedItem == 0 {
                configuration = .direct
            } else {
                guard let portNumber = Int(port.stringValue) else { throw ProxyConfigurationError.invalidPort }
                configuration = try .custom(host: host.stringValue, port: portNumber)
            }
            try proxyStore.save(configuration)
            proxyConfiguration = configuration
            statusItem?.setProxyMenuText(configuration.menuText)
            restartConnectionForProxyChange()
        } catch {
            statusItem?.setError("代理配置无效：请填写主机和 1–65535 端口")
        }
    }

    private func addProxyLabel(_ text: String, to form: NSView, y: CGFloat, width: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.alignment = .left
        label.frame = NSRect(x: 0, y: y, width: width, height: 20)
        form.addSubview(label)
    }

    private func restartConnectionForProxyChange() {
        connectionGeneration += 1
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTask?.cancel()
        updatesTask?.cancel()
        refreshTask = nil
        updatesTask = nil
        let previousCoordinator = coordinator
        Task { @MainActor [weak self] in
            await previousCoordinator?.stop()
            guard let self else { return }
            self.coordinator = self.makeCoordinator()
            self.refresh()
        }
    }

    private func networkErrorText(for result: QuotaRefreshResult) -> String? {
        guard result.failureReason == .networkUnavailable else { return nil }
        if proxyConfiguration.isCustom {
            return "无法通过 Clash 代理 \(proxyConfiguration.host):\(proxyConfiguration.port) 连接服务"
        }
        return "无法连接 ChatGPT 服务 · 可在“网络代理”中配置 Clash"
    }

    private func userMessage(for error: Error) -> String {
        guard let error = error as? RateLimitProviderError else { return "无法刷新额度" }
        return switch error {
        case .codexNotFound: "未找到 Codex CLI"
        case .notAuthenticated: "Codex 未登录"
        case .noQuotaData: "暂无额度数据"
        case .networkUnavailable: "无法连接 ChatGPT 服务"
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

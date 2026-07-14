import AppKit
import CodexQuotaCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onRefresh: () -> Void
    private let onToggleLaunchAtLogin: () -> Void
    private let onToggleCompactMode: () -> Void
    private let onConfigureProxy: () -> Void
    private var currentDisplay = QuotaPresentation.make(snapshot: nil)
    private var launchAtLoginEnabled = false
    private var displayMode: StatusBarDisplayMode
    private var isRefreshing = false
    private var errorMessage: String?
    private var proxyMenuText: String

    init(
        onRefresh: @escaping () -> Void,
        onToggleLaunchAtLogin: @escaping () -> Void,
        onToggleCompactMode: @escaping () -> Void,
        onConfigureProxy: @escaping () -> Void,
        proxyMenuText: String,
        displayMode: StatusBarDisplayMode
    ) {
        self.onRefresh = onRefresh
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        self.onToggleCompactMode = onToggleCompactMode
        self.onConfigureProxy = onConfigureProxy
        self.proxyMenuText = proxyMenuText
        self.displayMode = displayMode
        super.init()
        item.menu = makeMenu()
        render(display: currentDisplay)
    }

    func render(snapshot: QuotaSnapshot?) {
        render(result: .init(snapshot: snapshot, state: snapshot == nil ? .unavailable : .live))
    }

    func render(result: QuotaRefreshResult) {
        currentDisplay = QuotaPresentation.make(result: result)
        render(display: currentDisplay)
        item.menu = makeMenu()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
        item.menu = makeMenu()
    }

    func setDisplayMode(_ mode: StatusBarDisplayMode) {
        displayMode = mode
        render(display: currentDisplay)
        item.menu = makeMenu()
    }

    func setRefreshing(_ refreshing: Bool) {
        isRefreshing = refreshing
        item.menu = makeMenu()
    }

    func setError(_ message: String?) {
        errorMessage = message
        item.menu = makeMenu()
    }

    func setProxyMenuText(_ text: String) {
        proxyMenuText = text
        item.menu = makeMenu()
    }

    private func render(display: QuotaDisplay) {
        guard let button = item.button else { return }
        button.attributedTitle = statusTitle(display: display)
        button.toolTip = display.tooltip
        button.setAccessibilityLabel(display.tooltip)
    }

    private func statusTitle(display: QuotaDisplay) -> NSAttributedString {
        let title = NSMutableAttributedString()
        if display.usesMutedQuotaColors, displayMode == .full {
            title.append(NSAttributedString(string: "◷ ", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        }
        let parts = QuotaPresentation.statusText(display, mode: displayMode).components(separatedBy: " | ")
        title.append(metricText(parts[safe: 0] ?? "5h --", card: display.cards.first(where: { $0.title == "5 小时使用限制" }), muted: display.usesMutedQuotaColors))
        title.append(NSAttributedString(string: " | ", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        title.append(metricText(parts[safe: 1] ?? "7d --", card: display.cards.first(where: { $0.title == "每周使用限额" }), muted: display.usesMutedQuotaColors))
        return title
    }

    private func metricText(_ text: String, card: QuotaCardDisplay?, muted: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let attachment = NSTextAttachment()
        attachment.image = QuotaRingRenderer.image(remainingPercent: card?.remainingPercent, alert: card?.alert, muted: muted)
        attachment.bounds = NSRect(x: 0, y: -2, width: 14, height: 14)
        result.append(NSAttributedString(attachment: attachment))
        result.append(NSAttributedString(string: " \(text)", attributes: [.foregroundColor: muted ? NSColor.secondaryLabelColor : QuotaVisualColor.foreground(for: card?.alert)]))
        return result
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        if currentDisplay.cards.isEmpty {
            for line in currentDisplay.tooltip.split(separator: "\n", omittingEmptySubsequences: false) {
                let detail = NSMenuItem(title: String(line), action: nil, keyEquivalent: "")
                detail.isEnabled = false
                menu.addItem(detail)
            }
        } else {
            let cards = NSMenuItem()
            let hasCheckmark = displayMode == .compact || launchAtLoginEnabled
            cards.view = QuotaCardMenuItemView(cards: currentDisplay.cards, leadingInset: hasCheckmark ? 24 : 12)
            menu.addItem(cards)
        }
        if let errorMessage {
            let error = NSMenuItem(title: errorMessage, action: nil, keyEquivalent: "")
            error.isEnabled = false
            error.attributedTitle = NSAttributedString(string: errorMessage, attributes: [.foregroundColor: NSColor.systemRed])
            menu.addItem(error)
        }
        if let detailStatusText = currentDisplay.detailStatusText {
            let status = NSMenuItem(title: detailStatusText, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        }
        if let retryText = currentDisplay.retryText {
            let retry = NSMenuItem(title: retryText, action: nil, keyEquivalent: "")
            retry.isEnabled = false
            menu.addItem(retry)
        }
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: isRefreshing ? "正在刷新…" : "立即刷新", action: #selector(refresh), keyEquivalent: "")
        refresh.target = self
        refresh.isEnabled = !isRefreshing
        menu.addItem(refresh)
        let compactMode = NSMenuItem(title: "简洁模式", action: #selector(toggleCompactMode), keyEquivalent: "")
        compactMode.target = self
        compactMode.state = displayMode == .compact ? .on : .off
        menu.addItem(compactMode)
        let launchAtLogin = NSMenuItem(title: "登录时自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLogin)
        let proxy = NSMenuItem(title: "网络代理", action: #selector(configureProxy), keyEquivalent: "")
        proxy.target = self
        menu.addItem(proxy)
        let proxyInfo = NSMenuItem(title: proxyMenuText, action: nil, keyEquivalent: "")
        proxyInfo.isEnabled = false
        proxyInfo.attributedTitle = NSAttributedString(
            string: proxyMenuText,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(proxyInfo)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let refreshItem = menu.items.first(where: { $0.action == #selector(refresh) }) else { return }
        refreshItem.isEnabled = !isRefreshing
    }

    @objc private func refresh(_ sender: NSMenuItem) {
        guard !isRefreshing else { return }
        let trackingMenu = sender.menu
        sender.title = "正在刷新…"
        sender.isEnabled = false
        onRefresh()
        DispatchQueue.main.async {
            trackingMenu?.cancelTrackingWithoutAnimation()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        onToggleLaunchAtLogin()
    }

    @objc private func toggleCompactMode() {
        onToggleCompactMode()
    }

    @objc private func configureProxy() {
        onConfigureProxy()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

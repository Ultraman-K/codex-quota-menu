import AppKit
import CodexQuotaCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onRefresh: () -> Void
    private let onToggleLaunchAtLogin: () -> Void
    private var currentDisplay = QuotaPresentation.make(snapshot: nil)
    private var launchAtLoginEnabled = false
    private var isRefreshing = false
    private var errorMessage: String?

    init(onRefresh: @escaping () -> Void, onToggleLaunchAtLogin: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        super.init()
        item.menu = makeMenu()
        render(display: currentDisplay)
    }

    func render(snapshot: QuotaSnapshot?) {
        currentDisplay = QuotaPresentation.make(snapshot: snapshot)
        render(display: currentDisplay)
        item.menu = makeMenu()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
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

    private func render(display: QuotaDisplay) {
        guard let button = item.button else { return }
        button.attributedTitle = statusTitle(display: display)
        button.toolTip = display.tooltip
        button.setAccessibilityLabel(display.tooltip)
    }

    private func statusTitle(display: QuotaDisplay) -> NSAttributedString {
        let title = NSMutableAttributedString()
        let parts = display.menuText.components(separatedBy: " | ")
        title.append(metricText(parts[safe: 0] ?? "5h --", card: display.cards.first(where: { $0.title == "5 小时使用限制" })))
        title.append(NSAttributedString(string: " | ", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        title.append(metricText(parts[safe: 1] ?? "7d --", card: display.cards.first(where: { $0.title == "每周使用限额" })))
        return title
    }

    private func metricText(_ text: String, card: QuotaCardDisplay?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let attachment = NSTextAttachment()
        attachment.image = QuotaRingRenderer.image(remainingPercent: card?.remainingPercent, alert: card?.alert)
        attachment.bounds = NSRect(x: 0, y: -2, width: 14, height: 14)
        result.append(NSAttributedString(attachment: attachment))
        result.append(NSAttributedString(string: " \(text)", attributes: [.foregroundColor: QuotaVisualColor.foreground(for: card?.alert)]))
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
            cards.view = QuotaCardMenuItemView(cards: currentDisplay.cards)
            menu.addItem(cards)
        }
        if let errorMessage {
            let error = NSMenuItem(title: errorMessage, action: nil, keyEquivalent: "")
            error.isEnabled = false
            error.attributedTitle = NSAttributedString(string: errorMessage, attributes: [.foregroundColor: NSColor.systemRed])
            menu.addItem(error)
        }
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refresh), keyEquivalent: "")
        refresh.target = self
        refresh.isEnabled = !isRefreshing
        menu.addItem(refresh)
        let source = NSMenuItem(title: "来源：\(currentDisplay.sourceText)", action: nil, keyEquivalent: "")
        source.isEnabled = false
        menu.addItem(source)
        let launchAtLogin = NSMenuItem(title: "登录时自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLogin)
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

    @objc private func refresh() {
        guard !isRefreshing else { return }
        onRefresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        onToggleLaunchAtLogin()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

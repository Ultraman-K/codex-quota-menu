import AppKit
import CodexQuotaCore

@MainActor
final class QuotaCardMenuItemView: NSView {
    private let rows: [QuotaCardRowView]

    init(cards: [QuotaCardDisplay]) {
        rows = cards.map(QuotaCardRowView.init)
        let height = CGFloat(max(rows.count, 1)) * 92
        super.init(frame: NSRect(x: 0, y: 0, width: 168, height: height))
        for row in rows {
            addSubview(row)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let rowHeight = bounds.height / CGFloat(max(rows.count, 1))
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: bounds.height - CGFloat(index + 1) * rowHeight, width: bounds.width, height: rowHeight)
        }
    }
}

@MainActor
private final class QuotaCardRowView: NSView {
    private let card: QuotaCardDisplay
    private let titleLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let trackView = NSView()
    private let fillView = NSView()

    init(card: QuotaCardDisplay) {
        self.card = card
        super.init(frame: .zero)
        wantsLayer = true

        titleLabel.stringValue = card.title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .labelColor
        resetLabel.stringValue = card.resetText
        resetLabel.font = .systemFont(ofSize: 13)
        resetLabel.textColor = .secondaryLabelColor
        valueLabel.stringValue = "剩余 \(card.remainingPercent)%"
        valueLabel.font = .systemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = QuotaVisualColor.foreground(for: card.alert)

        trackView.wantsLayer = true
        trackView.layer?.cornerRadius = 6
        trackView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        fillView.wantsLayer = true
        fillView.layer?.cornerRadius = 6
        fillView.layer?.backgroundColor = QuotaVisualColor.foreground(for: card.alert).cgColor

        addSubview(titleLabel)
        addSubview(resetLabel)
        addSubview(trackView)
        trackView.addSubview(fillView)
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let inset: CGFloat = 12
        let valueWidth = ceil(valueLabel.intrinsicContentSize.width) + 6
        let gap: CGFloat = 8
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 31, width: bounds.width - inset * 2, height: 20)
        resetLabel.frame = NSRect(x: inset, y: bounds.height - 53, width: bounds.width - inset * 2, height: 18)
        let trackWidth: CGFloat = 88
        trackView.frame = NSRect(x: inset, y: 16, width: trackWidth, height: 12)
        fillView.frame = NSRect(x: 0, y: 0, width: trackView.bounds.width * CGFloat(card.remainingPercent) / 100, height: trackView.bounds.height)
        let valueHeight = ceil(valueLabel.intrinsicContentSize.height)
        valueLabel.frame = NSRect(
            x: trackView.frame.maxX + gap,
            y: trackView.frame.midY - valueHeight / 2,
            width: valueWidth,
            height: valueHeight
        )
    }
}

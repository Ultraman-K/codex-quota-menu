import AppKit
import CodexQuotaCore

enum QuotaVisualColor {
    static func foreground(for alert: QuotaAlert?) -> NSColor {
        switch alert {
        case .warning: .systemYellow
        case .danger: .systemRed
        case .unknown, nil: .secondaryLabelColor
        case .normal: .labelColor
        }
    }
}

enum QuotaRingRenderer {
    static func image(remainingPercent: Int?, alert: QuotaAlert?, muted: Bool = false) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 5
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
            track.lineWidth = 2.5
            let color = muted ? NSColor.secondaryLabelColor : QuotaVisualColor.foreground(for: alert)
            color.withAlphaComponent(0.28).setStroke()
            track.stroke()

            guard let remainingPercent else { return true }
            let progress = max(0, min(100, remainingPercent))
            guard progress > 0 else { return true }
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - CGFloat(progress) * 3.6,
                clockwise: true
            )
            arc.lineCapStyle = .round
            arc.lineWidth = 2.5
            color.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}

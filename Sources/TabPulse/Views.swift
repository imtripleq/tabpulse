import Cocoa

enum Palette {
    static let accent = dynamic(0x8a4fd8, 0xc4a1f5)
    static let warn = dynamic(0xc56a12, 0xf0a35e)
    static let ok = dynamic(0x2f8a4f, 0x7fd59a)
    static let highlight = rgb(0x8a4fd8)
    static let pillTint = rgb(0x8a4fd8, alpha: 0.18)

    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light) }
    }
}

enum Text {
    static func draw(_ s: String, in r: NSRect, font: NSFont, color: NSColor, align: NSTextAlignment = .left, kern: CGFloat = 0) {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.lineBreakMode = .byTruncatingTail
        (s as NSString).draw(in: r, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: p, .kern: kern])
    }
    static func lineHeight(_ f: NSFont) -> CGFloat { ceil(f.ascender - f.descender + f.leading) }
}

// MARK: - Menu views, drawn by hand: two-line rows, coloured glyph, right-aligned time

final class SessionRowView: NSView {
    static let height: CGFloat = 44
    private var glyph = "", glyphColor = NSColor.labelColor, title = "", sub = "", when = ""
    override var isFlipped: Bool { true }

    func show(state: String, detail: String, title: String, when: String, frame: String, isNew: Bool = false) {
        switch state {
        case "working":
            glyph = frame
            glyphColor = Palette.accent
            sub = "working · " + (detail.isEmpty ? "thinking" : detail)
        case "waiting":
            glyph = "●"
            glyphColor = Palette.warn
            sub = "needs you" + (detail.isEmpty ? "" : " · " + detail)
        default:
            glyph = "✓"
            glyphColor = Palette.ok
            // Only a StopFailure's reason; other done writes can carry the last tool's detail.
            sub = "done" + (detail.hasPrefix("stopped") ? " · " + detail : "") + (isNew ? " · new" : "")
        }
        self.title = title
        self.when = when
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let hi = enclosingMenuItem?.isHighlighted ?? false
        if hi {
            Palette.highlight.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        let main = hi ? NSColor.white : NSColor.labelColor
        let dim = hi ? NSColor.white.withAlphaComponent(0.8) : NSColor.secondaryLabelColor
        let w = bounds.width, textW = w - 42 - 78
        // Wide enough for the three-cell Typing and Sine spinners, which truncate to an ellipsis at 22 pt.
        Text.draw(glyph, in: NSRect(x: 9, y: 13, width: 28, height: 18),
                  font: .monospacedSystemFont(ofSize: 13, weight: .regular), color: hi ? .white : glyphColor, align: .center)
        Text.draw(title, in: NSRect(x: 42, y: 6, width: textW, height: 17), font: .systemFont(ofSize: 13), color: main)
        Text.draw(sub, in: NSRect(x: 42, y: 23, width: textW, height: 15), font: .systemFont(ofSize: 11.5), color: dim)
        Text.draw(when, in: NSRect(x: w - 14 - 64, y: 14, width: 64, height: 16),
                  font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular), color: dim, align: .right)
    }

    // View-based menu items get the click instead of the menu, so close the menu and fire the item's action.
    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, item.isEnabled, let action = item.action else { return }
        item.menu?.cancelTracking()
        DispatchQueue.main.async { NSApp.sendAction(action, to: item.target, from: item) }
    }
}

final class MenuTextView: NSView {
    private let text: String
    private let font: NSFont
    private let kern: CGFloat
    override var isFlipped: Bool { true }

    init(_ text: String, font: NSFont, kern: CGFloat = 0, width: CGFloat, height: CGFloat) {
        self.text = text
        self.font = font
        self.kern = kern
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let h = Text.lineHeight(font)
        Text.draw(text, in: NSRect(x: 14, y: (bounds.height - h) / 2, width: bounds.width - 28, height: h),
                  font: font, color: .secondaryLabelColor, kern: kern)
    }
}

import Cocoa

/// `TabPulse --render-preview <dir>` draws the menu with sample sessions into menu-light.png and
/// menu-dark.png, using the app's own views. The README images come from here.
enum Preview {
    private static let samples: [(state: String, title: String, detail: String, when: String)] = [
        ("waiting", "fix the flaky checkout test", "permission to use Edit", "0:48"),
        ("working", "refactor auth middleware", "running Bash", "3:22"),
        ("working", "write the release notes", "thinking", "0:51"),
        ("done", "add a dark mode toggle", "", "2m ago"),
    ]

    static func render(to dir: String) {
        PillView.stillOverride = false
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for dark in [false, true] {
            let path = (dir as NSString).appendingPathComponent(dark ? "menu-dark.png" : "menu-light.png")
            guard let png = snapshot(dark: dark).representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: URL(fileURLWithPath: path))
            print(path)
        }
    }

    /// `TabPulse --style-gallery [spin,orbit,…]` opens a window with the menu bar styles running, one column per
    /// section, for checking new ones. Environment:
    ///   TABPULSE_GALLERY_SCALE=3        zoom the whole window, for screenshots that show detail
    ///   TABPULSE_APPEARANCE=light|dark  force an appearance
    ///   TABPULSE_GALLERY_WORKING=4      session count with speed-up on (default: 2 at base speed)
    ///   TABPULSE_STILL=1                show the Reduce Motion poses
    ///   TABPULSE_SNAP_DIR=d TABPULSE_SNAP_COUNT=n TABPULSE_SNAP_EVERY=s
    ///                                   after 1 s, save n screenshots s seconds apart to d/frame-000.png…, then quit
    /// Prints `window <number> <x>,<y>,<w>,<h>` (top-left origin, as `screencapture -R` takes it) once shown.
    static func gallery(only filter: String?) {
        let env = ProcessInfo.processInfo.environment
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        switch env["TABPULSE_APPEARANCE"] {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark": app.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        var styles = BarStyle.allCases
        if let filter {
            let names = filter.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let unknown = names.filter { BarStyle(rawValue: $0) == nil }
            guard unknown.isEmpty else {
                let all = BarStyle.allCases.map(\.rawValue).joined(separator: ",")
                FileHandle.standardError.write(Data("Unknown style \(unknown.joined(separator: ", ")). Styles: \(all)\n".utf8))
                exit(2)
            }
            styles = styles.filter { names.contains($0.rawValue) }
        }
        var columns: [[BarStyle]] = []
        for s in styles {
            if columns.last?.first?.section == s.section { columns[columns.count - 1].append(s) } else { columns.append([s]) }
        }
        PillView.stillOverride = env["TABPULSE_STILL"] == "1" ? true : nil
        let working = max(1, Int(env["TABPULSE_GALLERY_WORKING"] ?? "") ?? 2)
        let busy = env["TABPULSE_GALLERY_WORKING"] != nil

        let margin: CGFloat = 16, headerH: CGFloat = 24, cellW: CGFloat = 156, cellH: CGFloat = 32
        let size = NSSize(width: margin * 2 + cellW * CGFloat(columns.count),
                          height: margin + headerH + cellH * CGFloat(columns.map(\.count).max() ?? 0) + margin)
        let scale = max(1, CGFloat(Double(env["TABPULSE_GALLERY_SCALE"] ?? "") ?? 1))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "TabPulse menu bar styles"
        window.isReleasedWhenClosed = false
        _ = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NSApp.terminate(nil)
        }
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit TabPulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        app.mainMenu = NSMenu()
        app.mainMenu?.addItem(appItem)
        let content = window.contentView!
        content.bounds = NSRect(origin: .zero, size: size)   // smaller bounds than frame: everything inside draws zoomed
        var pills: [PillView] = []
        for (c, column) in columns.enumerated() {
            let x = margin + CGFloat(c) * cellW, top = size.height - margin
            let heading = NSTextField(labelWithString: column[0].section.uppercased())
            heading.font = .systemFont(ofSize: 11, weight: .semibold)
            heading.textColor = .secondaryLabelColor
            heading.frame = NSRect(x: x + 2, y: top - headerH + 6, width: cellW - 8, height: 16)
            content.addSubview(heading)
            for (r, s) in column.enumerated() {
                let y = top - headerH - cellH * CGFloat(r + 1)
                let pill = PillView(frame: .zero)
                pill.style = s
                pill.speedsUp = busy
                pill.set(working: working, waiting: 0, finished: 0)
                pill.frame = NSRect(x: x, y: y + (cellH - 24) / 2, width: pill.width, height: 24)
                content.addSubview(pill)
                let label = NSTextField(labelWithString: s.name)
                label.frame = NSRect(x: x + 60, y: y + (cellH - 17) / 2, width: cellW - 64, height: 17)
                content.addSubview(label)
                pills.append(pill)
            }
        }
        let timer = Timer(timeInterval: 0.12, repeats: true) { _ in
            for p in pills { p.set(working: working, waiting: 0, finished: 0) }
        }
        RunLoop.main.add(timer, forMode: .common)
        if let screen = NSScreen.main?.visibleFrame { window.setFrameTopLeftPoint(NSPoint(x: screen.minX + 80, y: screen.maxY - 60)) }
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        let f = window.frame, top = NSScreen.screens.first?.frame.maxY ?? f.maxY
        print("window \(window.windowNumber) \(Int(f.minX)),\(Int(top - f.maxY)),\(Int(f.width)),\(Int(f.height))")
        fflush(stdout)
        if let dir = env["TABPULSE_SNAP_DIR"], !dir.isEmpty {
            snap(window: window.windowNumber, to: dir, count: Int(env["TABPULSE_SNAP_COUNT"] ?? "") ?? 1,
                 every: Double(env["TABPULSE_SNAP_EVERY"] ?? "") ?? 0.5)
        }
        app.run()
    }

    /// Screenshots the gallery window off the main thread (Core Animation keeps running meanwhile), then quits.
    private static func snap(window: Int, to dir: String, count: Int, every: Double) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Thread.detachNewThread {
            let start = Date().addingTimeInterval(1)   // warm-up: first layout and the styles settled into their loops
            for i in 0..<max(count, 0) {
                let wait = start.addingTimeInterval(Double(i) * every).timeIntervalSinceNow
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                let path = (dir as NSString).appendingPathComponent(String(format: "frame-%03d.png", i))
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", String(window), path]
                do {
                    try p.run()
                    p.waitUntilExit()
                    print(p.terminationStatus == 0 ? "snap \(path)" : "snap failed (\(p.terminationStatus)) \(path)")
                } catch {
                    print("snap failed: \(error.localizedDescription)")
                }
                fflush(stdout)
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func snapshot(dark: Bool) -> NSBitmapImageRep {
        let menuW: CGFloat = 330, margin: CGFloat = 28, barH: CGFloat = 30
        var items: [NSView] = [MenuTextView("CLAUDE CODE SESSIONS", font: .systemFont(ofSize: 11, weight: .semibold),
                                            kern: 0.9, width: menuW, height: 28)]
        for s in samples {
            let row = SessionRowView(frame: NSRect(x: 0, y: 0, width: menuW, height: SessionRowView.height))
            row.show(state: s.state, detail: s.detail, title: s.title, when: s.when, frame: TabStyle.braille.glyph(tick: 2, elapsed: 0),
                     isNew: s.state == "done")
            items.append(row)
        }
        items.append(Separator(frame: NSRect(x: 0, y: 0, width: menuW, height: 11)))
        items.append(MenuTextView("Click a session to jump to its Ghostty tab", font: .systemFont(ofSize: 12),
                                  width: menuW, height: 28))

        let menuH = items.reduce(0) { $0 + $1.frame.height } + 12
        let size = NSSize(width: menuW + margin * 2 + 60, height: barH + 6 + menuH + margin)
        let menuRect = NSRect(x: size.width - margin - menuW, y: margin, width: menuW, height: menuH)
        let canvas = Canvas(frame: NSRect(origin: .zero, size: size), barH: barH, menu: menuRect, dark: dark)
        canvas.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let pill = PillView(frame: .zero)
        pill.set(working: 2, waiting: 1, finished: 1)
        pill.frame = NSRect(x: menuRect.maxX - pill.width - 8, y: size.height - barH, width: pill.width, height: barH)
        canvas.addSubview(pill)
        var y = menuRect.maxY - 6
        for v in items {
            y -= v.frame.height
            v.frame.origin = NSPoint(x: menuRect.minX, y: y)
            canvas.addSubview(v)
        }
        pill.layout()

        let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        if let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext {
            let scale = CGFloat(rep.pixelsWide) / size.width
            ctx.scaleBy(x: scale, y: scale)
            pill.renderStar(in: ctx)
        }
        return rep
    }

    /// Wallpaper, menu bar strip and menu panel behind the real views.
    private final class Canvas: NSView {
        private let barH: CGFloat, menuRect: NSRect, dark: Bool

        init(frame: NSRect, barH: CGFloat, menu: NSRect, dark: Bool) {
            self.barH = barH
            self.menuRect = menu
            self.dark = dark
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { nil }

        override func draw(_ dirtyRect: NSRect) {
            NSGradient(starting: Palette.rgb(0x7b5ea7), ending: Palette.rgb(0x2f3e73))?.draw(in: bounds, angle: -35)
            let bar = NSRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
            (dark ? Palette.rgb(0x282632, alpha: 0.92) : Palette.rgb(0xf6f5f9, alpha: 0.92)).setFill()
            bar.fill()
            Text.draw("Ghostty      Shell      Edit      View", in: NSRect(x: 18, y: bar.minY + 6, width: 280, height: 18),
                      font: .systemFont(ofSize: 13, weight: .medium), color: .labelColor)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            shadow.set()
            (dark ? Palette.rgb(0x2c2a37) : NSColor.white).setFill()
            NSBezierPath(roundedRect: menuRect, xRadius: 10, yRadius: 10).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private final class Separator: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.separatorColor.setFill()
            NSRect(x: 14, y: floor(bounds.midY), width: bounds.width - 28, height: 1).fill()
        }
    }
}

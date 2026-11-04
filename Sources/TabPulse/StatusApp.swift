import Cocoa

final class StatusApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    private let menuWidth: CGFloat = 330

    private let ghostty = Ghostty()
    private lazy var tabs = TabSync(ghostty: ghostty)
    private let notifier = Notifier()
    private let awake = Awake()
    private let hotkey = Hotkey()
    private var reminder = WaitReminder()
    private var cycle = JumpCycle()
    private var item: NSStatusItem!
    private let pill = PillView(frame: .zero)
    private var sessions: [Session] = []
    private var previous: [String: Session]?   // sessions at the last reload, to spot turns that just ended
    private var unseen: Set<String> = []       // finished while you were looking somewhere else
    private var pending: [String: (armed: Date, updated: Date, turn: Date)] = [:]   // finished, banner not out yet
    private var frame = 0
    private var lastReload = Date.distantPast
    private var ghosttyWasRunning = false
    private var rowViews: [String: SessionRowView] = [:]
    private var menuOpen = false
    private var ticking = false
    private var pendingJump: String?
    private var pendingShortcut = false
    private var timer: Timer?
    private var fast = false
    private var previewUntil = Date.distantPast
    private var sigSource: DispatchSourceSignal?

    /// Done writes that follow Esc or a rejected prompt: you stopped it yourself, so no banner.
    private static let stoppedByYou: Set<String> = ["Notification", "PostToolUseFailure", "TabPulsePeek"]

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: pill.width)
        if let button = item.button {
            pill.frame = button.bounds
            pill.autoresizingMask = [.width, .height]
            button.addSubview(pill)
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        pill.style = Prefs.barStyle
        pill.speedsUp = Prefs.speedsUp
        notifier.onClick = { [weak self] tty in self?.jump(to: tty) }
        notifier.start()
        awake.busy = { [weak self] in self?.ticking ?? false }
        awake.releaseLeftovers()
        hotkey.onPress = { [weak self] in self?.jumpToNeedy() }
        if Prefs.jumpShortcut { hotkey.register() }
        tabs.releaseLeftovers()
        setPace(fast: true)
        installSignalHandler()
        tick()
    }

    func applicationWillTerminate(_ note: Notification) {
        awake.releaseAll()
        tabs.releaseAll()
    }

    // MARK: - Loop

    /// 0.12 s while anything animates; once a second otherwise, so a menu bar app with nothing working
    /// isn't waking up 8 times a second. A waiting tab's ● and the pill's dots are static.
    private func setPace(fast: Bool) {
        guard fast != self.fast || timer == nil else { return }
        self.fast = fast
        timer?.invalidate()
        let t = Timer(timeInterval: fast ? 0.12 : 1, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = fast ? 0.02 : 0.25
        RunLoop.main.add(t, forMode: .common)   // keep animating while the menu is open
        timer = t
    }

    private func tick() {
        // AppleScript calls spin the run loop, which can fire the timer again mid-tick.
        guard !ticking else { return }
        ticking = true
        defer {
            ticking = false
            if let tty = pendingJump { pendingJump = nil; jump(to: tty) }
            if pendingShortcut { pendingShortcut = false; jumpToNeedy() }
        }
        frame &+= 1
        var reloaded = false
        if !fast || Date().timeIntervalSince(lastReload) >= 1 {
            sessions = SessionStore.load()
            lastReload = Date()
            reloaded = true
        }
        let running = ghostty.isRunning
        if ghosttyWasRunning && !running { tabs.reset() }
        ghosttyWasRunning = running
        if running {
            ghostty.checkAccess()
            if ghostty.access == .ok {
                // By value, not inout: an access to `sessions` held open across AppleScript traps if
                // anything run from the nested run loop reads it.
                for id in tabs.sync(sessions, frame: frame, style: Prefs.tabStyle) {
                    if let i = sessions.firstIndex(where: { $0.id == id }) { sessions[i].state = "done" }
                    previous?[id]?.state = "done"   // stopped with Esc in that tab: you were there, so it isn't news
                }
            }
        }
        if reloaded {
            noticeWaiting()   // before noticeFinished, which moves `previous` on
            noticeFinished()
            updateAwake()
        }
        renderMenuBar()
        if menuOpen { for s in sessions { if let row = rowViews[s.id] { fill(row, with: s) } } }
        setPace(fast: menuOpen || Date() < previewUntil || sessions.contains { $0.state == "working" })
    }

    /// A session that finishes gets a banner and the green dot, unless its tab is the one you are looking at.
    /// They wait ten seconds, because a blocking Stop hook (/goal) can send Claude straight back to work.
    private func noticeFinished() {
        let now = Date()
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        lazy var focused = ghostty.access == .ok ? ghostty.focusedTTY() : nil   // an AppleScript call, so only when needed
        if let before = previous {
            for s in sessions where s.state == "done" && !Self.stoppedByYou.contains(s.event) {
                // Watched it finish: switching tabs before the banner is due doesn't make it news.
                guard let b = before[s.id], b.state == "working" || b.state == "waiting", s.tty != focused else { continue }
                pending[s.id] = (now, s.updated, b.turn)
            }
        }
        for (id, p) in pending {
            guard let s = byID[id], s.state == "done" else { pending[id] = nil; continue }
            // Written again while done (a blocked Stop, then a reply with no tools): that is the real end.
            if s.updated != p.updated { pending[id] = (now, s.updated, p.turn); continue }
            guard now.timeIntervalSince(p.armed) >= 10 else { continue }
            pending[id] = nil
            guard s.tty != focused else { continue }
            unseen.insert(id)
            let took = clock(p.turn, until: s.updated)
            if s.detail.hasPrefix("stopped: ") {   // StopFailure: an API error such as a rate limit ended the turn
                notify("Stopped: \(tabs.title(for: s))",
                       "Claude stopped in \(s.name) after \(took) (\(s.detail.dropFirst(9)))", tty: s.tty, sound: .finished)
            } else {
                notify("Finished: \(tabs.title(for: s))", "Claude is done in \(s.name) after \(took)", tty: s.tty, sound: .finished)
            }
        }
        // Seen once you look at its tab, or once it starts working again.
        if !unseen.isEmpty {
            let f = focused
            unseen = unseen.filter { id in byID[id].map { $0.state == "done" && $0.tty != f } ?? false }
        }
        previous = byID
    }

    /// A sound when a session starts waiting on you, and one reminder once it has waited five minutes. Neither for
    /// the tab you are looking at.
    private func noticeWaiting() {
        lazy var focused = ghostty.access == .ok ? ghostty.focusedTTY() : nil   // an AppleScript call, so only when needed
        if Prefs.sounds, let before = previous,
           Attention.startedWaiting(sessions, before: before).contains(where: { $0.tty != focused }) {
            Sound.needsYou.play()
        }
        guard Prefs.waitReminder else { return }
        for s in reminder.due(sessions, now: Date(), focused: { focused }) {
            let m = max(0, Int(Date().timeIntervalSince(s.since))) / 60
            notify("Still needs you: \(tabs.title(for: s))",
                   "Claude has been waiting in \(s.name) for \(m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min")",
                   tty: s.tty, sound: .needsYou)
        }
    }

    /// With Play sounds on, TabPulse's own sound stands in for the banner's.
    private func notify(_ title: String, _ body: String, tty: String, sound: Sound) {
        if Prefs.sounds { sound.play() }
        notifier.post(title: title, body: body, tty: tty, sound: !Prefs.sounds)
    }

    private func renderMenuBar() {
        let working = sessions.filter { $0.state == "working" }.count
        let waiting = sessions.filter { $0.state == "waiting" }.count
        pill.set(working: working, waiting: waiting, finished: unseen.count)
        if item.length != pill.width { item.length = pill.width }
        item.button?.setAccessibilityLabel("TabPulse: \(working) working, \(waiting) need you, \(unseen.count) finished")
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        rowViews = [:]
        let tabsReady = ghostty.isRunning && ghostty.access == .ok
        let ghosttyTTYs = tabsReady ? tabs.refreshTitles() : []

        menu.addItem(viewItem(MenuTextView("CLAUDE CODE SESSIONS", font: .systemFont(ofSize: 11, weight: .semibold),
                                           kern: 0.9, width: menuWidth, height: 28)))
        if sessions.isEmpty && Self.hooksInstalled() {
            menu.addItem(viewItem(MenuTextView("No sessions yet. Start claude in a terminal.", font: .systemFont(ofSize: 13),
                                               width: menuWidth, height: 30)))
        } else if sessions.isEmpty {
            menu.addItem(viewItem(MenuTextView("Claude Code hooks aren't installed.", font: .systemFont(ofSize: 13),
                                               width: menuWidth, height: 24)))
            menu.addItem(viewItem(MenuTextView("Run the installer from the README.", font: .systemFont(ofSize: 13),
                                               width: menuWidth, height: 22)))
        }
        for s in sessions {
            let row = SessionRowView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: SessionRowView.height))
            fill(row, with: s)
            rowViews[s.id] = row
            let mi = viewItem(row, enabled: ghosttyTTYs.contains(s.tty))
            mi.target = self
            mi.action = #selector(jump(_:))
            mi.representedObject = s.tty
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        switch ghostty.access {
        case .denied:
            let fix = NSMenuItem(title: "Allow TabPulse to control Ghostty…", action: #selector(openAutomationSettings), keyEquivalent: "")
            fix.target = self
            menu.addItem(fix)
        case .unsupported:
            menu.addItem(footer("Tab spinners need Ghostty 1.4 or newer"))
        default:
            menu.addItem(footer(tabsReady ? "Click a session to jump to its Ghostty tab" : "Tab spinners work in Ghostty 1.4+"))
        }
        if awake.stuck {
            menu.addItem(footer("Lid sleep is still off: sudo pmset -a disablesleep 0"))
        } else if awake.holding {
            menu.addItem(footer(awake.lidHeld ? "Keeping your Mac awake, even with the lid closed" : "Keeping your Mac awake while Claude works"))
        }
        if Prefs.jumpShortcut {
            // The tab is picked now: closing the menu clears `unseen` before the click arrives.
            let target = cycle.target(sessions.filter { ghosttyTTYs.contains($0.tty) }, unseen: unseen, now: Date())
            let mi = NSMenuItem(title: "Jump to the tab that needs you", action: target == nil ? nil : #selector(jump(_:)),
                                keyEquivalent: "j")
            mi.keyEquivalentModifierMask = [.control, .option, .command]
            mi.target = self
            mi.representedObject = target?.tty
            menu.addItem(mi)
        }
        let style = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        style.submenu = styleMenu()
        menu.addItem(style)
        let options = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        options.submenu = optionsMenu()
        menu.addItem(options)

        // Kept out of the way like many menu bar apps: hold Option while opening the menu.
        if NSEvent.modifierFlags.contains(.option) {
            menu.addItem(.separator())
            let about = NSMenuItem(title: "TabPulse \(Self.version)", action: nil, keyEquivalent: "")
            about.isEnabled = false
            menu.addItem(about)
            let quit = NSMenuItem(title: "Quit TabPulse", action: #selector(quit), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        setPace(fast: true)
    }

    // Opening the menu counts as having seen what finished.
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        rowViews = [:]
        unseen.removeAll()
        pending.removeAll()
    }

    /// The installer's hooks or the enabled plugin, in the settings Claude Code reads.
    private static func hooksInstalled() -> Bool {
        // Only the hook creates this, whatever config dir or plugin scope it runs from. The login item
        // starts the app without the shell's CLAUDE_CONFIG_DIR, so the settings check alone can miss it.
        if FileManager.default.fileExists(atPath: SessionStore.dir) { return true }
        let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? ""
        let dirs = [env.isEmpty ? nil : (env as NSString).expandingTildeInPath,
                    (NSHomeDirectory() as NSString).appendingPathComponent(".claude")].compactMap { $0 }
        return dirs.contains { dir in
            guard let data = FileManager.default.contents(atPath: (dir as NSString).appendingPathComponent("settings.json"))
            else { return false }
            if String(decoding: data, as: UTF8.self).contains("tabpulse-hook.sh") { return true }
            let plugins = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["enabledPlugins"] as? [String: Any]
            return plugins?.contains { $0.key.hasPrefix("tabpulse@") && ($0.value as? Bool) == true } ?? false
        }
    }

    /// Each picker gets its own submenu: forty styles in one menu would be taller than a laptop screen.
    private func styleMenu() -> NSMenu {
        let tab = NSMenu()
        for s in TabStyle.allCases {
            if s == TabStyle.allCases.first(where: { $0.section == s.section }) { header(s.section, in: tab) }
            let mi = choice(s.name, s.rawValue, on: s == Prefs.tabStyle, #selector(pickTabStyle(_:)))
            mi.attributedTitle = columns(s.sample, s.name)
            tab.addItem(mi)
        }
        let bar = NSMenu()
        for s in BarStyle.allCases {
            if s == BarStyle.allCases.first(where: { $0.section == s.section }) { header(s.section, in: bar) }
            bar.addItem(choice(s.name, s.rawValue, on: s == Prefs.barStyle, #selector(pickBarStyle(_:))))
        }
        let m = NSMenu()
        for (title, sub) in [("Tab spinner", tab), ("Menu bar", bar)] {
            let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            mi.submenu = sub
            m.addItem(mi)
        }
        m.addItem(.separator())
        m.addItem(choice("Speed up when busy", "", on: Prefs.speedsUp, #selector(toggleSpeedsUp)))
        return m
    }

    private func header(_ title: String, in menu: NSMenu) {
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        menu.addItem(.sectionHeader(title: title))
    }

    private func choice(_ title: String, _ value: String, on: Bool, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.representedObject = value
        mi.state = on ? .on : .off
        return mi
    }

    /// Sample and name in two columns, so a wide emoji sample doesn't push its name out of line. The font
    /// is explicit (an attributed title falls back to Helvetica 12); no colour, so highlighted rows invert.
    private func columns(_ sample: String, _ name: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.tabStops = [NSTextTab(textAlignment: .left, location: 34)]   // the widest samples, Typing and Sine, are 26.7 pt
        return NSAttributedString(string: "\(sample)\t\(name)", attributes: [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: p])
    }

    @objc private func pickTabStyle(_ sender: NSMenuItem) {
        if let s = TabStyle(rawValue: sender.representedObject as? String ?? "") { Prefs.tabStyle = s }
    }

    @objc private func pickBarStyle(_ sender: NSMenuItem) {
        guard let s = BarStyle(rawValue: sender.representedObject as? String ?? "") else { return }
        Prefs.barStyle = s
        pill.style = s
        // Shows the pick even when nothing is working. The pill notices the preview ending on a tick, so stay fast.
        pill.preview(for: 3)
        previewUntil = Date().addingTimeInterval(3)
    }

    @objc private func toggleSpeedsUp() {
        Prefs.speedsUp.toggle()
        pill.speedsUp = Prefs.speedsUp
    }

    private func optionsMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(choice("Keep Mac awake while Claude works", "", on: Prefs.keepAwake, #selector(toggleKeepAwake)))
        m.addItem(choice("Keep awake with lid closed…", "", on: Prefs.lidAwake, #selector(toggleLidAwake)))
        m.addItem(.separator())
        m.addItem(choice("Remind me if a session waits 5 min", "", on: Prefs.waitReminder, #selector(toggleWaitReminder)))
        m.addItem(choice("Play sounds", "", on: Prefs.sounds, #selector(toggleSounds)))
        // In the title, not as a key equivalent, so the shortcut never toggles this item.
        m.addItem(choice("Jump shortcut ⌃⌥⌘J", "", on: Prefs.jumpShortcut, #selector(toggleJumpShortcut)))
        return m
    }

    @objc private func toggleWaitReminder() { Prefs.waitReminder.toggle() }

    @objc private func toggleSounds() {
        Prefs.sounds.toggle()
        if Prefs.sounds { Sound.needsYou.play() }   // so you hear what you turned on
    }

    @objc private func toggleJumpShortcut() {
        Prefs.jumpShortcut.toggle()
        Prefs.jumpShortcut ? hotkey.register() : hotkey.unregister()
    }

    private func updateAwake() { awake.update(working: sessions.filter { $0.state == "working" }.count) }

    @objc private func toggleKeepAwake() {
        Prefs.keepAwake.toggle()
        updateAwake()
    }

    /// Turning it off releases right away; turning it on may ask for your password first.
    @objc private func toggleLidAwake() {
        guard !Prefs.lidAwake else {
            Prefs.lidAwake = false
            updateAwake()
            return
        }
        awake.setUpLidMode { [weak self] ready in
            guard ready else { return }
            Prefs.lidAwake = true
            self?.updateAwake()
        }
    }

    private func viewItem(_ view: NSView, enabled: Bool = false) -> NSMenuItem {
        let mi = NSMenuItem()
        mi.view = view
        mi.isEnabled = enabled
        return mi
    }

    private func footer(_ text: String) -> NSMenuItem {
        viewItem(MenuTextView(text, font: .systemFont(ofSize: 12), width: menuWidth, height: 28))
    }

    private func fill(_ row: SessionRowView, with s: Session) {
        row.show(state: s.state, detail: s.detail, title: tabs.title(for: s),
                 when: s.state == "done" ? ago(s.since) : clock(s.state == "working" ? s.turn : s.since),
                 frame: Prefs.tabStyle.glyph(tick: frame, elapsed: Date().timeIntervalSince(s.turn)),
                 isNew: unseen.contains(s.id))
    }

    private func clock(_ d: Date, until end: Date = Date()) -> String {
        let s = max(0, Int(end.timeIntervalSince(d)))
        return s < 3600 ? String(format: "%d:%02d", s / 60, s % 60) : "\(s / 3600)h\((s % 3600) / 60)m"
    }

    private func ago(_ d: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(d)))
        return s < 60 ? "just now" : s < 3600 ? "\(s / 60)m ago" : s < 86400 ? "\(s / 3600)h ago" : "\(s / 86400)d ago"
    }

    @objc private func jump(_ sender: NSMenuItem) {
        guard let tty = sender.representedObject as? String else { return }
        jump(to: tty)
    }

    /// False when there was no Ghostty tab to go to.
    @discardableResult
    private func jump(to tty: String) -> Bool {
        guard !tty.isEmpty else { return false }
        // A click can arrive while a tick waits on AppleScript; it runs once that tick is done.
        if ticking { pendingJump = tty; return true }
        unseen = unseen.filter { id in sessions.first { $0.id == id }?.tty != tty }
        // Never launch Ghostty, or ask for Automation access, just to look for a tab.
        guard ghostty.isRunning, ghostty.access == .ok else { return false }
        return ghostty.focus(tty)
    }

    /// The ⌃⌥⌘J shortcut. Only sessions in Ghostty tabs count, so a quick second press skips ones it can't reach.
    private func jumpToNeedy() {
        // Mid-tick, `sessions` and `unseen` may be half updated; the tick runs this when it is done.
        if ticking { pendingShortcut = true; return }
        guard ghostty.isRunning, ghostty.access == .ok else { NSSound.beep(); return }
        let inGhostty = tabs.refreshTitles()
        guard let s = cycle.next(sessions.filter { inGhostty.contains($0.tty) }, unseen: unseen, now: Date()),
              jump(to: s.tty) else { NSSound.beep(); return }
    }

    @objc private func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler { NSApp.terminate(nil) }   // pkill / logout: still hand tab titles back
        src.resume()
        sigSource = src
    }
}

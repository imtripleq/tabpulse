import Foundation

/// Puts a spinner (working) or a dot (needs you) in front of each active session's Ghostty tab title,
/// and hands the title back to Claude when the turn ends.
final class TabSync {
    private static let claudeGlyphs: Set<String> = ["✳", "◐", "◑"]

    private let ghostty: Ghostty
    private let overridesFile = (SessionStore.root as NSString).appendingPathComponent("overrides")
    private var overridden: Set<String> = []        // ttys whose tab title we currently own
    private var savedOverrides: Set<String> = []
    private var baseTitles: [String: String] = [:]  // tty -> Claude's own title under our override
    private var tabTitles: [String: String] = [:]   // tty -> last title seen, for idle sessions
    private var lastPeek: [String: Date] = [:]
    private var lastAnyPeek = Date.distantPast
    private var lastSent: [String: String] = [:]    // tty -> the title we set last
    private var shown: [String: String] = [:]       // tty -> the title Ghostty took, so it isn't resent every tick
    private var foreign: Set<String> = []           // ttys with no titled Ghostty terminal (tmux, other terminals)

    init(ghostty: Ghostty) { self.ghostty = ghostty }

    /// A crash or force quit can leave spinners on tabs; the overrides file says which ones.
    func releaseLeftovers() {
        guard let text = try? String(contentsOfFile: overridesFile, encoding: .utf8) else { return }
        overridden = Set(text.split(separator: "\n").map(String.init))
        releaseAll()
    }

    func releaseAll() {
        guard !overridden.isEmpty, ghostty.isRunning else { return }
        ghostty.setTitles(Dictionary(uniqueKeysWithValues: overridden.map { ($0, "") }))
        overridden.removeAll()
        shown.removeAll()
        save()
    }

    /// Ghostty quit, so its terminals and our overrides are gone with it.
    func reset() {
        overridden.removeAll()
        baseTitles.removeAll()
        lastPeek.removeAll()
        shown.removeAll()
        foreign.removeAll()
        save()
    }

    /// Returns the ids of sessions it found stopped with Esc and marked done; the caller updates its copy.
    @discardableResult
    func sync(_ sessions: [Session], frame: Int, style: TabStyle) -> [String] {
        let active = sessions.filter { ($0.state == "working" || $0.state == "waiting") && !$0.tty.isEmpty }
        let activeTTYs = Set(active.map(\.tty))
        var titles: [String: String] = [:]
        var interrupted: [String] = []

        for tty in overridden.subtracting(activeTTYs) {   // turn over: hand the title back to Claude
            titles[tty] = ""
            if let base = baseTitles.removeValue(forKey: tty) { tabTitles[tty] = base }
        }
        overridden.formIntersection(activeTTYs)
        foreign.formIntersection(activeTTYs)

        // A tab we don't own yet has no override to lift, so one round trip reads every new tab at once
        // (launch, wake, Automation just allowed). Its ✳ is checked at its first timed peek.
        let fresh = active.filter { !overridden.contains($0.tty) && !foreign.contains($0.tty) }
        if !fresh.isEmpty, let all = ghostty.allTitles() {
            for s in fresh {
                lastPeek[s.tty] = Date()
                if let t = all[s.tty], !t.isEmpty { baseTitles[s.tty] = Self.strip(t) } else { foreign.insert(s.tty) }
            }
        }
        // Each peek blocks for a moment, so they are spaced out instead of all landing in one tick.
        let gap = min(1, 10 / Double(max(active.count, 1)))
        for s in active {
            let peeked = Date().timeIntervalSince(lastPeek[s.tty] ?? .distantPast) > 10
                && Date().timeIntervalSince(lastAnyPeek) >= gap
            if peeked && !peek(s) {
                SessionStore.markDone(s)
                interrupted.append(s.id)
                continue
            }
            guard let base = baseTitles[s.tty] else { continue }
            let mark = s.state == "waiting" ? "●" : style.glyph(tick: frame, elapsed: Date().timeIntervalSince(s.turn))
            let title = "\(mark) \(base)"
            // A peek cleared the override, so that tab needs its title again even when it hasn't changed.
            if peeked || title != shown[s.tty] { titles[s.tty] = title }
            lastSent[s.tty] = title
            overridden.insert(s.tty)
        }
        for tty in lastSent.keys where !overridden.contains(tty) { lastSent[tty] = nil }
        let sent = ghostty.setTitles(titles)
        for (tty, title) in titles { shown[tty] = sent && !title.isEmpty ? title : nil }
        save()
        return interrupted
    }

    /// Reads Claude's real title from under our override: keeps the title fresh and catches turns that
    /// ended without a Stop hook (Esc interrupt), which Claude marks with its idle ✳. False = turn is over.
    private func peek(_ s: Session) -> Bool {
        lastPeek[s.tty] = Date()
        lastAnyPeek = Date()
        guard let read = ghostty.underlyingTitle(s.tty) else { return true }
        // Nothing to put a spinner on, so look again only when a peek is due rather than every tick.
        guard read.found, !read.title.isEmpty else { foreign.insert(s.tty); return true }
        foreign.remove(s.tty)
        let title = read.title
        // Our own override read back stale. Sparkle's ✳ frame would otherwise pass for Claude's idle ✳.
        if title == lastSent[s.tty] { return true }
        baseTitles[s.tty] = Self.strip(title)
        return !(title.first == "✳" && s.state == "working")
    }

    /// Also returns the ttys Ghostty has a terminal for.
    @discardableResult
    func refreshTitles() -> Set<String> {
        let all = ghostty.allTitles() ?? [:]
        for (tty, title) in all { tabTitles[tty] = Self.strip(title) }
        return Set(all.keys)
    }

    func title(for s: Session) -> String {
        let t = baseTitles[s.tty] ?? tabTitles[s.tty] ?? ""
        return t.isEmpty || t == "Claude Code" ? s.name : t
    }

    /// Drops the one status mark in front of a title: Claude's, or ours when Ghostty returns an override we
    /// just cleared. Only one, so a title that itself starts with 💡 or · keeps it.
    static func strip(_ title: String) -> String {
        let rest = title.drop { $0 == " " }
        let mark = String(rest.prefix { $0 != " " })
        let isMark = mark == "●" || claudeGlyphs.contains(mark) || TabStyle.allFrames.contains(mark)
            || !mark.isEmpty && mark.unicodeScalars.allSatisfy { (0x2800...0x28FF).contains($0.value) }
        return isMark ? String(rest.dropFirst(mark.count).drop { $0 == " " }) : String(rest)
    }

    private func save() {
        guard overridden != savedOverrides else { return }
        savedOverrides = overridden
        try? FileManager.default.createDirectory(atPath: SessionStore.root, withIntermediateDirectories: true)
        try? overridden.sorted().joined(separator: "\n").write(toFile: overridesFile, atomically: true, encoding: .utf8)
    }
}

import Cocoa

/// AppleScript bridge to Ghostty 1.4+, which lets another app set a per-terminal `name override`
/// and find terminals by tty.
final class Ghostty {
    enum Access { case unknown, ok, denied, unsupported }

    private(set) var access: Access = .unknown
    private var lastCheck = Date.distantPast
    private var lastLoggedError: Int?

    static let bundleID = "com.mitchellh.ghostty"

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    /// The tty of the tab you are looking at, or nil when Ghostty isn't the frontmost app.
    func focusedTTY() -> String? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.bundleID else { return nil }
        return execute("tell application \"Ghostty\" to get tty of focused terminal of selected tab of front window").value
    }

    /// Needs Ghostty 1.4's scripting dictionary and the user's Automation permission. The first call is
    /// what makes macOS ask "TabPulse wants to control Ghostty". Rechecked every 30 s until it works.
    func checkAccess() {
        guard access != .ok, Date().timeIntervalSince(lastCheck) > 30 else { return }
        lastCheck = Date()
        var err: NSDictionary?
        let probe = NSAppleScript(source: "tell application \"Ghostty\" to get name override of first terminal")
        if probe?.compileAndReturnError(&err) == false { access = .unsupported; return }
        switch execute("tell application \"Ghostty\" to count terminals").error {
        case nil: access = .ok
        case -1743, -1744: access = .denied   // not permitted / would need consent
        default: access = .unknown
        }
    }

    /// tty -> title; an empty title hands the tab back to its own title. False when the script failed.
    @discardableResult
    func setTitles(_ titles: [String: String]) -> Bool {
        guard !titles.isEmpty else { return true }
        let lines = titles.map { tty, title in
            "try\nset name override of (first terminal whose tty is \"\(esc(tty))\") to \"\(esc(title))\"\nend try"
        }
        return execute("tell application \"Ghostty\"\n\(lines.joined(separator: "\n"))\nend tell").error == nil
    }

    /// Clears our override and reads the title the program in that terminal set. nil when the call failed;
    /// `found` is false when Ghostty has no terminal on that tty (tmux, or another terminal app).
    func underlyingTitle(_ tty: String) -> (found: Bool, title: String)? {
        guard let out = execute("""
        tell application "Ghostty"
          try
            set t to first terminal whose tty is "\(esc(tty))"
          on error number n
            if n is -1719 or n is -1728 then return "0"
            error number n
          end try
          set name override of t to ""
          delay 0.15
          return "1" & (name of t)
        end tell
        """).value else { return nil }
        return out.hasPrefix("1") ? (true, String(out.dropFirst())) : (false, "")
    }

    /// Every terminal's current title in one round trip; nil when the call failed.
    func allTitles() -> [String: String]? {
        guard let out = execute("""
        tell application "Ghostty"
          set ttys to tty of every terminal
          set names to name of every terminal
        end tell
        set out to ""
        repeat with i from 1 to count of ttys
          try
            set out to out & (item i of ttys) & (character id 9) & (item i of names) & (character id 10)
          end try
        end repeat
        return out
        """).value else { return nil }
        var titles: [String: String] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if parts.count == 2 { titles[parts[0]] = parts[1] }
        }
        return titles
    }

    /// Brings Ghostty forward only when it has a terminal on that tty. False when it has none.
    @discardableResult
    func focus(_ tty: String) -> Bool {
        execute("""
        tell application "Ghostty"
          try
            focus (first terminal whose tty is "\(esc(tty))")
            activate
            return "1"
          end try
        end tell
        return ""
        """).value == "1"
    }

    @discardableResult
    private func execute(_ source: String) -> (value: String?, error: Int?) {
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        guard let err else { lastLoggedError = nil; return (result?.stringValue, nil) }
        let code = err[NSAppleScript.errorNumber] as? Int ?? 0
        if code != lastLoggedError {   // the loop runs 8 times a second; log each new error once
            NSLog("TabPulse AppleScript error \(code): \(err[NSAppleScript.errorMessage] ?? "")")
            lastLoggedError = code
        }
        return (nil, code)
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

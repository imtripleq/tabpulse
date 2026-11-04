import Cocoa
import IOKit.ps
import IOKit.pwr_mgt

/// Keeps the Mac awake while Claude works: an idle sleep assertion, and in lid-closed mode `pmset disablesleep`.
/// pmset needs root, so it goes through a one-line sudoers rule that TabPulse installs once, with your password.
/// sudo runs on a background queue, in order, so the menu bar never waits on it.
final class Awake {
    private static let rule = "/etc/sudoers.d/tabpulse"
    /// Exists while lid sleep may be off, so a crash or force quit can't leave it off for good.
    private static let marker = (SessionStore.root as NSString).appendingPathComponent("lid-awake")

    /// True while the app is mid-tick. An alert opened then would hold the tick, and the menu bar, until dismissed.
    var busy: () -> Bool = { false }
    private var assertion: IOPMAssertionID?
    private(set) var lidHeld = false
    /// sudo refused to turn lid sleep back on, so it is still off.
    private(set) var stuck = false
    private var settingUp = false
    private let queue = DispatchQueue(label: "dev.tabpulse.awake")
    private var lidOff = false   // on `queue` only: what pmset was last told
    private var foreign = false   // on `queue` only: lid sleep was already off before TabPulse, so it isn't ours to undo
    private var lastWorked = Date.distantPast
    private var working = 0

    var holding: Bool { assertion != nil || lidHeld }

    /// Called about once a second, and when an option changes. Only a change in what to hold calls sudo.
    func update(working: Int) {
        if stuck && !Self.sleepDisabled() {   // someone ran the pmset fix by hand
            stuck = false
            queue.async {
                guard !Self.sleepDisabled() else { return }
                self.lidOff = false
                try? FileManager.default.removeItem(atPath: Self.marker)
            }
        }
        self.working = working
        if working > 0 { lastWorked = Date() }
        var p = AwakePolicy(working: working, keepAwake: Prefs.keepAwake, lidAwake: Prefs.lidAwake)
        p.quiet = Date().timeIntervalSince(lastWorked)
        if p.lidAwake && p.busy {
            (p.onBattery, p.batteryPercent) = Self.power()
            p.thermal = ProcessInfo.processInfo.thermalState
        }
        if p.holdIdle != (assertion != nil) { p.holdIdle ? holdIdle() : releaseIdle() }
        if p.holdLid != lidHeld { p.holdLid ? holdLid() : releaseLid(p.lidRelease) }
    }

    func releaseLeftovers() {
        guard FileManager.default.fileExists(atPath: Self.marker) else { return }
        releaseLid(.turnedOff)
    }

    /// On quit. Waits for sudo, so lid sleep is back on before the process ends.
    func releaseAll() {
        releaseIdle()
        lidHeld = false
        queue.sync { _ = setLidOff(false) }
    }

    // MARK: - Idle sleep

    private func holdIdle() {
        guard assertion == nil else { return }
        var id = IOPMAssertionID(0)
        let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn), "Claude Code is working" as CFString, &id)
        if ok == kIOReturnSuccess { assertion = id }
    }

    private func releaseIdle() {
        guard let id = assertion else { return }
        IOPMAssertionRelease(id)
        assertion = nil
    }

    // MARK: - Lid sleep

    private func holdLid() {
        lidHeld = true
        queue.async {
            guard !self.setLidOff(true) else { return }
            DispatchQueue.main.async { self.ruleMissing() }
        }
    }

    private func releaseLid(_ why: LidRelease) {
        lidHeld = false
        if why == .cutoff { NSLog("TabPulse: lid sleep is back on early: low battery or the Mac is hot") }
        queue.async {
            let ours = !self.foreign
            let ok = self.setLidOff(false)
            DispatchQueue.main.async {
                self.stuck = !ok
                guard ok else {
                    if Prefs.lidAwake {   // not ruleMissing(), which releases again and would loop
                        Prefs.lidAwake = false
                        NSLog("TabPulse: sudo -n pmset failed, so lid sleep is still off and lid-closed mode is off. Run: sudo pmset -a disablesleep 0")
                    }
                    return
                }
                // Work started again while sudo ran.
                guard !self.lidHeld, why == .cutoff || self.working == 0 else { return }
                let lid = Self.clamshell()
                if ours && why.sleepsMac(lidClosed: lid.closed, clamshellCausesSleep: lid.causesSleep) { Self.sleepNow() }
            }
        }
    }

    /// sudo refused: the rule was removed, or a managed Mac reset it. Stays off until you set it up again.
    private func ruleMissing() {
        releaseLid(.turnedOff)   // nothing to do unless an earlier hold got through
        guard Prefs.lidAwake else { return }
        Prefs.lidAwake = false
        NSLog("TabPulse: sudo -n pmset failed, so lid-closed mode is off. Turn it on again in Options to set it up.")
    }

    /// On `queue` only. Skips sudo when pmset already has this setting; false when sudo refused.
    private func setLidOff(_ off: Bool) -> Bool {
        let fm = FileManager.default
        let disabled = Self.sleepDisabled()   // pmset may have been run by hand
        if off && disabled && !fm.fileExists(atPath: Self.marker) { foreign = true; return true }
        if !off && foreign { foreign = false; return true }
        // `lidOff` too, in case the registry hasn't caught up with our last pmset yet.
        if off ? disabled : (!disabled && !lidOff) {
            lidOff = off
            if !off { try? fm.removeItem(atPath: Self.marker) }
            return true
        }
        if off {   // before pmset, so a crash in between still leaves the marker
            try? fm.createDirectory(atPath: SessionStore.root, withIntermediateDirectories: true)
            fm.createFile(atPath: Self.marker, contents: nil)
        }
        let status = Self.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", off ? "1" : "0"])
        let ok = status == 0 || (!off && !Self.sleepDisabled())   // refused, but lid sleep is back on anyway
        if ok { lidOff = off }
        if !lidOff { try? fm.removeItem(atPath: Self.marker) }
        return ok
    }

    /// On battery, and the internal battery's charge in percent (nil without one).
    private static func power() -> (onBattery: Bool, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (false, nil) }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onBattery = source == kIOPMBatteryPowerKey
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return (onBattery, now * 100 / max)
        }
        return (onBattery, nil)
    }

    /// Both are false on a Mac with no lid.
    private static func clamshell() -> (closed: Bool, causesSleep: Bool) {
        (rootFlag(kAppleClamshellStateKey), rootFlag(kAppleClamshellCausesSleepKey))
    }

    /// What `pmset disablesleep` last set, whoever ran it. Readable without root.
    private static func sleepDisabled() -> Bool { rootFlag("SleepDisabled") }

    private static func rootFlag(_ key: String) -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool ?? false
    }

    /// IOPMSleepSystem accepts the console user as well as root, so this needs no sudo.
    private static func sleepNow() {
        let port = IOPMFindPowerManagement(kIOMainPortDefault)
        guard port != 0 else { return }
        if IOPMSleepSystem(port) != kIOReturnSuccess { NSLog("TabPulse: couldn't put the Mac to sleep") }
        IOServiceClose(port)
    }

    /// Waits on a semaphore rather than waitUntilExit, which spins the run loop and could re-enter tick().
    private static func run(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return -1 }
        guard done.wait(timeout: .now() + timeout) == .success else { p.terminate(); return -1 }
        return p.terminationStatus
    }

    // MARK: - Setting up lid-closed mode

    /// Asks first and installs the sudoers rule, unless a working one is already there. `done` gets whether it's ready.
    func setUpLidMode(_ done: @escaping (Bool) -> Void) {
        guard !settingUp else { return }
        settingUp = true
        let finish = { (ok: Bool) in self.settingUp = false; done(ok) }
        DispatchQueue.global(qos: .userInitiated).async {
            if Self.ruleWorks() { DispatchQueue.main.async { finish(true) }; return }
            self.whenIdle {
                guard self.confirm() else { finish(false); return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Self.installRule()
                    self.whenIdle {
                        if result == .failed { self.showFailure() }
                        finish(result == .installed)
                    }
                }
            }
        }
    }

    private func whenIdle(_ work: @escaping () -> Void) {
        DispatchQueue.main.async {
            if self.busy() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.whenIdle(work) } } else { work() }
        }
    }

    private func confirm() -> Bool {
        let a = NSAlert()
        a.messageText = "Keep your Mac awake with the lid closed?"
        a.informativeText = """
            macOS puts a MacBook to sleep when you close the lid. TabPulse can turn that off only while Claude is \
            working, and turns it back on when Claude finishes. It also turns it back on if the battery drops to 20% \
            or the Mac gets hot.

            This needs your admin password once. Don't put a working Mac in a bag.
            """
        a.addButton(withTitle: "Continue")
        a.addButton(withTitle: "Cancel")
        NSApp.activate()
        return a.runModal() == .alertFirstButtonReturn
    }

    private func showFailure() {
        let a = NSAlert()
        a.messageText = "Couldn't set up lid-closed mode"
        a.informativeText = "macOS didn't allow the change. Macs managed by an employer often block it. "
            + "TabPulse still keeps your Mac awake while the lid is open."
        NSApp.activate()
        a.runModal()
    }

    /// The rule is readable only by root, so ask sudo whether it would run both commands without a password.
    private static func ruleWorks() -> Bool {
        FileManager.default.fileExists(atPath: rule)
            && ["1", "0"].allSatisfy { run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", $0]) == 0 }
    }

    private enum Setup { case installed, cancelled, failed }

    /// Runs `installScript` as root behind the macOS password prompt. The user name goes in as an argument, quoted
    /// by AppleScript, never pasted into the script.
    private static func installRule() -> Setup {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z_][A-Za-z0-9_.-]{0,63}$", options: .regularExpression) != nil else {
            NSLog("TabPulse: unexpected user name, so no sudoers rule")
            return .failed
        }
        let p = Process()
        let errors = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "on run argv",
                       "-e", "set cmd to \"/bin/sh -c \" & quoted form of (item 1 of argv) & \" tabpulse \" & quoted form of (item 2 of argv)",
                       "-e", "do shell script cmd with prompt (item 3 of argv) with administrator privileges",
                       "-e", "end run",
                       installScript, user, "TabPulse needs your password once, so it can turn lid sleep off while Claude works."]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errors
        do { try p.run() } catch { return .failed }
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()   // off the main thread, so spinning this thread's run loop is harmless
        if p.terminationStatus == 0 { return ruleWorks() ? .installed : .failed }
        if message.contains("(-128)") { return .cancelled }   // the password prompt's Cancel
        NSLog("TabPulse: setting up lid-closed mode failed: \(message)")
        return .failed
    }

    /// Runs as root with the checked user name as $1. visudo checks the rule before it goes in and the whole
    /// sudoers setup after, so a broken file never stays in place.
    private static let installScript = """
        set -eu
        tmp=$(/usr/bin/mktemp)
        trap '/bin/rm -f "$tmp"' EXIT
        printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0\\n' "$1" >"$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null
        [ -d /etc/sudoers.d ] || /bin/mkdir -m 0755 /etc/sudoers.d
        /usr/bin/install -m 0440 -o root -g wheel "$tmp" /etc/sudoers.d/tabpulse
        /usr/sbin/visudo -c >/dev/null || { /bin/rm -f /etc/sudoers.d/tabpulse; exit 1; }
        """
}

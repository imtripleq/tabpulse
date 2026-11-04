import Foundation

/// Plain checks of TabPulse's pure decision logic, built and run by scripts/test-logic.sh. No XCTest needed.
@main
enum LogicTests {
    static var failed = 0

    static func check(_ ok: Bool, _ name: String) {
        print(ok ? "ok   \(name)" : "FAIL \(name)")
        if !ok { failed += 1 }
    }

    static func main() {
        awake()
        reminder()
        startedWaiting()
        jump()
        // Each group of checks gets its own function, called from here.
        exit(failed == 0 ? 0 : 1)
    }

    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// `since` and `turn` in seconds after t0.
    static func session(_ id: String, _ state: String, since: TimeInterval = 0, turn: TimeInterval = 0,
                        tty: String? = nil) -> Session {
        Session(id: id, state: state, since: t0.addingTimeInterval(since), turn: t0.addingTimeInterval(turn), updated: t0,
                cwd: "/code/\(id)", tty: tty ?? "/dev/tty-\(id)", pid: 0, detail: "", event: "")
    }

    static func ids(_ sessions: [Session]) -> [String] { sessions.map(\.id) }

    static func reminder() {
        var r = WaitReminder()
        var asked = 0
        func due(_ sessions: [Session], at seconds: TimeInterval, focused: String? = nil) -> [String] {
            ids(r.due(sessions, now: t0.addingTimeInterval(seconds), focused: { asked += 1; return focused }))
        }
        let a = session("a", "waiting")

        check(due([a], at: 299) == [], "waiting 4:59: no reminder yet")
        check(asked == 0, "nothing due: the focused tab isn't looked up")
        check(due([a], at: 300) == ["a"], "waiting 5:00: reminder")
        check(due([a], at: 301) == [], "same wait a second later: no second reminder")
        check(due([a], at: 3600) == [], "same wait an hour later: still only the one")

        _ = due([session("a", "working", since: 3700)], at: 3700)
        let again = session("a", "waiting", since: 3800)
        check(due([again], at: 3900) == [], "new wait, 100 s in: not yet")
        check(due([again], at: 4100) == ["a"], "new wait, 5 min in: reminds again")

        var q = WaitReminder()
        let b = session("b", "waiting")
        check(ids(q.due([b], now: t0.addingTimeInterval(400), focused: { "/dev/tty-b" })) == [],
              "you're looking at its tab: no reminder")
        check(ids(q.due([b], now: t0.addingTimeInterval(500), focused: { "/dev/tty-other" })) == ["b"],
              "you looked away while it still waits: reminder")

        var w = WaitReminder()
        let both = [session("c", "waiting"), session("d", "waiting", since: 10)]
        check(Set(ids(w.due(both, now: t0.addingTimeInterval(600), focused: { nil }))) == ["c", "d"],
              "two long waits: one reminder each")
        let others = [session("e", "working", turn: -900), session("f", "done", since: -900)]
        check(ids(w.due(others, now: t0.addingTimeInterval(900), focused: { nil })) == [], "working and done sessions: never")
    }

    static func startedWaiting() {
        let before = Dictionary(uniqueKeysWithValues: [session("a", "working"), session("b", "waiting"),
                                                       session("c", "waiting"), session("d", "done")].map { ($0.id, $0) })
        let now = [session("a", "waiting", since: 5), session("b", "waiting"), session("c", "waiting", since: 5),
                   session("d", "done"), session("e", "waiting", since: 5)]
        check(ids(Attention.startedWaiting(now, before: before)) == ["a", "c", "e"],
              "started waiting: from working, a new prompt, a new session; not a wait that carries on")
    }

    static func jump() {
        let ordered = SessionStore.ordered([
            session("done-old", "done", since: -600), session("work", "working", turn: -50),
            session("wait-new", "waiting", since: -10), session("done-new", "done", since: -60),
            session("wait-old", "waiting", since: -300), session("wait-mid", "waiting", since: -100),
        ])
        check(ids(ordered) == ["wait-old", "wait-mid", "wait-new", "work", "done-new", "done-old"],
              "session order: longest waiting first, then working, then newest done")

        var c = JumpCycle()
        func press(_ sessions: [Session], at seconds: TimeInterval, unseen: Set<String> = []) -> String? {
            c.next(sessions, unseen: unseen, now: t0.addingTimeInterval(seconds))?.id
        }
        check(c.target(ordered, unseen: [], now: t0)?.id == "wait-old", "target before any press: the longest waiting")
        check(press(ordered, at: 0) == "wait-old", "first press: the longest waiting")
        check(c.target(ordered, unseen: [], now: t0.addingTimeInterval(1))?.id == "wait-mid",
              "looking at the target doesn't move the cycle on")
        check(press(ordered, at: 2) == "wait-mid", "quick second press: the next waiting")
        check(press(ordered, at: 4) == "wait-new", "quick third press: the one after")
        check(press(ordered, at: 6) == "wait-old", "quick fourth press: back to the first")
        check(press(ordered, at: 20) == "wait-old", "a press after a pause starts at the first again")

        let answered = ordered.filter { $0.id != "wait-old" }
        check(press(answered, at: 21) == "wait-mid", "the last one stopped waiting: start at the top")

        let noWaits = ordered.filter { $0.state != "waiting" }
        check(press(noWaits, at: 40, unseen: ["done-old", "done-new"]) == "done-new",
              "nobody waiting: the newest finished one you haven't seen")
        check(press(noWaits, at: 41, unseen: ["done-old"]) == "done-old", "a finished one you've seen is skipped")
        check(press(noWaits, at: 42) == nil, "nobody waiting and nothing unseen: no target")
        check(press(ordered, at: 43, unseen: ["done-new"]) == "wait-old", "a waiting session beats an unseen finished one")
    }

    static func awake() {
        func policy(working: Int = 1, keepAwake: Bool = true, lidAwake: Bool = true, onBattery: Bool = false,
                    battery: Int? = 80, thermal: ProcessInfo.ThermalState = .nominal,
                    quiet: TimeInterval = .infinity) -> AwakePolicy {
            AwakePolicy(working: working, keepAwake: keepAwake, lidAwake: lidAwake, onBattery: onBattery,
                        batteryPercent: battery, thermal: thermal, quiet: quiet)
        }

        check(!policy(working: 0).holdIdle, "nothing working: no idle assertion")
        check(policy(working: 1).holdIdle, "one working: idle assertion")
        check(policy(working: 3).holdIdle, "three working: idle assertion")
        check(!policy(keepAwake: false).holdIdle, "keep awake off: no idle assertion")
        check(policy(onBattery: true, battery: 5, thermal: .critical).holdIdle, "battery and heat cutoffs leave the idle assertion alone")

        check(policy().holdLid, "lid mode on and working: lid sleep off")
        check(!policy(working: 0).holdLid, "lid mode on, nothing working: lid sleep on")
        check(!policy(lidAwake: false).holdLid, "lid mode off: lid sleep on")
        check(policy(keepAwake: false).holdLid, "lid mode works without keep awake")

        check(policy(onBattery: true, battery: 21).holdLid, "on battery at 21%: still held")
        check(!policy(onBattery: true, battery: 20).holdLid, "on battery at 20%: cut off")
        check(!policy(onBattery: true, battery: 3).holdLid, "on battery at 3%: cut off")
        check(policy(onBattery: false, battery: 5).holdLid, "plugged in at 5%: still held")
        check(policy(onBattery: false, battery: nil).holdLid, "no battery: still held")

        check(policy(thermal: .fair).holdLid, "fair thermal state: still held")
        check(!policy(thermal: .serious).holdLid, "serious thermal state: cut off")
        check(!policy(thermal: .critical).holdLid, "critical thermal state: cut off")

        check(policy(working: 0).lidRelease == .finished, "released because work finished")
        check(policy(onBattery: true, battery: 10).lidRelease == .cutoff, "released because of the battery cutoff")
        check(policy(thermal: .serious).lidRelease == .cutoff, "released because of the heat cutoff")
        check(policy(lidAwake: false).lidRelease == .turnedOff, "released because the option was turned off")
        check(policy(working: 0, lidAwake: false).lidRelease == .turnedOff, "turned off counts as turned off even when idle")

        check(policy(working: 0, quiet: 5).holdLid && policy(working: 0, quiet: 5).holdIdle,
              "done 5 s ago: both still held, in case a Stop hook sends it back to work")
        let settled = policy(working: 0, quiet: 15)
        check(!settled.holdLid && settled.lidRelease == .finished, "quiet for the whole 15 s: released as finished")
        let low = policy(working: 0, onBattery: true, battery: 10, quiet: 5)
        check(!low.holdLid && low.lidRelease == .cutoff, "battery cutoff still releases at once in the grace window")
        check(!policy(working: 0, lidAwake: false, quiet: 5).holdLid, "turning lid mode off still releases at once")

        check(LidRelease.finished.sleepsMac(lidClosed: true, clamshellCausesSleep: true), "finished, lid closed: sleep")
        check(LidRelease.cutoff.sleepsMac(lidClosed: true, clamshellCausesSleep: true), "cutoff, lid closed: sleep")
        check(!LidRelease.finished.sleepsMac(lidClosed: false, clamshellCausesSleep: true), "finished, lid open: no sleep")
        check(!LidRelease.finished.sleepsMac(lidClosed: true, clamshellCausesSleep: false),
              "finished, lid closed on a desk setup: no sleep")
        check(!LidRelease.turnedOff.sleepsMac(lidClosed: true, clamshellCausesSleep: true), "turned off, lid closed: no sleep")
    }
}

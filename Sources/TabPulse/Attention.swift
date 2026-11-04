import Foundation

/// One "Still needs you" banner per wait, once a session has waited five minutes. Plain values in and out, with no
/// AppKit, so scripts/test-logic.sh can test it.
struct WaitReminder {
    static let after: TimeInterval = 300

    /// Each wait already reminded about, by session id and the time it started waiting.
    private var sent: Set<String> = []

    /// The sessions to remind about now. `focused` is an AppleScript call, so it runs only when one is due.
    mutating func due(_ sessions: [Session], now: Date, focused: () -> String?) -> [Session] {
        let waits = sessions.filter { $0.state == "waiting" }
        sent.formIntersection(waits.map(Self.key))   // a wait that ended can't come back; a new one gets a new key
        let ready = waits.filter { now.timeIntervalSince($0.since) >= Self.after && !sent.contains(Self.key($0)) }
        guard !ready.isEmpty else { return [] }
        let f = focused()
        let due = ready.filter { $0.tty != f }   // looking at it: not yet, but it can remind once you look away
        sent.formUnion(due.map(Self.key))
        return due
    }

    private static func key(_ s: Session) -> String { "\(s.id) \(s.since.timeIntervalSince1970)" }
}

enum Attention {
    /// Sessions that began a new wait since the last reload. A second prompt right after the first has a new `since`.
    static func startedWaiting(_ sessions: [Session], before: [String: Session]) -> [Session] {
        sessions.filter { s in
            guard s.state == "waiting" else { return false }
            guard let b = before[s.id] else { return true }
            return b.state != "waiting" || b.since != s.since
        }
    }
}

/// Where Control-Option-Command-J goes: sessions waiting on you in SessionStore order (longest waiting first), and
/// on a quick second press the next one. With none waiting, the newest finished session you haven't seen.
struct JumpCycle {
    static let window: TimeInterval = 4

    private var last: (id: String, at: Date)?

    /// Who a press would go to now, without moving the cycle on.
    func target(_ sessions: [Session], unseen: Set<String>, now: Date) -> Session? {
        let waiting = sessions.filter { $0.state == "waiting" }
        guard !waiting.isEmpty else { return sessions.first { $0.state == "done" && unseen.contains($0.id) } }
        // The one you just went to may have stopped waiting (you answered it); then start over at the top.
        if let last, now.timeIntervalSince(last.at) < Self.window, let i = waiting.firstIndex(where: { $0.id == last.id }) {
            return waiting[(i + 1) % waiting.count]
        }
        return waiting[0]
    }

    mutating func next(_ sessions: [Session], unseen: Set<String>, now: Date) -> Session? {
        let t = target(sessions, unseen: unseen, now: now)
        last = t.map { ($0.id, now) }
        return t
    }
}

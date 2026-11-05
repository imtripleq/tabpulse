import Foundation

struct Session {
    let id: String
    var state: String          // working | waiting | done
    let since: Date            // when it entered this state
    let turn: Date             // when the current turn started, across permission prompts
    let updated: Date          // the hook's last write
    let cwd: String
    let tty: String
    let pid: Int32
    let detail: String         // "running Bash", "thinking", "permission to use Edit"
    let event: String          // the hook event behind the last write
    var background = ""        // agents or a workflow still running after the turn stopped
    var name: String { (cwd as NSString).lastPathComponent }
    var rank: Int { state == "waiting" ? 0 : state == "working" ? 1 : 2 }
}

/// The per-session JSON files that tabpulse-hook.sh writes.
enum SessionStore {
    static let root = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/tabpulse")
    static let dir = (root as NSString).appendingPathComponent("sessions")
    private static let iso = ISO8601DateFormatter()

    static func load() -> [Session] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var found: [Session] = []
        for n in names where n.hasSuffix(".json") {
            let path = (dir as NSString).appendingPathComponent(n)
            guard let data = fm.contents(atPath: path),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let pid = Int32((j["pid"] as? Int) ?? 0)
            let updated = iso.date(from: j["updated"] as? String ?? "") ?? .distantPast
            // Claude exited without SessionEnd (crash, closed tab), or the hook never found its process: forget it.
            let gone = pid > 0 ? (kill(pid, 0) != 0 && errno == ESRCH) : Date().timeIntervalSince(updated) > 12 * 3600
            if gone { try? fm.removeItem(atPath: path); continue }
            let since = iso.date(from: j["since"] as? String ?? "") ?? Date()
            var state = j["state"] as? String ?? "done"
            let background = j["background"] as? String ?? ""
            // Killed background work sends no hook, so a long silence ends it rather than spinning (and keeping
            // the Mac awake) forever. Its agents' tool calls refresh updated while they run.
            if state == "working" && !background.isEmpty && Date().timeIntervalSince(updated) > staleBackground {
                state = "done"
                markDone(path: path, j)
            }
            found.append(Session(id: String(n.dropLast(5)),
                                 state: state,
                                 since: since,
                                 turn: iso.date(from: j["turn"] as? String ?? "") ?? since,   // older hooks wrote no turn
                                 updated: updated,
                                 cwd: j["cwd"] as? String ?? "",
                                 tty: j["tty"] as? String ?? "",
                                 pid: pid,
                                 detail: j["detail"] as? String ?? "",
                                 event: j["event"] as? String ?? "",
                                 background: background))
        }
        return ordered(found)
    }

    /// Needs-you first (longest waiting first), then working (longest running first), then done (most recent first).
    static func ordered(_ found: [Session]) -> [Session] {
        found.sorted { a, b in
            a.rank != b.rank ? a.rank < b.rank
                : a.rank == 2 ? a.since > b.since
                : a.rank == 1 ? a.turn < b.turn
                : a.since < b.since
        }
    }

    /// A turn ended without a Stop hook (Esc interrupt); record it so the menu agrees with the tab.
    static func markDone(_ s: Session) {
        let path = (dir as NSString).appendingPathComponent("\(s.id).json")
        guard let data = FileManager.default.contents(atPath: path),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        markDone(path: path, j)
    }

    static let staleBackground: TimeInterval = 30 * 60

    private static func markDone(path: String, _ file: [String: Any]) {
        var j = file
        j["state"] = "done"
        j["background"] = ""
        j["since"] = iso.string(from: Date())
        j["event"] = "TabPulsePeek"
        if let out = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted]) {
            try? out.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}

#!/bin/bash
# Feeds fake Claude Code hook events to the hook and checks the state file it writes.
set -euo pipefail
cd "$(dirname "$0")/.."

HOOK=plugin/hooks/tabpulse-hook.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/.claude/tabpulse/sessions/t1.json"
OLD="2000-01-01T00:00:00Z"
fail=0

# ev <event> [tool] [message] [extra fields as a JSON object]
ev() { jq -cn --arg e "$1" --arg t "${2:-}" --arg m "${3:-}" --argjson x "${4:-null}" \
  '{session_id: "t1", hook_event_name: $e, cwd: "/tmp/demo", tool_name: $t, message: $m} + $x'; }
note() { ev Notification "" "$1" "{\"notification_type\": \"$2\"}"; }
send() { HOME="$TMP" bash "$HOOK" <<<"$1"; }
pass() { echo "ok   $1"; }
flunk() { echo "FAIL $1"; fail=1; }

# check <event json> <expected state> <expected detail>
check() {
  local out got label
  out=$(send "$1")
  [ -z "$out" ] || flunk "hook printed to stdout: $out"
  label=$(jq -r '[.hook_event_name, .notification_type // empty, .source // empty, .error // empty,
    (if .agent_id then "subagent" else empty end), (if .is_interrupt then "interrupt" else empty end)] | join(" ")' <<<"$1")
  got=$(jq -r '"\(.state)|\(.detail)"' "$STATE" 2>/dev/null || echo missing)
  if [ "$got" = "$2|$3" ]; then pass "$label -> $2 | $3"; else flunk "$label: want $2|$3, got $got"; fi
}

# Set fields of the state file to $OLD, then assert whether a later event kept or replaced them.
backdate() { local f; for f in "$@"; do jq --arg f "$f" --arg v "$OLD" '.[$f] = $v' "$STATE" >"$STATE.new" && mv "$STATE.new" "$STATE"; done; }
kept() { local v; v=$(jq -r ".$1" "$STATE"); if [ "$v" = "$OLD" ]; then pass "$2"; else flunk "$2 ($1 = $v)"; fi; }
renewed() { local v; v=$(jq -r ".$1" "$STATE"); if [ "$v" != "$OLD" ] && [ "$v" != null ]; then pass "$2"; else flunk "$2 ($1 = $v)"; fi; }

check "$(ev SessionStart)" "done" ""
check "$(ev Notification "" "Claude is waiting for your input")" "done" ""
check "$(ev UserPromptSubmit)" working thinking
check "$(ev PreToolUse Bash)" working "running Bash"
check "$(ev PreToolUse mcp__github__create_issue)" working "running create_issue"
check "$(ev PostToolUse Bash)" working thinking
check "$(ev Notification "" "Claude needs your permission to use Edit")" waiting "permission to use Edit"
check "$(ev Stop)" "done" ""

# turn spans the whole turn; since is only the time in the current state.
check "$(ev UserPromptSubmit)" working thinking
backdate turn since
check "$(ev UserPromptSubmit)" working thinking
kept turn "a queued prompt while working keeps the turn"
kept since "a queued prompt while working keeps since"
check "$(note "Claude needs your permission to use Bash" permission_prompt)" waiting "permission to use Bash"
check "$(ev PostToolUse Bash)" working thinking
kept turn "turn survives waiting -> working"
renewed since "since restarts on waiting -> working"
check "$(ev Stop)" "done" ""
kept turn "Stop keeps the turn"
check "$(ev UserPromptSubmit)" working thinking
renewed turn "a new prompt from done starts a new turn"
backdate turn
check "$(note "Claude needs your permission to use Bash" permission_prompt)" waiting "permission to use Bash"
check "$(ev UserPromptSubmit)" working thinking
renewed turn "a new prompt after a dismissed permission prompt starts a new turn"
jq -n --arg v "$OLD" '{state: "working", since: $v, detail: "thinking"}' >"$STATE"
check "$(ev PostToolUse Bash)" working thinking
kept turn "a file without turn falls back to since"

# Compaction fires SessionStart mid-turn; it must not end the turn.
check "$(ev PreToolUse Bash)" working "running Bash"
backdate since
check "$(ev SessionStart "" "" '{"source": "compact"}')" working "running Bash"
kept since "compaction keeps since"
check "$(ev Stop)" "done" ""
check "$(ev SessionStart "" "" '{"source": "compact"}')" "done" ""
check "$(ev SessionStart "" "" '{"source": "startup"}')" "done" ""

# An API error ends the turn with StopFailure instead of Stop.
check "$(ev UserPromptSubmit)" working thinking
check "$(ev StopFailure "" "" '{"error": "rate_limit"}')" "done" "stopped: rate limit"
check "$(note "Claude is waiting for your input" idle_prompt)" "done" "stopped: rate limit"
check "$(ev UserPromptSubmit)" working thinking
check "$(ev StopFailure)" "done" "stopped: error"

# Usage-limit notices arrive after the turn has stopped, and still need you.
check "$(ev UserPromptSubmit)" working thinking
check "$(ev StopFailure "" "" '{"error": "rate_limit"}')" "done" "stopped: rate limit"
backdate turn
check "$(note "Usage limit reset, press enter to continue" quota_auto_resume_stale)" waiting "Usage limit reset, press enter to continue"
check "$(note "The task will not resume on its own" quota_auto_resume_disabled)" waiting "Usage limit reset, press enter to continue"
check "$(ev UserPromptSubmit)" working thinking
renewed turn "a prompt after a usage-limit notice starts a new turn"

# Esc or a rejected permission fires no Stop; Claude's idle notice ends the turn.
check "$(ev UserPromptSubmit)" working thinking
check "$(ev PreToolUse Bash)" working "running Bash"
check "$(note "Claude is waiting for your input" idle_prompt)" "done" ""
check "$(ev UserPromptSubmit)" working thinking
check "$(note "Claude needs your permission to use Bash" permission_prompt)" waiting "permission to use Bash"
check "$(note "Claude is waiting for your input" idle_prompt)" "done" ""
check "$(ev UserPromptSubmit)" working thinking
check "$(ev Notification "" "Claude needs your permission to use Edit")" waiting "permission to use Edit"
check "$(ev Notification "" "Claude is waiting for your input")" "done" ""

# Notices that need nothing from the user leave a working session alone.
check "$(ev UserPromptSubmit)" working thinking
check "$(ev PreToolUse mcp__forms__ask)" working "running ask"
for t in quota_auto_resume_fired elicitation_response elicitation_complete auth_success plugin_notification agent_completed; do
  check "$(note "Something happened" "$t")" working "running ask"
done
check "$(note "Form from forms" elicitation_dialog)" waiting "Form from forms"
check "$(note "Response sent" elicitation_response)" working thinking
check "$(note "Claude needs your input" agent_needs_input)" waiting "input"
check "$(ev PostToolUse Bash)" working thinking
check "$(note "builder needs permission for Bash" worker_permission_prompt)" waiting "builder needs permission for Bash"
check "$(note "Claude Code continued your task" quota_auto_resume_fired)" working thinking

# A failed tool fires PostToolUseFailure instead of PostToolUse.
check "$(ev PreToolUse Bash)" working "running Bash"
check "$(note "Claude needs your permission to use Bash" permission_prompt)" waiting "permission to use Bash"
check "$(ev PostToolUseFailure Bash "" '{"is_interrupt": false}')" working thinking
check "$(ev PreToolUse Task)" working "running Task"
check "$(ev PostToolUseFailure Bash "" '{"agent_id": "a1", "is_interrupt": true}')" working thinking
check "$(ev PreToolUse Bash)" working "running Bash"
check "$(ev PostToolUseFailure Bash "" '{"is_interrupt": true}')" "done" ""

send "$(ev SessionEnd)"
if [ ! -e "$STATE" ]; then pass "SessionEnd removes the file"; else flunk "file left after SessionEnd"; fi

check "$(ev SessionStart "" "" '{"source": "compact"}')" "done" ""

send '{"session_id":"../escape","hook_event_name":"Stop"}'
if [ ! -e "$TMP/.claude/tabpulse/escape.json" ]; then pass "unsafe session ids are ignored"; else flunk "path traversal"; fi

send 'not json'
pass "bad input exits cleanly"

exit $fail

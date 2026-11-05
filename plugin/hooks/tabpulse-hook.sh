#!/bin/bash
# TabPulse hook for Claude Code: records each session's state for the TabPulse menu bar app in
# ~/.claude/tabpulse/sessions/<session_id>.json. Must stay silent on stdout (UserPromptSubmit
# output is fed to Claude) and always exit 0, so it can never block or change a session.

DIR="$HOME/.claude/tabpulse/sessions"
command -v jq >/dev/null 2>&1 || exit 0
mkdir -p "$DIR" 2>/dev/null || exit 0
input=$(cat)

# Unit separator, not tab: bash collapses runs of tabs, which would shift empty fields.
US=$'\x1f'
# bg names the agents, workflows and teammates still running when a turn stops. Background shells and
# monitors don't count: they are often servers or log tails that never finish.
IFS="$US" read -r sid event cwd tool msg ntype source err intr agent bg < <(jq -r --arg us "$US" \
  '[.session_id, .hook_event_name, .cwd, .tool_name, .message, .notification_type, .source, .error, .is_interrupt, .agent_id,
    ([(.background_tasks // [])[]? | select(type == "object" and ((.type // "") | IN("subagent", "workflow", "teammate", "cloud session")))] as $b
     | if ($b | length) == 0 then null
       elif ($b | length) > 1 then "\($b | length) tasks"
       elif $b[0].type == "workflow" then ("workflow " + ($b[0].name // "") | rtrimstr(" "))
       elif $b[0].type == "subagent" then (($b[0].agent_type // "") + " agent" | ltrimstr(" "))
       else $b[0].type end)]
   | map(. // "" | tostring | gsub("[\u001f\n]"; " ")) | join($us)' \
  <<<"$input" 2>/dev/null)
if [ -z "$sid" ] || [ -z "$event" ]; then exit 0; fi
case "$sid" in */* | .*) exit 0 ;; esac   # the id becomes a file name
file="$DIR/$sid.json"

if [ "$event" = "SessionEnd" ]; then
  rm -f "$file"
  exit 0
fi

prev_state="" prev_since="" prev_turn="" prev_bg=""
if [ -f "$file" ]; then
  IFS="$US" read -r prev_state prev_since prev_turn prev_bg < <(jq -r --arg us "$US" \
    '[.state // "", .since // "", .turn // "", .background // ""] | join($us)' "$file" 2>/dev/null)
fi

detail=""
background=$prev_bg   # what is still running in the background, e.g. "workflow review in background"
case "$event" in
  SessionStart)
    # Compaction fires SessionStart too, often mid-turn, so it keeps whatever state the session had.
    [ "$source" = "compact" ] && [ -n "$prev_state" ] && exit 0
    state="done" background=""
    ;;
  Stop)
    # Background agents wake Claude again when they finish, so the session is still at work.
    state="done" background=""
    [ -n "$bg" ] && state="working" detail="$bg in background" background="$detail"
    ;;
  StopFailure)   # an API error ended the turn instead of Stop
    state="done" detail="stopped: ${err:-error}" background=""
    detail=${detail//_/ }   # rate_limit -> rate limit
    ;;
  UserPromptSubmit) state="working" detail="thinking" background="" ;;
  PostToolUse) state="working" detail="thinking" ;;
  PostToolUseFailure)
    state="working" detail="thinking"
    # Esc during a tool: no Stop follows. A subagent's aborted tool (agent_id set) leaves the main turn running.
    [ "$intr" = "true" ] && [ -z "$agent" ] && state="done" detail="" background=""
    ;;
  PreToolUse)
    state="working" detail="running ${tool##*__}"   # mcp__server__tool -> tool
    [ -n "$tool" ] || detail="thinking"
    ;;
  Notification)
    # Older Claude Code sends no notification_type, so its idle notice is known only by the message.
    [ -z "$ntype" ] && [[ "$msg" == *"waiting for your input"* ]] && ntype="idle_prompt"
    case "$ntype" in
      idle_prompt)
        # Claude is back at the prompt, so a turn that ended without Stop (Esc, a rejected permission) is over.
        # It sits at the prompt while background work runs too, so that isn't the end.
        [ "$prev_state" = "working" ] || [ "$prev_state" = "waiting" ] || exit 0
        [ -z "$prev_bg" ] || exit 0
        state="done"
        ;;
      "" | permission_prompt | worker_permission_prompt | elicitation_dialog | elicitation_url_dialog | agent_needs_input)
        [ "$prev_state" = "working" ] || exit 0
        state="waiting" detail="${msg#Claude needs your }"   # "... permission to use Edit" -> "permission to use Edit"
        ;;
      quota_auto_resume_stale | quota_auto_resume_disabled)
        # These come after a usage-limit stop, so the session is already done but paused on you.
        [ "$prev_state" = "waiting" ] && exit 0
        state="waiting" detail="$msg"
        ;;
      elicitation_response | elicitation_complete | quota_auto_resume_fired)
        # Only clears a "needs you": a working session keeps its "running <tool>" detail.
        [ "$prev_state" = "waiting" ] || exit 0
        state="working" detail="thinking"
        ;;
      *) exit 0 ;;   # auth_success, plugin_notification and the like need nothing from the user
    esac
    ;;
  *) exit 0 ;;
esac
# A background agent's tool calls and cleared notices show what the session is waiting on, not "running Bash".
if [ "$state" = "working" ] && [ -n "$background" ] && { [ -n "$agent" ] || [ "$event" = "Notification" ]; }; then
  detail="$background"
fi

# Hooks run in a detached shell. Walk up to the Claude Code process (native "claude", or node/bun for
# npm installs) to get the terminal's tty and a pid the app can check is still alive.
pid=$PPID tty="" cpid=""
for _ in 1 2 3 4 5 6 7 8; do
  read -r ppid t comm < <(ps -o ppid=,tty=,comm= -p "$pid" 2>/dev/null)
  [ -z "$ppid" ] && break
  case "${comm##*/}" in
    claude | node | bun)
      cpid=$pid
      [ "$t" != "??" ] && tty="/dev/$t"
      break
      ;;
  esac
  pid=$ppid
done

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
since=$now   # time in the current state, e.g. how long it has waited on you
[ "$state" = "$prev_state" ] && [ -n "$prev_since" ] && since=$prev_since
# turn spans the whole turn, so a permission prompt or a queued prompt doesn't restart it.
# Files from older hooks have no turn; their since is the best guess.
turn=${prev_turn:-${prev_since:-$now}}
case "$state:$prev_state" in
  working:working) ;;
  working:waiting) [ "$event" = "UserPromptSubmit" ] && turn=$now ;;   # a new prompt means the dialog was dismissed
  working:*) turn=$now ;;
esac

tmp="$file.$$"
jq -n --arg state "$state" --arg since "$since" --arg turn "$turn" --arg updated "$now" --arg cwd "$cwd" \
  --arg tty "$tty" --arg pid "$cpid" --arg event "$event" --arg detail "$detail" --arg background "$background" \
  '{state: $state, since: $since, turn: $turn, updated: $updated, cwd: $cwd, tty: $tty,
    pid: ($pid | tonumber? // 0), event: $event, detail: $detail, background: $background}' >"$tmp" 2>/dev/null && mv -f "$tmp" "$file"
rm -f "$tmp" 2>/dev/null
exit 0

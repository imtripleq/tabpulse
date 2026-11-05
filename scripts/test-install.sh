#!/bin/bash
# shellcheck disable=SC2016,SC2329  # checks are single-quoted strings that check() evals
# Runs install.sh and uninstall.sh against a throwaway HOME and checks settings.json is merged safely:
# existing settings and hooks survive, re-installing doesn't duplicate, a symlinked file stays a symlink,
# and a broken settings.json or a missing jq stops both scripts before they change anything.
set -euo pipefail
cd "$(dirname "$0")/.."
unset CLAUDE_CONFIG_DIR   # a developer's own would point the scripts at their real settings

[ -d build/TabPulse.app ] || scripts/build.sh >/dev/null
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.claude" "$T/dotfiles"
cat >"$T/dotfiles/settings.json" <<'EOF'
{ "model": "opus", "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "echo existing" } ] } ] } }
EOF
ln -s "$T/dotfiles/settings.json" "$T/.claude/settings.json"
S="$T/.claude/settings.json"
H="$T/.claude/hooks/tabpulse-hook.sh"
fail=0

# TABPULSE_SUDOERS keeps uninstall.sh away from a real lid-closed sudoers rule on the developer's Mac.
in_home() { HOME="$1" TABPULSE_APP="$PWD/build/TabPulse.app" TABPULSE_NO_PROCESS=1 TABPULSE_SUDOERS="$1/sudoers-rule" bash "${@:2}"; }
run() { in_home "$T" "$@" >/dev/null; }
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
ours() { jq '[.hooks // {} | .[][] | .hooks[] | select(.command | contains("tabpulse-hook.sh"))] | length' "${1:-$S}"; }
existing() { jq -e '.hooks.Stop[].hooks[] | select(.command == "echo existing")' "$S" >/dev/null; }
enable_plugin() {   # $1 is a Claude config dir
  jq '.enabledPlugins = {"tabpulse@tabpulse": true}' "$1/settings.json" >"$T/edit.json"
  cat "$T/edit.json" >"$1/settings.json"
}
plugin_installed() { mkdir -p "$1/plugins"; echo '{"version": 2, "plugins": {"tabpulse@tabpulse": [{"scope": "user"}]}}' >"$1/plugins/installed_plugins.json"; }

run install.sh
run install.sh
check "app installed" '[ -x "$T/Applications/TabPulse.app/Contents/MacOS/TabPulse" ]'
check "hook script installed" '[ -f "$H" ]'
check "login item written" 'plutil -lint "$T/Library/LaunchAgents/dev.tabpulse.TabPulse.plist" >/dev/null'
# launchd only notices a crash when it runs the app itself; open -a exits at once.
check "login item runs the app directly" \
  '[ "$(plutil -extract ProgramArguments.0 raw "$T/Library/LaunchAgents/dev.tabpulse.TabPulse.plist")" = "$T/Applications/TabPulse.app/Contents/MacOS/TabPulse" ]'
check "login item restarts TabPulse only after a crash" \
  '[ "$(plutil -extract KeepAlive.SuccessfulExit raw "$T/Library/LaunchAgents/dev.tabpulse.TabPulse.plist")" = false ]'
check "one TabPulse hook per event after two installs" '[ "$(ours)" = 9 ]'
check "existing hook kept" 'existing'
check "other settings kept" '[ "$(jq -r .model "$S")" = opus ]'
check "symlinked settings.json is still a symlink" '[ -L "$S" ]'
check "backup written" '[ -f "$S.tabpulse-backup" ]'

run uninstall.sh
check "uninstall removes TabPulse hooks" '[ "$(ours)" = 0 ]'
check "uninstall keeps existing hook" 'existing'
check "uninstall removes the app" '[ ! -e "$T/Applications/TabPulse.app" ]'
check "uninstall removes the login item" '[ ! -e "$T/Library/LaunchAgents/dev.tabpulse.TabPulse.plist" ]'
check "uninstall removes the hook script" '[ ! -e "$H" ]'

HOME="$T" TABPULSE_APP="$PWD/build/TabPulse.app" TABPULSE_NO_PROCESS=1 TABPULSE_SUDOERS="$T/sudoers-rule" bash install.sh --app-only >/dev/null
check "--app-only leaves settings.json alone" '[ "$(ours)" = 0 ]'

run install.sh
echo '# old' >>"$H"
check "--app-only warns when an earlier install's hooks are still there" 'in_home "$T" install.sh --app-only >"$T/out" && grep -q "still has TabPulse hooks" "$T/out"'
check "--app-only keeps those hooks" '[ "$(ours)" = 9 ]'
check "--app-only refreshes the hook copy they call" '! grep -q "# old" "$H"'

mkdir "$T/nojq"
for tool in bash grep rm cp cat mktemp; do ln -s "$(command -v "$tool")" "$T/nojq/$tool"; done
check "uninstall without jq stops with an error" '! PATH="$T/nojq" in_home "$T" uninstall.sh >/dev/null 2>"$T/err" && grep -q "jq is needed" "$T/err"'
check "uninstall without jq keeps the hooks and the hook script" '[ "$(ours)" = 9 ] && [ -f "$H" ]'
check "uninstall without jq keeps the app" '[ -d "$T/Applications/TabPulse.app" ]'

enable_plugin "$T/.claude"
run install.sh
check "a plugin enabled but not installed still gets settings.json hooks" '[ "$(ours)" = 9 ] && [ -f "$H" ]'
plugin_installed "$T/.claude"
echo '# old' >>"$H"
run install.sh
check "switching to the plugin removes the old hooks" '[ "$(ours)" = 0 ]'
check "switching to the plugin keeps the hook copy current for sessions still calling it" '[ -f "$H" ] && ! grep -q "# old" "$H"'
check "switching to the plugin keeps existing hook and settings" 'existing && [ "$(jq -r .model "$S")" = opus ] && [ -L "$S" ]'

B="$T/bad"
mkdir -p "$B/.claude"
echo '{ "model": "opus", }' >"$B/.claude/settings.json"
check "invalid settings.json stops the install" '! in_home "$B" install.sh >/dev/null 2>&1'
check "invalid settings.json stops it before anything is installed" '[ ! -e "$B/Applications" ] && [ ! -e "$B/.claude/hooks" ] && [ ! -e "$B/Library" ]'
mkdir -p "$B/.claude/hooks" && touch "$B/.claude/hooks/tabpulse-hook.sh"
echo '{ "hooks": { "Stop": "tabpulse-hook.sh", } }' >"$B/.claude/settings.json"
check "uninstall with invalid settings.json fails and removes nothing" '! in_home "$B" uninstall.sh >/dev/null 2>&1 && [ -f "$B/.claude/hooks/tabpulse-hook.sh" ]'

C="$T/multi"
W="$C/work"
mkdir -p "$C"
in_home "$C" install.sh >/dev/null
CLAUDE_CONFIG_DIR="$W" in_home "$C" install.sh >/dev/null
check "CLAUDE_CONFIG_DIR gets its own hooks" '[ "$(ours "$W/settings.json")" = 9 ]'
check "CLAUDE_CONFIG_DIR leaves ~/.claude/settings.json alone" '[ "$(ours "$C/.claude/settings.json")" = 9 ]'
CLAUDE_CONFIG_DIR="$W" in_home "$C" uninstall.sh >"$T/out"
check "CLAUDE_CONFIG_DIR uninstall cleans that config dir" '[ "$(ours "$W/settings.json")" = 0 ] && [ "$(ours "$C/.claude/settings.json")" = 9 ]'
check "CLAUDE_CONFIG_DIR uninstall keeps the hook copy ~/.claude still calls" '[ -f "$C/.claude/hooks/tabpulse-hook.sh" ] && grep -q "hook script was kept" "$T/out"'
CLAUDE_CONFIG_DIR="$W" in_home "$C" install.sh >/dev/null
enable_plugin "$W"
plugin_installed "$W"
CLAUDE_CONFIG_DIR="$W" in_home "$C" install.sh >/dev/null
check "plugin in one config dir keeps the hook copy another still calls" '[ "$(ours "$W/settings.json")" = 0 ] && [ -f "$C/.claude/hooks/tabpulse-hook.sh" ]'

# A stand-in sudo that only logs, so these never run the real one.
L="$T/lid"
mkdir -p "$L/bin" "$L/home"
printf '#!/bin/bash\necho "$*" >>"%s"\n' "$L/sudo.log" >"$L/bin/sudo"
chmod +x "$L/bin/sudo"
lid_uninstall() { PATH="$L/bin:$PATH" in_home "$L/home" uninstall.sh >/dev/null; }
lid_uninstall
check "uninstall without the lid-closed sudoers rule never runs sudo" '[ ! -e "$L/sudo.log" ]'
mkdir -p "$L/home/.claude/tabpulse" && touch "$L/home/.claude/tabpulse/lid-awake"
PATH="$L/bin:$PATH" in_home "$L/home" uninstall.sh >"$T/out"
check "uninstall with lid sleep left off but no rule only says how to fix it" '[ ! -e "$L/sudo.log" ] && grep -q "disablesleep 0" "$T/out"'
touch "$L/home/sudoers-rule"
lid_uninstall
check "uninstall removes the lid-closed sudoers rule" 'grep -qx "rm -f $L/home/sudoers-rule" "$L/sudo.log"'
check "uninstall leaves lid sleep alone when TabPulse turned it back on" '! grep -q pmset "$L/sudo.log"'
rm -f "$L/sudo.log"
mkdir -p "$L/home/.claude/tabpulse" && touch "$L/home/.claude/tabpulse/lid-awake"
lid_uninstall
check "uninstall turns lid sleep back on when TabPulse left it off" 'grep -qx "/usr/bin/pmset -a disablesleep 0" "$L/sudo.log"'

exit $fail

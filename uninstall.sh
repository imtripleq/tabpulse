#!/bin/bash
# Removes TabPulse: the app, its login item, its Claude Code hooks and its state folder.
#   curl -fsSL https://raw.githubusercontent.com/imtripleq/tabpulse/main/uninstall.sh | bash
set -euo pipefail
# One brace group, so bash parses the whole file before running any of it: a cut-off curl | bash is a syntax error.
{

SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# settings.json goes first: if it can't be cleaned, nothing is deleted and no hook is left calling a missing script.
if [ -f "$SETTINGS" ] && grep -q tabpulse-hook.sh "$SETTINGS"; then
  command -v jq >/dev/null || die "jq is needed to remove TabPulse's hooks from $SETTINGS. Install it with: brew install jq, then run this again. Nothing was removed."
  jq empty "$SETTINGS" || die "$SETTINGS is not valid JSON. Fix it and run this again. Nothing was removed."
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  cp "$SETTINGS" "$SETTINGS.tabpulse-backup"
  jq '.hooks = ((.hooks // {}) | map_values(map(.hooks |= map(select((.command // "") | contains("tabpulse-hook.sh") | not)))
                                             | map(select(.hooks | length > 0)))
                 | with_entries(select(.value | length > 0)))
       | if .hooks == {} then del(.hooks) else . end' "$SETTINGS" >"$tmp"
  cat "$tmp" >"$SETTINGS"   # write through, so a symlinked settings.json stays a symlink
  echo "Removed TabPulse hooks from $SETTINGS (backup: $SETTINGS.tabpulse-backup)"
fi

# TABPULSE_NO_PROCESS is for tests that run against a throwaway HOME.
if [ -z "${TABPULSE_NO_PROCESS:-}" ]; then
  # Unload the login item first, or launchd would start TabPulse again.
  launchctl bootout "gui/$(id -u)/dev.tabpulse.TabPulse" 2>/dev/null || true
  if pkill -x TabPulse 2>/dev/null; then
    sleep 0.5   # on SIGTERM it hands tab titles back before quitting
  fi
fi
# Lid-closed mode's sudoers rule needs root to remove, so sudo runs only if it exists. Tests set TABPULSE_SUDOERS.
RULE="${TABPULSE_SUDOERS:-/etc/sudoers.d/tabpulse}"
if [ -e "$RULE" ]; then
  echo "Removing the sudoers rule TabPulse added for lid-closed mode. macOS may ask for your password."
  # The marker means TabPulse quit without turning lid sleep back on.
  if [ -e "$HOME/.claude/tabpulse/lid-awake" ]; then
    sudo /usr/bin/pmset -a disablesleep 0 || echo "Couldn't turn lid sleep back on. Run: sudo pmset -a disablesleep 0"
  fi
  sudo rm -f "$RULE" || echo "Couldn't remove $RULE. Remove it with: sudo rm $RULE"
elif [ -e "$HOME/.claude/tabpulse/lid-awake" ]; then
  echo "Lid sleep may still be off. Turn it back on with: sudo pmset -a disablesleep 0"
fi
# The hook copy is shared, so keep it while the default config dir still calls it.
keep_hook=0
if [ "$SETTINGS" != "$HOME/.claude/settings.json" ] && grep -qs tabpulse-hook.sh "$HOME/.claude/settings.json"; then keep_hook=1; fi
rm -rf "$HOME/Applications/TabPulse.app" "$HOME/Library/LaunchAgents/dev.tabpulse.TabPulse.plist" "$HOME/.claude/tabpulse"
[ "$keep_hook" = 1 ] || rm -f "$HOME/.claude/hooks/tabpulse-hook.sh"

echo "TabPulse is uninstalled."
if [ "$keep_hook" = 1 ]; then
  echo "The hook script was kept because ~/.claude/settings.json still runs TabPulse's hooks. Run this again without CLAUDE_CONFIG_DIR to remove them."
fi
echo "Restart any Claude Code sessions that are still open: they keep calling the old hooks until then."
echo "If you used the Claude Code plugin, also run: /plugin uninstall tabpulse@tabpulse"
}

#!/bin/bash
# TabPulse installer. https://github.com/imtripleq/tabpulse
#
#   curl -fsSL https://raw.githubusercontent.com/imtripleq/tabpulse/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/imtripleq/tabpulse/main/install.sh | bash -s -- --app-only
#
# --app-only     install the app but leave ~/.claude/settings.json alone (use the Claude Code plugin for hooks)
# --from-source  build from source instead of downloading a release (needs the Xcode Command Line Tools)
#
# Run from a clone (./install.sh) it builds that checkout. Running it again upgrades in place.
set -euo pipefail
# One brace group, so bash parses the whole file before running any of it: a cut-off curl | bash is a syntax error.
{

REPO="${TABPULSE_REPO:-imtripleq/tabpulse}"
APP="$HOME/Applications/TabPulse.app"
AGENT="$HOME/Library/LaunchAgents/dev.tabpulse.TabPulse.plist"
HOOK="$HOME/.claude/hooks/tabpulse-hook.sh"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
PLUGINS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
EVENTS='["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure","Notification","Stop","StopFailure","SessionEnd"]'
# Drops every hook that calls tabpulse-hook.sh, then any event or hooks object left empty. uninstall.sh has a copy.
STRIP='.hooks = ((.hooks // {}) | map_values(map(.hooks |= map(select((.command // "") | contains("tabpulse-hook.sh") | not)))
                                             | map(select(.hooks | length > 0)))
                 | with_entries(select(.value | length > 0)))
       | if .hooks == {} then del(.hooks) else . end'

hooks=1 from_source=0
for arg in "$@"; do
  case "$arg" in
    --app-only) hooks=0 ;;
    --from-source) from_source=1 ;;
    -h | --help) echo "Usage: install.sh [--app-only] [--from-source]"; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

say() { printf '\033[35m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "TabPulse is a macOS app."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || die "TabPulse needs macOS 14 (Sonoma) or newer."
command -v jq >/dev/null || die "jq is missing (it ships with macOS 15 and later). Install it with: brew install jq"
# Checked before anything is downloaded, stopped or replaced, so a bad file leaves the current install running.
if [ "$hooks" = 1 ] && [ -s "$SETTINGS" ] && ! jq empty "$SETTINGS"; then
  die "$SETTINGS is not valid JSON. Fix it and run the installer again."
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Get the app: a prebuilt bundle (tests), this checkout, a fresh clone, or the latest release.
here=""
src="${BASH_SOURCE[0]:-}"
if [ -n "$src" ] && [ -f "$src" ]; then here=$(cd "$(dirname "$src")" && pwd); fi
if [ -n "${TABPULSE_APP:-}" ]; then
  built="$TABPULSE_APP"
elif [ -n "$here" ] && [ -f "$here/scripts/build.sh" ]; then
  say "Building from source"
  "$here/scripts/build.sh" >/dev/null
  built="$here/build/TabPulse.app"
elif [ "$from_source" = 1 ]; then
  say "Building from source"
  git clone -q --depth 1 "https://github.com/$REPO" "$tmp/src"
  "$tmp/src/scripts/build.sh" >/dev/null
  built="$tmp/src/build/TabPulse.app"
else
  base="https://github.com/$REPO/releases/latest/download"
  if [ -n "${TABPULSE_VERSION:-}" ]; then base="https://github.com/$REPO/releases/download/v${TABPULSE_VERSION#v}"; fi
  say "Downloading TabPulse"
  curl -fsSL "$base/TabPulse.zip" -o "$tmp/TabPulse.zip" || die "Download failed: $base/TabPulse.zip"
  curl -fsSL "$base/TabPulse.zip.sha256" -o "$tmp/TabPulse.zip.sha256" || die "Could not download the checksum: $base/TabPulse.zip.sha256"
  want=$(awk '{print $1}' "$tmp/TabPulse.zip.sha256")
  got=$(shasum -a 256 "$tmp/TabPulse.zip" | awk '{print $1}')
  if [ -z "$want" ] || [ "$want" != "$got" ]; then die "Checksum mismatch for TabPulse.zip"; fi
  ditto -x -k "$tmp/TabPulse.zip" "$tmp/out"
  built="$tmp/out/TabPulse.app"
fi
[ -x "$built/Contents/MacOS/TabPulse" ] || die "No app found at $built"

# TABPULSE_NO_PROCESS is for tests that install into a throwaway HOME.
manage=1
if [ -n "${TABPULSE_NO_PROCESS:-}" ]; then manage=0; fi
if [ "$manage" = 1 ] && pkill -x TabPulse 2>/dev/null; then
  sleep 0.5   # on SIGTERM it hands tab titles back before quitting
fi

say "Installing $APP"
mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
ditto "$built" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Enabled alone isn't enough: a stale enabledPlugins entry for a removed plugin would leave no hooks at all.
plugin_on=false
if jq -e 'any((.enabledPlugins // {}) | to_entries[]; (.key | startswith("tabpulse@")) and .value == true)' "$SETTINGS" >/dev/null 2>&1 \
  && jq -e 'any(.plugins // {} | keys[]; startswith("tabpulse@"))' "$PLUGINS" >/dev/null 2>&1; then
  plugin_on=true
fi
if [ "$hooks" = 1 ] && [ "$plugin_on" = true ]; then
  hooks=0
  if grep -q tabpulse-hook.sh "$SETTINGS"; then
    # Left in place, an earlier install's hooks would run next to the plugin's on every event.
    cp "$SETTINGS" "$SETTINGS.tabpulse-backup"
    jq "$STRIP" "$SETTINGS" >"$tmp/settings.json"
    cat "$tmp/settings.json" >"$SETTINGS"
    say "The TabPulse Claude Code plugin is enabled, so its old hooks were removed from $SETTINGS (backup: $SETTINGS.tabpulse-backup)"
  else
    say "The TabPulse Claude Code plugin is enabled, so settings.json is left alone"
  fi
fi
# Anything still calling a leftover copy must not run an older hook than this app.
if [ "$hooks" = 0 ] && [ -f "$HOOK" ]; then install -m 755 "$APP/Contents/Resources/tabpulse-hook.sh" "$HOOK"; fi

if [ "$hooks" = 1 ]; then
  say "Adding hooks to $SETTINGS"
  mkdir -p "$(dirname "$HOOK")" "$(dirname "$SETTINGS")"
  install -m 755 "$APP/Contents/Resources/tabpulse-hook.sh" "$HOOK"
  [ -s "$SETTINGS" ] || echo '{}' >"$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.tabpulse-backup"
  jq --arg cmd "bash \"$HOOK\"" --argjson events "$EVENTS" "$STRIP"'
    | reduce $events[] as $e (.;
        .hooks[$e] += [ (if ($e | IN("PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification")) then {matcher: "*"} else {} end)
                        + {hooks: [{type: "command", command: $cmd}]} ])
  ' "$SETTINGS" >"$tmp/settings.json"
  cat "$tmp/settings.json" >"$SETTINGS"   # write through, so a symlinked settings.json stays a symlink
fi

mkdir -p "$(dirname "$AGENT")"
cat >"$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.tabpulse.TabPulse</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$APP</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST

if [ "$manage" = 1 ]; then open "$APP"; fi

version=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
echo
echo "TabPulse $version is installed and starts at login. Look for ✳ in your menu bar."
echo
if [ "$hooks" = 0 ] && [ "$plugin_on" != true ]; then
  echo "  • Add the hooks from inside Claude Code:"
  echo "      /plugin marketplace add $REPO"
  echo "      /plugin install tabpulse@tabpulse"
fi
if [ "$hooks" = 0 ] && grep -qs tabpulse-hook.sh "$SETTINGS"; then
  echo "  • $SETTINGS still has TabPulse hooks from an earlier install. With the plugin on, both run on every event."
  echo "    Once the plugin is installed, run this installer again without --app-only to remove them."
fi
echo "  • New Claude Code sessions show up on their own. Restart any that were already open."
echo "  • macOS asks once whether TabPulse may control Ghostty. Click OK: that's how tabs get their spinner."
echo "  • macOS may also ask whether TabPulse can send notifications. Click Allow: that's how you hear a session finished."
echo "  • Hold ⌥ (Option) while clicking the menu bar icon to quit."
echo
echo "Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
}

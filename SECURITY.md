# Security

## What TabPulse touches

Nothing TabPulse does needs sudo. The installer and uninstaller edit `$CLAUDE_CONFIG_DIR/settings.json` when that variable is set, and `~/.claude/settings.json` otherwise. The app and the uninstaller can also read `~/.claude/settings.json` while `CLAUDE_CONFIG_DIR` is set, as described below. Everything else lives at the fixed paths below.

### The hook

- Claude Code runs `tabpulse-hook.sh` on nine hook events and passes it a JSON event on stdin. The installer's copy is `~/.claude/hooks/tabpulse-hook.sh`; the plugin runs the same script from Claude Code's plugin folder.
- It writes one small file per session to `~/.claude/tabpulse/sessions/<session id>.json`, and deletes that file when the session ends. It refuses session ids that contain `/` or start with `.`, since the id becomes the file name.
- To find the session's terminal, it runs `ps` on its parent processes up to the Claude Code process. It needs jq and does nothing without it.
- It never prints to stdout and always exits 0, so it can't inject text into a Claude session or block one.

### The app

- Reads the session files once a second. It deletes a file once its Claude process has exited (or, for a file with no process id, once the hook hasn't updated it for 12 hours), and rewrites a file as done when it finds that you stopped the turn with Esc.
- Writes `~/.claude/tabpulse/overrides`, the list of terminals whose tab titles it has changed, so it can hand them back after a crash.
- Sends AppleScript to Ghostty, and only to Ghostty: it reads and sets tab titles, reads which tab is in front, and focuses a tab when you click a session or its banner. macOS asks for your permission the first time TabPulse runs while Ghostty is open. It never launches Ghostty.
- Shows finished-session banners through macOS notifications. If macOS refuses those, it runs `/usr/bin/osascript` with `display notification` instead, which controls no other app. The title and text are passed as arguments, never as script, so a tab title can't change what runs.
- When the menu opens with no sessions, it reads `settings.json` (in `~/.claude`, and in `CLAUDE_CONFIG_DIR` if that is set in the app's own environment) to tell whether the hooks are installed. It never writes there.
- Saves your style choices in its preferences, under the `dev.tabpulse.TabPulse` defaults domain.
- Makes no network requests.

### The installer

- Puts the app in `~/Applications/TabPulse.app` and writes the login item `~/Library/LaunchAgents/dev.tabpulse.TabPulse.plist`. Unless you use `--app-only` or the plugin, it copies the hook to `~/.claude/hooks/tabpulse-hook.sh`. If a copy is already there, it refreshes it in every mode.
- Changes only the `hooks` section of `settings.json`, creating the file as `{}` if it is missing or empty. It does this only after copying the file to `settings.json.tabpulse-backup`, which each run replaces. jq writes the file back, so its indentation can change. It checks the file is valid JSON before it downloads or changes anything. With `--app-only` it never edits `settings.json`. It reads `plugins/installed_plugins.json` in the same config dir to tell whether the TabPulse plugin is installed.
- Removes macOS's quarantine flag from the app (`xattr -dr com.apple.quarantine`). TabPulse is signed ad hoc and not notarized, so Gatekeeper would otherwise block it.
- Quits a running TabPulse before replacing it, and opens the new copy afterwards.
- Downloads only from GitHub: `TabPulse.zip` from a release, or a `git clone` with `--from-source`, both from this repository unless `TABPULSE_REPO` names another one. `TABPULSE_VERSION` picks a specific release, and `TABPULSE_APP` (used by the tests) installs a local app without downloading anything. It verifies the zip against the SHA-256 file published with the same release, and stops if that file can't be downloaded, is empty or doesn't match. This catches a corrupt or incomplete download but not a tampered release, because both files come from the same place. The `--from-source` clone isn't checked.

### The uninstaller

- Removes TabPulse's hooks from `settings.json` first, after saving a backup. If jq is missing or the file isn't valid JSON, it stops without removing anything.
- Then quits a running TabPulse and deletes the app, the login item, `~/.claude/tabpulse/` and `~/.claude/hooks/tabpulse-hook.sh`. When it is run for another `CLAUDE_CONFIG_DIR`, it keeps the hook script while `~/.claude/settings.json` still uses it.
- Leaves the `settings.json.tabpulse-backup` file and the app's preferences. `defaults delete dev.tabpulse.TabPulse` removes the preferences.

## Reporting a vulnerability

Please report it privately through GitHub: open the repository's Security tab and choose "Report a vulnerability". If that button is missing, email denniskcc@hotmail.com instead. Don't open a public issue for it.

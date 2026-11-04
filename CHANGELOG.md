# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-11-04

### Added

- Options submenu next to Style. Its first item, Keep Mac awake while Claude works, is on by default and stops idle sleep while any session is working. The screen can still sleep. TabPulse lets go about 15 seconds after nothing is working, when you turn the option off, and when it quits.
- Lid-closed mode, under Options > Keep awake with lid closed, off by default. It asks for your admin password once and installs a sudoers rule at `/etc/sudoers.d/tabpulse` that allows only `pmset -a disablesleep 1` and `pmset -a disablesleep 0`. TabPulse then turns lid sleep off only while Claude works. It turns it back on when the work finishes, when the battery is at 20% or less and not plugged in, or when the Mac gets hot, and then puts a closed Mac to sleep unless macOS would keep it awake anyway (external display and power). If TabPulse crashes, it turns lid sleep back on at the next launch. The uninstaller removes the rule.
- A "Still needs you" notification once a session has waited on you for 5 minutes. It comes once per wait, skips the Ghostty tab you are looking at, and jumps to the tab when clicked. Turn it off under Options.
- ⌃⌥⌘J jumps to the tab that needs you from any app, longest waiting first, and a second press within a few seconds goes to the next one. With nothing waiting, it goes to the newest finished session you haven't seen, and otherwise it beeps. It needs no Accessibility permission. The menu has the same jump, and Options can turn the shortcut off.
- Optional sounds, under Options > Play sounds: Ping when a session starts waiting on you or a reminder goes out, and Glass when a session finishes. Neither plays for the tab you are looking at. With sounds on, banners skip their own sound, so you hear only one.

### Changed

- The menu picture in the README is now animated. `TabPulse --menu-demo` shows that scene live so it can be recorded.

## [0.1.0] - 2026-11-03

### Added

- Menu bar pill with a spinning ✳, the number of working sessions, an orange dot when one needs you, and a green dot when one finished while you were looking elsewhere. The green dot clears when you open the menu or look at that session's Ghostty tab. The ✳ turns grey when nothing is going on.
- Spinners and ● markers on Ghostty 1.4+ tab titles for sessions running directly in a Ghostty tab, handed back to Claude when a turn ends. Every ten seconds TabPulse peeks at Claude's own title to keep it current and to spot a turn stopped with Esc.
- Session list showing each session's title, what it is doing, and how long the turn has run, how long it has waited for you, or how long ago it finished. Clicking a session that runs in a Ghostty tab jumps to it. TabPulse never launches Ghostty or asks for Automation access just to look for a tab.
- Notification about ten seconds after a session finishes, skipped for the Ghostty tab you are looking at and for turns you stopped yourself. The wait lets a Stop hook that sends Claude back to work, such as `/goal`, cancel it. It says Stopped when an API error such as a rate limit ended the turn. Clicking it jumps to the tab. Where macOS refuses TabPulse's own notifications, the banner goes out through osascript instead.
- Style menu with a Tab spinner submenu and a Menu bar submenu, each split into sections. There are 16 tab spinners in two sections (Glyph: Braille, Bounce, Arc, Equalizer, Sparkle, Sine, Typing, Snake; Emoji: Moon, Garden, Heartbeat, Magic, Monkeys, Duck, Hatch, Slots) and 24 menu bar animations in three sections (Star: Spin, Breathe, Hop, Bloom, Neon, Rainbow, Morph, Sketch; Signal: Orbit, Comet, Radar, Wave, Helix, Equalizer, Pulse, Scanner; Playful: Chomp, Mochi, Kitty, Brainstorm, Rocket, Cradle, Prompt, Cube). Picking a menu bar style previews it for 3 seconds, even when nothing is working. The menu bar can speed up as more sessions work, and `--style-gallery` shows every menu bar style at once.
- Reduce Motion support: the menu bar shows a still pose of the chosen style, and each tab spinner holds one glyph, except Garden, which still grows with the turn.
- App icon.
- The Claude Code hook, on nine events (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Notification, Stop, StopFailure, SessionEnd), available through the installer or as a Claude Code plugin. It needs Claude Code 2.1.78 or newer. It marks a session as needing you only for notices that wait on you, such as permission prompts and dialogs. It ends a turn on Esc in any terminal, and on an API error, and it leaves compaction alone.
- One-line installer. It verifies the release zip against its published SHA-256 file and stops if that file is missing or doesn't match. It edits only the hooks in `settings.json` (in `CLAUDE_CONFIG_DIR`, or `~/.claude`), keeps a backup, and checks the file is valid JSON before it changes anything. `--app-only` leaves `settings.json` alone for the plugin route, and running it again without `--app-only` once the plugin is installed removes the old hooks.
- Uninstaller that removes the hooks from `settings.json` before deleting anything else, and stops with nothing removed if it can't.
- Releases with `TabPulse.zip` and its checksum, and release notes that explain how to install the zip by hand.

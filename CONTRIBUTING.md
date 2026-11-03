# Contributing to TabPulse

Thanks for taking a look. Small, focused pull requests are the easiest to review. For anything bigger than a bug fix, opening an issue first saves you from building something that won't fit. New tab spinners and menu bar styles are welcome, and [Adding a style](#adding-a-style) shows how.

## Setup

You need macOS 14 or newer, the Xcode Command Line Tools (`xcode-select --install`), jq, and shellcheck for the lint check (`brew install shellcheck`). Xcode itself is optional.

```sh
git clone https://github.com/imtripleq/tabpulse
cd tabpulse
./install.sh          # builds this checkout and installs it over any existing copy
```

To try a change without installing it, quit the installed copy (hold ⌥ and click the menu bar icon), then run your build directly:

```sh
scripts/build.sh && open build/TabPulse.app
```

`scripts/build.sh` calls `swiftc` directly, so it works even where SwiftPM is broken. `Package.swift` is only for editing and code completion in Xcode. Xcode's Run and `swift run` build a bare executable with no app bundle, which doesn't behave like the real app: it skips TabPulse's own notifications and sends banners through osascript, and it keeps its settings under the `TabPulse` defaults domain instead of `dev.tabpulse.TabPulse`. To run your change, use the `scripts/build.sh` line above.

## Layout

| Path | What it does |
|---|---|
| `Sources/TabPulse/main.swift` | Entry point, plus the `--version`, `--render-preview`, `--menu-demo` and `--style-gallery` flags |
| `Sources/TabPulse/StatusApp.swift` | Menu bar item, the menu with its Style submenus, and the main loop |
| `Sources/TabPulse/Styles.swift` | Tab spinner and menu bar style lists with their names and sections, and the saved choices |
| `Sources/TabPulse/PillView.swift` | The menu bar pill, its animation helpers (`play`, `loop`, `keyframes`, `group`, `pinned`, `capped`) and the shorter menu bar styles |
| `Sources/TabPulse/BarStar.swift` | The Sketch, Morph and Cube menu bar styles |
| `Sources/TabPulse/BarCharacters.swift` | The Chomp, Mochi, Kitty and Rocket menu bar styles |
| `Sources/TabPulse/BarScenes.swift` | The Prompt, Brainstorm and Cradle menu bar styles |
| `Sources/TabPulse/Views.swift` | The hand-drawn menu rows |
| `Sources/TabPulse/TabSync.swift` | Spinner titles on Ghostty tabs, and the ten-second peek at Claude's own title |
| `Sources/TabPulse/Ghostty.swift` | AppleScript calls to Ghostty |
| `Sources/TabPulse/Session.swift` | Reads the hook's JSON files and forgets sessions whose Claude has exited |
| `Sources/TabPulse/Notifier.swift` | Finished-session notifications, with an osascript fallback when macOS refuses its own |
| `Sources/TabPulse/Preview.swift` | Renders the README menu images, and runs the style gallery and its snap mode |
| `Resources/AppIcon.icns` | The app icon. `scripts/build.sh` copies it into the app bundle |
| `plugin/hooks/tabpulse-hook.sh` | The Claude Code hook, shared by the installer and the plugin |
| `plugin/`, `.claude-plugin/marketplace.json` | Claude Code plugin and marketplace |
| `plugin/.claude-plugin/icon.png` | Plugin listing icon |
| `assets/` | README images, plus `social-preview.png` for the repository's social preview setting |
| `install.sh`, `uninstall.sh` | What users run |
| `scripts/` | Build and test scripts |
| `.github/workflows/` | CI on pushes to main and on pull requests, and the release on a version tag |

## Session files

The hook writes one file per session to `~/.claude/tabpulse/sessions/<session_id>.json`, and the app reads them back:

| Field | Meaning |
|---|---|
| `state` | `working`, `waiting` (needs you) or `done` |
| `since` | When it entered this state, in ISO 8601 UTC. For a waiting session, how long it has waited; for a done one, when it finished |
| `turn` | When the current turn started. It carries over permission prompts, dialogs and queued prompts. The app uses `since` when it's missing |
| `updated` | The hook's last write |
| `cwd`, `tty`, `pid` | The session's folder, its terminal and the Claude Code process id (`tty` is empty and `pid` is 0 when the hook couldn't find them) |
| `event` | The hook event behind the last write, or `TabPulsePeek` when the app marked the turn done itself |
| `detail` | What it is doing: `running Bash`, `thinking`, `permission to use Edit`, or `stopped: rate limit` after an API error |

## Checks

CI builds a universal app, runs a smoke test and runs these on every pull request, so run them locally first:

```sh
scripts/test-hook.sh        # feeds fake hook events to the hook
scripts/test-install.sh     # installs and uninstalls into a throwaway HOME
shellcheck install.sh uninstall.sh scripts/*.sh plugin/hooks/*.sh
```

CI also checks that the hook events in `plugin/hooks/hooks.json` match `EVENTS` in `install.sh`, that the marketplace points at the plugin, and that the versions agree. It doesn't have the Claude Code CLI and doesn't run `claude plugin validate`, so if you change the plugin or marketplace files, validate them yourself. Without `--strict`, an unknown hook event is only a warning:

```sh
claude plugin validate --strict . && claude plugin validate --strict plugin
```

The events check reads `install.sh`'s `EVENTS='[...]'` line, so keep that assignment on one line, starting at column 0, with nothing after the closing quote. Both `install.sh` and `uninstall.sh` sit inside one `{ ... }` group, so a download cut off halfway through `curl | bash` runs nothing. Keep the closing `}` as the last line.

`test-install.sh` never touches your real `~/.claude` or the copy of TabPulse you have running. It unsets `CLAUDE_CONFIG_DIR` and sets `TABPULSE_NO_PROCESS=1`, which tells the scripts not to stop or start the app.

Attach a screenshot to any pull request that changes how something looks. If you change the menu, regenerate the README images too. The still menu-light.png and menu-dark.png come from:

```sh
build/TabPulse.app/Contents/MacOS/TabPulse --render-preview assets
```

The animated menu-light.gif and menu-dark.gif are screen recordings of `--menu-demo`. It shows the same scene live in a borderless window, with the spinners turning and the timers counting, and hides the pointer while it runs. Once the window is up it prints `window <number> <x>,<y>,<w>,<h>`, which you pass to `screencapture -R`:

```sh
TABPULSE_APPEARANCE=light TABPULSE_DEMO_SECONDS=9 build/TabPulse.app/Contents/MacOS/TabPulse --menu-demo &
screencapture -x -v -V 6 -R <x>,<y>,<w>,<h> menu-light.mov   # then the same with dark
```

Turn each recording into a looping GIF at 15 frames a second and 892 px wide, using any converter you like.

## Adding a style

### A menu bar style

1. In `Styles.swift`, add a case to `BarStyle` with its `name` and its `section` (Star, Signal or Playful). The cases are declared in Style menu order, so put the new one with the rest of its section. If it needs more room than the 13 pt star, add it to `isWide` as well.
2. Write a `buildX()` method in whichever of `BarStar.swift`, `BarCharacters.swift` or `BarScenes.swift` suits it, and call it from the `switch` in `PillView.build()`.
3. Draw into `fx`, or animate `star`. `fx` is y-up, `markWidth` wide and 13 pt tall, with the centre at `mid`. Colour with `ink` and `accent`, which the pill resolves for light and dark mode, and use `faceInk` for features drawn on an accent body.
4. Start every animation with `play(_:on:)`, never with `add(_:forKey:)` on the layer. Under Reduce Motion `play()` adds nothing, so the layers' model values become the still pose. Set them to a frame that reads well standing still.
5. Animations run at their base duration, and **Speed up when busy** retimes the layers, so there is no per-tick drawing. If your style looks wrong sped up, use `capped(seconds, top)` to limit how fast it gets, or `pinned(seconds)` to keep it at real time.

Then build and open it in the gallery next to the others, in both appearances and as a still pose:

```sh
scripts/build.sh
build/TabPulse.app/Contents/MacOS/TabPulse --style-gallery
TABPULSE_STILL=1 TABPULSE_APPEARANCE=dark build/TabPulse.app/Contents/MacOS/TabPulse --style-gallery
```

### A tab spinner

Add a case to `TabStyle` in `Styles.swift` with its `name`, its `section` (Glyph or Emoji), its frames and a `sample`.

- Each frame shows for one 0.12 s tick. Repeat a frame to hold it longer, the way Heartbeat and Slots do.
- Don't use ✳ or ● in the frames. ● is TabPulse's needs-you mark. ✳ is Claude's idle mark, which the ten-second peek looks for to spot a turn stopped with Esc. Sparkle is the one exception: `TabSync.peek` ignores a title that matches the one TabPulse just set, so Sparkle's ✳ frame can't pass for Claude's.
- Keep every frame the same kind of glyph: all braille, all block characters or all emoji. Mixing kinds changes the width, and the title next to the spinner jitters. A spinner several characters wide, like Sine or Typing, needs every frame at that width.
- The `sample` is what the Style menu shows and, for every style except Garden, what a tab holds under Reduce Motion. It must be one of the style's own frames, so TabSync can strip it from titles.

### The style gallery

`--style-gallery` opens a window with the menu bar styles running, one column per section. Add a comma-separated list of names, such as `--style-gallery chomp,rocket`, to show only those. Close the window or press ⌘Q to quit. Once the window is up, it prints `window <number> <x>,<y>,<w>,<h>` in the top-left coordinates that `screencapture -R` takes.

These environment variables change what it shows:

| Variable | Effect |
|---|---|
| `TABPULSE_GALLERY_SCALE=3` | Zooms the whole window, for screenshots that show detail |
| `TABPULSE_APPEARANCE=light` or `dark` | Forces an appearance |
| `TABPULSE_STILL=1` | Shows the Reduce Motion still poses |
| `TABPULSE_GALLERY_WORKING=4` | Shows that many working sessions with Speed up when busy on. Without it, the gallery shows 2 at base speed |
| `TABPULSE_SNAP_DIR=<dir>` | Snap mode: after a 1 second warm-up, saves screenshots of the window to `<dir>/frame-000.png`, `frame-001.png` and so on, then quits |
| `TABPULSE_SNAP_COUNT=<n>` | How many screenshots snap mode takes (default 1) |
| `TABPULSE_SNAP_EVERY=<s>` | Seconds between them (default 0.5) |

macOS has no `timeout` command. When you script snap mode, wrap it in perl's `alarm` so a stuck window can't hang the script:

```sh
TABPULSE_SNAP_DIR=/tmp/frames TABPULSE_SNAP_COUNT=40 TABPULSE_SNAP_EVERY=0.1 \
  perl -e 'alarm shift; exec @ARGV' 60 build/TabPulse.app/Contents/MacOS/TabPulse --style-gallery
```

## Supporting another terminal

Tab spinners and click-to-jump need four things from a terminal: set a tab's title by tty, read its current title and list every tab's title (for the spinners), and focus a tab (for jumping to it). TabPulse also needs a fifth, `focusedTTY`, the tty of the tab you're looking at. It uses that to skip the finished banner for that tab and to clear its green dot. `Ghostty.swift` does all five over AppleScript. It also provides `isRunning` and the `checkAccess()`/`access` permission check, which `StatusApp` tests before any other call, so TabPulse never launches the terminal or asks for Automation access without reason. Another terminal needs the same calls, plus a way for `StatusApp` to pick which terminal to talk to. Please open an issue first so we can agree on the shape.

## Releasing (maintainers)

1. Bump the version in `VERSION`, `plugin/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`. CI fails if they disagree.
2. Move the entries under `## [Unreleased]` in `CHANGELOG.md` into a new `## [<version>] - <date>` section. The release fails if that section is missing or empty.
3. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`.

A tag push runs the whole CI workflow first. Only after it passes does the release job check that the tag matches `VERSION`, build a universal app and publish `TabPulse.zip` with its checksum. The release notes are a generated install section, followed by that version's changelog section under "Changes". The install section links to the README's "Installing the zip by hand" heading, so keep that heading's wording. The installer fetches the latest release unless `TABPULSE_VERSION` is set.

## Code of conduct

Everyone taking part agrees to follow the [code of conduct](CODE_OF_CONDUCT.md).

// TabPulse product data for the site, trimmed to what the page imports.
// Copied from site/research/product-facts.md (checked against Sources/TabPulse/*.swift, v0.2.1).
// One rule changed on purpose: every ✳ in a string is written "✳︎" (U+2733 U+FE0E) so it never
// renders as the green emoji square. Strip U+FE0E if you need the app's exact bytes.

const STAR = '✳︎'; // ✳︎, text presentation

const freezeDeep = (value) => {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.values(value).forEach(freezeDeep);
    Object.freeze(value);
  }
  return value;
};

// ---------------------------------------------------------------------------
// Tab spinners (Styles.swift TabStyle). One frame per 0.12 s tick, repeats are deliberate holds.

export const TICK_MS = 120; // app timer while anything is working, the menu is open or a style previews

export const TAB_SPINNERS = freezeDeep({
  braille: ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'],
  bounce: ['⠁', '⠂', '⠄', '⡀', '⢀', '⠠', '⠐', '⠈'],
  arc: ['◜', '◠', '◝', '◞', '◡', '◟'],
  equalizer: ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█', '▇', '▆', '▅', '▄', '▃', '▂'],
  sparkle: ['·', '✢', STAR, '✶', '✻', '✽', '✻', '✶', STAR, '✢'],
  sine: ['⠊⠑⢄', '⠉⠢⣀', '⠑⢄⡠', '⠢⣀⠔', '⢄⡠⠊', '⣀⠔⠉', '⡠⠊⠑', '⠔⠉⠢'],
  typing: ['⡀⡀⡀', '⠄⡀⡀', '⠂⡀⡀', '⠄⠄⡀', '⡀⠂⡀', '⡀⠄⠄', '⡀⡀⠂', '⡀⡀⠄', '⡀⡀⡀'],
  snake: ['▘', '▀', '▜', '▟', '▙', '▛', '▐', '▖'],
  moon: ['🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘'],
  // Garden does not cycle: [seconds into the turn, glyph]. Use gardenGlyph().
  garden: [[0, '🌱'], [60, '🌿'], [180, '🌷'], [600, '🌻']],
  heartbeat: ['💜', '💜', '💜', '💖', '💜', '💖', '💜', '💜'],
  magic: ['🎩', '🎩', '🪄', '🪄', '💫', '🐰', '🐰', '🐰', '🐰', '💫'],
  monkeys: ['🙊', '🙊', '🙊', '🙈', '🙈', '🙈', '🙉', '🙉', '🙉'],
  duck: ['💡', '💡', '🦆', '🦆', '🦆', '🦆', '🦆', '💬', '💬', '🦆', '🦆', '💡'],
  hatch: ['🥚', '🥚', '🥚', '🐣', '🐥', '🐥', '🐤', '🐤', '🐥', '🐣'],
  slots: ['🍒', '🔔', '🍋', '🍋', '🍉', '🍉', '🍉', '💎', '💎', '💎', '💎', '💎'],
});

/** Style menu order. */
export const TAB_STYLE_ORDER = Object.freeze(Object.keys(TAB_SPINNERS));
export const DEFAULT_TAB_STYLE = 'braille';

const tabMeta = (name, section, sample, cells, note = null) => ({ name, section, sample, cells, note });

/** frames and cycleSeconds are filled in below from TAB_SPINNERS and TICK_MS. */
export const TAB_STYLE_META = freezeDeep(
  Object.fromEntries(
    Object.entries({
      braille: tabMeta('Braille', 'Glyph', '⠹', 1, 'The default tab spinner.'),
      bounce: tabMeta('Bounce', 'Glyph', '⠂', 1),
      arc: tabMeta('Arc', 'Glyph', '◠', 1),
      equalizer: tabMeta('Equalizer', 'Glyph', '▅', 1),
      sparkle: tabMeta('Sparkle', 'Glyph', '✽', 1,
        `Its ${STAR} frame is the one spinner frame allowed to use Claude's idle mark.`),
      sine: tabMeta('Sine', 'Glyph', '⢄⡠⠊', 3, 'Three braille cells wide.'),
      typing: tabMeta('Typing', 'Glyph', '⡀⠂⡀', 3, 'Three braille cells wide.'),
      snake: tabMeta('Snake', 'Glyph', '▙', 1),
      moon: tabMeta('Moon', 'Emoji', '🌓', 1, 'The style in the README demo.'),
      garden: tabMeta('Garden', 'Emoji', '🌻', 1,
        'Grows with the turn instead of cycling: 🌱 from the start, 🌿 after 1 min, 🌷 after 3 min, 🌻 after 10 min. It keeps growing under Reduce Motion.'),
      heartbeat: tabMeta('Heartbeat', 'Emoji', '💜', 1),
      magic: tabMeta('Magic', 'Emoji', '🐰', 1),
      monkeys: tabMeta('Monkeys', 'Emoji', '🙈', 1),
      duck: tabMeta('Duck', 'Emoji', '🦆', 1),
      hatch: tabMeta('Hatch', 'Emoji', '🐥', 1),
      slots: tabMeta('Slots', 'Emoji', '💎', 1,
        'The reel slows down onto the jackpot instead of strobing six symbols at full speed.'),
    }).map(([key, meta]) => {
      const isGarden = key === 'garden';
      const frames = TAB_SPINNERS[key].length;
      return [key, {
        ...meta,
        key,
        frames: isGarden ? null : frames, // Garden: 4 stages, see TAB_SPINNERS.garden
        stages: isGarden ? frames : null,
        cycleSeconds: isGarden ? null : Math.round(frames * TICK_MS) / 1000,
      }];
    }),
  ),
);

/** Garden's glyph for a turn that has run `secondsIntoTurn` seconds. */
function gardenGlyph(secondsIntoTurn = 0) {
  const s = Number.isFinite(secondsIntoTurn) ? secondsIntoTurn : 0;
  let glyph = TAB_SPINNERS.garden[0][1];
  for (const [after, g] of TAB_SPINNERS.garden) {
    if (s >= after) glyph = g;
  }
  return glyph;
}

/** The still glyph for a style: its Style menu sample, also what a tab holds under Reduce Motion. */
export function sampleGlyph(styleKey) {
  const meta = TAB_STYLE_META[styleKey];
  if (!meta) throw new Error(`Unknown tab style: ${styleKey}`);
  return meta.sample;
}

/**
 * The frame every working tab shows at global tick `tick` (all tabs share one counter: lockstep).
 * Garden ignores the tick and grows with `elapsedSeconds`. Reduce Motion holds the sample,
 * except Garden, which still grows (same order as TabStyle.glyph in the app).
 */
export function frameAt(styleKey, tick, { reducedMotion = false, elapsedSeconds = 0 } = {}) {
  const frames = TAB_SPINNERS[styleKey];
  if (!frames) throw new Error(`Unknown tab style: ${styleKey}`);
  if (styleKey === 'garden') return gardenGlyph(elapsedSeconds);
  if (reducedMotion) return sampleGlyph(styleKey);
  const n = frames.length;
  const i = ((Math.trunc(tick) % n) + n) % n;
  return frames[i];
}

// ---------------------------------------------------------------------------
// Menu bar styles (Styles.swift BarStyle, PillView.swift, BarStar.swift, BarCharacters.swift, BarScenes.swift).
// seconds = main cycle at 1x. cap = the most speed-up the style takes. pinned = never speeds up.

const bar = (name, section, seconds, description, extra = {}) => ({
  name, section, seconds, description, wide: false, cap: null, pinned: false, pinnedParts: [], timings: null, ...extra,
});

export const BAR_STYLES = freezeDeep({
  // Star
  spin: bar('Spin', 'Star', 1.6, `${STAR} rotates one full turn clockwise every 1.6 s.`, { isDefault: true }),
  breathe: bar('Breathe', 'Star', 0.9,
    `${STAR} scales 0.7 to 1.06 and fades 0.55 to 1, back and forth (0.9 s each way, ease in-out).`,
    { timings: { oneWay: 0.9, fullCycle: 1.8 } }),
  hop: bar('Hop', 'Star', 1.1, `${STAR} jumps 4.5 pt, squashes on landing and springs back.`),
  bloom: bar('Bloom', 'Star', 1.2, 'Steps through the Sparkle glyphs, 0.12 s each.'),
  neon: bar('Neon', 'Star', 1.4,
    `Accent ${STAR} with a pulsing glow, plus a neon-tube flicker late in a 3.1 s cycle.`,
    { timings: { glow: 1.4, flicker: 3.1 } }),
  rainbow: bar('Rainbow', 'Star', 3.2,
    `${STAR} turns once per 3.2 s while its color cycles through 8 hues every 2.4 s.`,
    { timings: { turn: 3.2, hues: 2.4 } }),
  morph: bar('Morph', 'Star', 2.4,
    `${STAR} melts into a purple ring and sharpens back, turning an eighth each way.`),
  sketch: bar('Sketch', 'Star', 2.4,
    `A pen nib writes ${STAR} stroke by stroke over a faint tracing, flashes it purple, then erases it.`,
    { cap: 1.3 }),
  // Signal
  orbit: bar('Orbit', 'Signal', 1.4, `${STAR} at 62% size with a dot orbiting it.`),
  comet: bar('Comet', 'Signal', 0.9, 'An 8-dot comet with a bright head and a fading tail, circling.'),
  radar: bar('Radar', 'Signal', 1.6,
    `Half-size ${STAR} sending out 2 sonar rings that grow and fade, half a cycle apart.`),
  wave: bar('Wave', 'Signal', 0.9, 'Three dots bobbing up and down in a staggered wave.'),
  helix: bar('Helix', 'Signal', 1.3, 'Three rungs of dot pairs turning in step like a DNA strand.'),
  equalizer: bar('Equalizer', 'Signal', 0.9, 'Four rounded bars bouncing at different rates.',
    { timings: { bars: [0.9, 0.75, 1.05, 0.85] } }),
  pulse: bar('Pulse', 'Signal', 1.4, 'A heart-monitor trace: a bright stretch runs along a faint copy of the line.',
    { wide: true }),
  scanner: bar('Scanner', 'Signal', 1.3, 'An accent light sweeping back and forth on a faint track, with a 3-dot afterglow.',
    { wide: true }),
  // Playful
  chomp: bar('Chomp', 'Playful', 0.36, 'An accent chomper with an eye, munching along a row of dots, one bite per dot.',
    { wide: true, cap: 1.35 }),
  mochi: bar('Mochi', 'Playful', 1.4, 'A blushing accent mochi that boings, wobbles like jelly and scrunches its eyes on the squish.',
    { cap: 1.35 }),
  kitty: bar('Kitty', 'Playful', 1.3, 'An accent cat head vibing side to side, with a blink and an ear flick every third bop.',
    { timings: { bop: 1.3, loop: 3.9 } }),
  brainstorm: bar('Brainstorm', 'Playful', 2.4, 'A cloud with falling rain; a purple lightning bolt strikes and lights it from inside.',
    { pinned: true }),
  rocket: bar('Rocket', 'Playful', 0.24, 'A rocket climbing up and to the right on a flickering accent flame, speed streaks whipping past.',
    { pinnedParts: ['rumble'], timings: { flame: 0.24, streaks: 0.6, rumble: 0.2 } }),
  cradle: bar('Cradle', 'Playful', 1.2, "Newton's cradle: 5 balls on a bar, the two end balls accent, swinging.",
    { wide: true, cap: 1.35 }),
  prompt: bar('Prompt', 'Playful', 1.9, 'An accent > prompt types four characters, then Enter scrolls the line up and a fresh prompt rises.',
    { wide: true }),
  cube: bar('Cube', 'Playful', 1.2, 'A purple wireframe cube turning in perspective, hidden edges dimmed to 30%, a quarter turn per cycle.'),
});


const DEFAULT_BAR_STYLE = 'spin';

/** Speed up when busy, indexed by Math.min(working, 4): 1 working = 1x, 2 = 1.35x, 3 = 1.6x, 4+ = 1.8x. */
export const SPEED_UP = Object.freeze([1, 1, 1.35, 1.6, 1.8]);

/**
 * Playback rate for a menu bar style (WAAPI updatePlaybackRate). Only the pill speeds up: tab and menu-row
 * spinners always step once per TICK_MS. Pass { part: 'rumble' } for Rocket's pinned rumble.
 */
export function speedFor(workingCount, barStyleKey = DEFAULT_BAR_STYLE, { speedsUp = true, part = null } = {}) {
  const style = BAR_STYLES[barStyleKey];
  if (!style) throw new Error(`Unknown menu bar style: ${barStyleKey}`);
  const n = Math.max(0, Math.min(4, Math.trunc(Number(workingCount) || 0)));
  const rate = speedsUp ? SPEED_UP[n] : 1;
  if (style.pinned || (part && style.pinnedParts.includes(part))) return 1;
  return style.cap ? Math.min(rate, style.cap) : rate;
}

// ---------------------------------------------------------------------------
// Colours (Views.swift Palette, Preview.swift scene).

export const PALETTE = freezeDeep({
  light: {
    accent: '#8a4fd8',
    warn: '#c56a12',
    ok: '#2f8a4f',
    menuBarStrip: 'rgba(246, 245, 249, 0.92)', // #f6f5f9 at 92%
    menuPanel: '#ffffff',
    rocketFlameCore: '#c4a1f5',
  },
  dark: {
    accent: '#c4a1f5',
    warn: '#f0a35e',
    ok: '#7fd59a',
    menuBarStrip: 'rgba(40, 38, 50, 0.92)', // #282632 at 92%
    menuPanel: '#2c2a37',
    rocketFlameCore: 'rgba(255, 255, 255, 0.9)',
  },
  highlight: '#8a4fd8', // menu row hover, both modes
  pillTint: 'rgba(138, 79, 216, 0.18)', // #8a4fd8 at 18%, both modes
  faceInk: '#241240', // eyes and features on accent bodies (Mochi, Kitty, Chomp)
  mochiBlush: 'rgba(255, 111, 168, 0.75)',
  wallpaper: {
    from: '#7b5ea7',
    to: '#2f3e73',
    appAngle: -35, // NSGradient angle (y-up): top left to bottom right
    css: 'linear-gradient(125deg, #7b5ea7, #2f3e73)',
  },
  menuShadow: '0 8px 18px rgba(0, 0, 0, 0.4)',
});

// ---------------------------------------------------------------------------
// Pill (PillView.draw). pt = CSS px at 1x.

/**
 * What the pill shows (product-facts C2). Returns background, star colour role, motion, count and dots.
 * starColor: 'secondary' (grey idle), 'label' (black/white) or 'accent' (Reduce Motion still pose).
 */
export function pillState({ working = 0, waiting = 0, finished = 0, reducedMotion = false, previewing = false } = {}) {
  const lit = working + waiting + finished > 0 || previewing;
  const showing = working > 0 || previewing;
  let starColor = 'secondary';
  if (lit) starColor = showing && reducedMotion ? 'accent' : 'label';
  return {
    background: lit,
    starColor,
    moving: showing && !reducedMotion,
    count: working > 0 ? working : null,
    dots: [...(waiting > 0 ? ['warn'] : []), ...(finished > 0 ? ['ok'] : [])],
    ariaLabel: `TabPulse: ${working} working, ${waiting} need you, ${finished} finished`,
  };
}

// ---------------------------------------------------------------------------
// The menu (StatusApp.menuNeedsUpdate, Views.swift SessionRowView).

const pad2 = (n) => String(n).padStart(2, '0');

/** Running clock for working/waiting rows: m:ss, or XhYm past an hour. */
export function formatClock(seconds) {
  const s = Math.max(0, Math.floor(seconds));
  return s < 3600 ? `${Math.floor(s / 60)}:${pad2(s % 60)}` : `${Math.floor(s / 3600)}h${Math.floor((s % 3600) / 60)}m`;
}

/** Done rows: just now, 2m ago, 3h ago, 1d ago. */
export function formatAgo(seconds) {
  const s = Math.max(0, Math.floor(seconds));
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

/** Row subtitle exactly as the app builds it. state: 'working' | 'waiting' | 'done'. */
export function rowSubtitle(state, detail = '', { isNew = false } = {}) {
  if (state === 'working') return `working · ${detail || 'thinking'}`;
  if (state === 'waiting') return `needs you${detail ? ` · ${detail}` : ''}`;
  return `done${detail.startsWith('stopped') ? ` · ${detail}` : ''}${isNew ? ' · new' : ''}`;
}

export const MENU = freezeDeep({
  width: 330,
  rowHeight: 44,
  header: 'CLAUDE CODE SESSIONS', // real app UI: 11 pt semibold, letter-spaced 0.9
  empty: {
    noSessions: 'No sessions yet. Start claude in a terminal.',
    noHooks: ["Claude Code hooks aren't installed.", 'Run the installer from the README.'],
  },
  ghosttyFooter: {
    allow: 'Allow TabPulse to control Ghostty…', // clickable, opens Automation settings
    tooOld: 'Tab spinners need Ghostty 1.4 or newer',
    ready: 'Click a session to jump to its Ghostty tab',
    notReady: 'Tab spinners work in Ghostty 1.4+',
  },
  awakeFooter: {
    awake: 'Keeping your Mac awake while Claude works',
    lid: 'Keeping your Mac awake, even with the lid closed',
    lidStillOff: 'Lid sleep is still off: sudo pmset -a disablesleep 0',
  },
  jump: { label: 'Jump to the tab that needs you', shortcut: '⌃⌥⌘J' },
  style: {
    label: 'Style',
    tabSpinner: { label: 'Tab spinner', sections: ['Glyph', 'Emoji'] },
    menuBar: { label: 'Menu bar', sections: ['Star', 'Signal', 'Playful'] },
    speedUp: { label: 'Speed up when busy', default: true },
  },
  options: {
    label: 'Options',
    items: [
      { key: 'keepAwake', label: 'Keep Mac awake while Claude works', default: true },
      { key: 'lidAwake', label: 'Keep awake with lid closed…', default: false },
      { separator: true },
      { key: 'waitReminder', label: 'Remind me if a session waits 5 min', default: true },
      { key: 'sounds', label: 'Play sounds', default: false },
      { key: 'jumpShortcut', label: 'Jump shortcut ⌃⌥⌘J', default: true },
    ],
  },
  optionHeld: { version: 'TabPulse 0.2.1', quit: { label: 'Quit TabPulse', shortcut: '⌘Q' } }, // only while holding ⌥
  subtitleExamples: {
    working: ['working · thinking', 'working · running Bash', 'working · workflow review in background'],
    waiting: ['needs you · permission to use Edit'],
    done: ['done', 'done · new', 'done · stopped: rate limit'],
  },
  order: 'needs you first (longest waiting first), then working (longest running first), then done (most recent first)',
  // The README menu picture (menu-*.gif): four rows, Braille spinners, timers counting up.
  readmeRows: [
    { state: 'waiting', title: 'fix the flaky checkout test', subtitle: 'needs you · permission to use Edit', time: '0:48' },
    { state: 'working', title: 'refactor auth middleware', subtitle: 'working · running Bash', time: '3:22' },
    { state: 'working', title: 'write the release notes', subtitle: 'working · thinking', time: '0:51' },
    { state: 'done', title: 'add a dark mode toggle', subtitle: 'done · new', time: '2m ago' },
  ],
  readmeFooter: 'Click a session to jump to its Ghostty tab',
  rowGlyph: { working: 'accent spinner frame', waiting: '●', done: '✓' },
  // Geometry in pt, y down (product-facts C3).
  geometry: {
    padding: 6,
    header: { height: 28, x: 14, size: 11, weight: 600, kern: 0.9 },
    separator: { height: 11, inset: 14 },
    footer: { height: 28, size: 12 },
    row: {
      glyphBox: { x: 9, y: 13, width: 28, height: 18, size: 13, font: 'monospace' },
      title: { x: 42, y: 6, size: 13, maxWidth: 210 },
      subtitle: { x: 42, y: 23, size: 11.5 },
      time: { width: 64, rightInset: 14, y: 14, size: 12, tabularNums: true },
      hover: { insetX: 5, insetY: 1, radius: 6, fill: '#8a4fd8', subtitleAlpha: 0.8 },
    },
    fourRowHeight: 255,
  },
});

// Notification strings (Notifier.swift / StatusApp.swift).
export const NOTIFICATIONS = freezeDeep({
  finished: { title: (tab) => `Finished: ${tab}`, body: (folder, took) => `Claude is done in ${folder} after ${took}` },
  stopped: {
    title: (tab) => `Stopped: ${tab}`,
    body: (folder, took, reason) => `Claude stopped in ${folder} after ${took} (${reason})`,
  },
  stillNeedsYou: {
    title: (tab) => `Still needs you: ${tab}`,
    body: (folder, minutes) =>
      `Claude has been waiting in ${folder} for ${minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} h ${minutes % 60} min`}`,
  },
  finishedDelaySeconds: 10,
  reminderAfterSeconds: 300,
});

export const WAITING_GLYPH = '●'; // U+25CF on the tab (grey) and in the menu (warn)
export const DONE_GLYPH = '✓'; // U+2713, menu only (ok); a done tab gets Claude's own title back

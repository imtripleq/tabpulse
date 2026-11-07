// The hidden-tab trick: while this page's browser tab is in the background, its title spins like a
// TabPulse tab ("⠋ TabPulse"), then after about 20 s it flips to "● TabPulse" as a playful "needs you".
// Coming back restores the original title and favicon.
//
// Browsers throttle timers in hidden tabs to about once a second, so this steps one frame per second,
// about 8x slower than the app's 0.12 s tick. Say "your browser slows hidden tabs; the app doesn't".
// requestAnimationFrame never runs in hidden tabs, so this uses its own setTimeout loop on purpose.
// Safari ignores scripted favicon changes; the title is the trick, the favicon is a Chrome/Firefox bonus.

import { DEFAULT_TAB_STYLE, PALETTE, TAB_SPINNERS, WAITING_GLYPH, frameAt } from './tabpulse-data.js';

const STEP_MS = 1000;
const NEEDS_YOU_AFTER_MS = 20000;
const ICON_PX = 32;
const ICON_RADIUS = 7;
const BRAILLE_START = 0x2800;
const BRAILLE_END = 0x28ff;
// Braille dot bits by [row][column]: dots 1-2-3-7 run down the left column, 4-5-6-8 down the right.
const BRAILLE_BITS = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]];
const GLYPH_FONT = '"TP Glyphs", "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", system-ui, sans-serif';
const REDUCED_MOTION = '(prefers-reduced-motion: reduce)';

let current = null;

const isKnownStyle = (key) => Object.prototype.hasOwnProperty.call(TAB_SPINNERS, key);

const prefersReducedMotion = () => {
  try {
    return window.matchMedia(REDUCED_MOTION).matches;
  } catch {
    return false;
  }
};

const isBraille = (text) =>
  text.length > 0 && [...text].every((c) => {
    const cp = c.codePointAt(0);
    return cp >= BRAILLE_START && cp <= BRAILLE_END;
  });

// ---------------------------------------------------------------------------
// Favicon drawing (canvas, 32 x 32): accent tile, then the frame on top.

function makeCanvas() {
  try {
    const canvas = document.createElement('canvas');
    canvas.width = ICON_PX;
    canvas.height = ICON_PX;
    const ctx = canvas.getContext('2d');
    return ctx ? { canvas, ctx } : null;
  } catch {
    return null;
  }
}

function drawTile(ctx) {
  ctx.clearRect(0, 0, ICON_PX, ICON_PX);
  ctx.fillStyle = PALETTE.light.accent;
  ctx.beginPath();
  if (typeof ctx.roundRect === 'function') ctx.roundRect(0, 0, ICON_PX, ICON_PX, ICON_RADIUS);
  else ctx.rect(0, 0, ICON_PX, ICON_PX);
  ctx.fill();
}

// Braille drawn as dots, so it is crisp at 16 px and needs no font.
function drawBraille(ctx, text) {
  const cells = [...text];
  const cols = cells.length * 2;
  const pad = 5;
  const step = Math.min((ICON_PX - pad * 2) / Math.max(cols - 1, 1), (ICON_PX - pad * 2) / 3, 6.5);
  const radius = Math.max(1.3, step * 0.36);
  const width = step * (cols - 1);
  const x0 = (ICON_PX - width) / 2;
  const y0 = (ICON_PX - step * 3) / 2;
  ctx.fillStyle = '#ffffff';
  cells.forEach((cell, ci) => {
    const bits = cell.codePointAt(0) - BRAILLE_START;
    BRAILLE_BITS.forEach((row, r) => row.forEach((bit, c) => {
      if (!(bits & bit)) return;
      ctx.beginPath();
      ctx.arc(x0 + (ci * 2 + c) * step, y0 + r * step, radius, 0, Math.PI * 2);
      ctx.fill();
    }));
  });
}

function drawNeedsYou(ctx) {
  ctx.fillStyle = PALETTE.dark.warn;
  ctx.beginPath();
  ctx.arc(ICON_PX / 2, ICON_PX / 2, 8, 0, Math.PI * 2);
  ctx.fill();
}

function drawText(ctx, text) {
  ctx.fillStyle = '#ffffff';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = `22px ${GLYPH_FONT}`;
  ctx.fillText(text, ICON_PX / 2, ICON_PX / 2 + 1, ICON_PX - 4);
}

function iconDataURL(state, glyph) {
  if (!state.icon) return null;
  const { canvas, ctx } = state.icon;
  drawTile(ctx);
  if (glyph === WAITING_GLYPH) drawNeedsYou(ctx);
  else if (isBraille(glyph)) drawBraille(ctx, glyph);
  else drawText(ctx, glyph);
  try {
    return canvas.toDataURL('image/png');
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Save, show and restore

function saveOriginals(state) {
  state.savedTitle = document.title;
  state.savedIcons = [...document.querySelectorAll('link[rel~="icon"]')].map((el) => ({
    el, href: el.getAttribute('href'),
  }));
}

function setIcon(state, href) {
  if (!state.favicon || !href) return;
  if (state.savedIcons.length === 0 && !state.tempIcon) {
    state.tempIcon = document.createElement('link');
    state.tempIcon.rel = 'icon';
    document.head.appendChild(state.tempIcon);
  }
  if (state.tempIcon) state.tempIcon.href = href;
  state.savedIcons.forEach(({ el }) => el.setAttribute('href', href));
}

function show(state, glyph) {
  if (glyph === state.lastGlyph) return;
  state.lastGlyph = glyph;
  document.title = `${glyph} ${state.label}`;
  if (state.favicon) setIcon(state, iconDataURL(state, glyph));
}

function restore(state) {
  clearTimeout(state.timer);
  state.timer = 0;
  if (!state.running) return;
  state.running = false;
  state.lastGlyph = null;
  document.title = state.savedTitle;
  state.savedIcons.forEach(({ el, href }) => {
    if (href === null) el.removeAttribute('href');
    else el.setAttribute('href', href);
  });
  if (state.tempIcon) {
    state.tempIcon.remove();
    state.tempIcon = null;
  }
}

// ---------------------------------------------------------------------------
// The hidden-tab loop

function step(state) {
  state.timer = 0;
  if (!state.running || !document.hidden) return;
  const hiddenMs = Date.now() - state.hiddenAt;
  if (Number.isFinite(state.needsYouAfterMs) && hiddenMs >= state.needsYouAfterMs) {
    show(state, WAITING_GLYPH); // stays put until the tab is visible again
    return;
  }
  // Reduce Motion holds the style's sample (Garden still grows), exactly like the app.
  show(state, frameAt(state.styleKey, state.tick, {
    reducedMotion: prefersReducedMotion(),
    elapsedSeconds: hiddenMs / 1000,
  }));
  state.tick += 1;
  state.timer = setTimeout(() => step(state), state.stepMs);
}

function start(state) {
  if (state.running) return;
  saveOriginals(state);
  state.running = true;
  state.tick = 0;
  state.hiddenAt = Date.now();
  if (state.favicon && document.fonts && typeof document.fonts.load === 'function') {
    document.fonts.load(`16px ${GLYPH_FONT}`, '⠋▁◜✢').catch(() => {});
  }
  step(state);
}

function onVisibility(state) {
  if (document.hidden) start(state);
  else restore(state);
}

/**
 * Start the hidden-tab title spinner. Safe to call again: the previous one is torn down.
 * @param {{ styleKey?: string, label?: string, favicon?: boolean, stepMs?: number, needsYouAfterMs?: number }} [options]
 * @returns {{ setStyle: (key: string) => boolean, destroy: () => void }}
 */
export function initTabTitle({
  styleKey = DEFAULT_TAB_STYLE, label = 'TabPulse', favicon = true,
  stepMs = STEP_MS, needsYouAfterMs = NEEDS_YOU_AFTER_MS,
} = {}) {
  destroyTabTitle();
  const state = {
    styleKey: isKnownStyle(styleKey) ? styleKey : DEFAULT_TAB_STYLE,
    label: String(label),
    favicon: Boolean(favicon),
    stepMs: Math.max(250, Number(stepMs) || STEP_MS),
    needsYouAfterMs: Number(needsYouAfterMs),
    icon: favicon ? makeCanvas() : null,
    running: false,
    timer: 0,
    tick: 0,
    hiddenAt: 0,
    lastGlyph: null,
    savedTitle: '',
    savedIcons: [],
    tempIcon: null,
  };
  state.listener = () => onVisibility(state);
  document.addEventListener('visibilitychange', state.listener);
  current = state;
  if (document.hidden) start(state);
  return { setStyle: setTabTitleStyle, destroy: destroyTabTitle };
}

/** Change the style the hidden tab steps through (for example when a visitor picks one). */
export function setTabTitleStyle(styleKey) {
  if (!current || !isKnownStyle(styleKey)) return false;
  current.styleKey = styleKey;
  current.lastGlyph = null;
  return true;
}

/** Stop listening and put the original title and favicon back. */
export function destroyTabTitle() {
  if (!current) return;
  document.removeEventListener('visibilitychange', current.listener);
  restore(current);
  current = null;
}

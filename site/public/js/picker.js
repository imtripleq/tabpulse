// The spinner sheet: all 16 tab spinners in the app's Glyph and Emoji groups. Each cell is one button with
// its name, its glyph live and large (in lockstep with every other spinner on the page), every frame as a
// strip with the current one marked, its cycle time and one line about it. The sheet is a radio group: the
// style in use is checked. Nodes are built once; a tick
// only moves the "now" class and flips the specimen's parts. The sheet ticks only while it is on screen.

import { TAB_SPINNERS, TAB_STYLE_META, TAB_STYLE_ORDER } from '../assets/tabpulse-data.js';
import { buildSpecimen } from './specimen.js';
import { el } from './mocks.js';
import { createRegion, onFrame, onRuntimeChange, onTick, runtime } from './runtime.js';

// One true line each, checked against the frame data and product-facts.
const CAPTIONS = Object.freeze({
  braille: 'The default. A short trail of dots runs clockwise around the cell.',
  bounce: 'One dot visits all eight seats: down the left side, up the right.',
  arc: 'Six arcs, two of them halves, roll around a circle.',
  equalizer: 'One bar climbs all eight steps and comes back down.',
  sparkle: 'A dot blooms through five stars and folds back down.',
  sine: 'Three cells wide. The wave slides left one cell every two frames.',
  typing: 'Three cells wide. Each dot hops up in turn, like someone typing.',
  snake: 'A snake of quarter blocks grows, crawls clockwise and shrinks.',
  moon: 'A whole lunar month every 0.96\u00A0s. The style in the README demo.',
  garden: 'Doesn’t spin. It grows with the turn, and keeps growing with Reduce Motion on.',
  heartbeat: 'Two quick beats, then a rest.',
  magic: 'Hat, wand, sparkle, rabbit. The rabbit holds for four frames.',
  monkeys: 'Speak no, see no, hear no. Three ticks each.',
  duck: 'Rubber duck debugging. The duck gets 7 of the 12 frames.',
  hatch: 'Hatches, grows up, then climbs back into the egg.',
  slots: 'Slows down onto the jackpot instead of strobing, then holds it.',
});

const GARDEN_AT = Object.freeze(['0 min', '1 min', '3 min', '10 min']);
const ROW_SLOP = 8; // px: cells whose tops differ by less than this sit on the same row

const framesOf = (key) => (key === 'garden' ? TAB_SPINNERS.garden.map(([, g]) => g) : [...TAB_SPINNERS[key]]);

function timeLabel(key) {
  const meta = TAB_STYLE_META[key];
  return key === 'garden' ? 'over 10\u00A0min' : `${meta.cycleSeconds.toFixed(2)}\u00A0s`;
}

function detail(key) {
  const meta = TAB_STYLE_META[key];
  if (key === 'garden') return ' Four stages, the last one after 10 minutes.';
  return ` ${meta.frames} frames, ${meta.cycleSeconds.toFixed(2)} seconds a turn.`;
}

function gardenStage(seconds) {
  let stage = 0;
  TAB_SPINNERS.garden.forEach(([after], i) => { if (seconds >= after) stage = i; });
  return stage;
}

function buildStrip(key, frames) {
  const meta = TAB_STYLE_META[key];
  const strip = el('span', 'cell-strip');
  strip.setAttribute('aria-hidden', 'true');
  // Three-cell frames are wide, so their strip folds onto two rows instead of shrinking the type.
  const cols = meta.cells > 1 ? Math.ceil(frames.length / 2) : frames.length;
  strip.style.setProperty('--cols', String(cols));
  let fw = meta.section === 'Emoji' ? 1.2 : 0.6 * meta.cells;
  if (key === 'garden') fw = 3.2; // room for the time under each stage
  strip.style.setProperty('--fw', String(fw));
  const nodes = frames.map((glyph, i) => {
    const f = el('span', 'f');
    if (key === 'garden') f.append(el('span', 'f-g', glyph), el('span', 'f-at', GARDEN_AT[i]));
    else f.textContent = glyph;
    strip.append(f);
    return f;
  });
  return { strip, nodes };
}

function buildCell(key) {
  const meta = TAB_STYLE_META[key];
  const frames = framesOf(key);
  const spec = buildSpecimen(key);
  const b = el('button', 'cell');
  b.type = 'button';
  b.tabIndex = -1;
  b.dataset.key = key;
  b.dataset.kind = spec.kind;
  b.dataset.cells = String(meta.cells);
  b.setAttribute('role', 'radio');
  b.setAttribute('aria-label', meta.name);
  b.setAttribute('aria-checked', 'false');
  b.setAttribute('aria-describedby', `cap-${key} sheet-keys`);

  const head = el('span', 'cell-head');
  const on = el('span', 'cell-on', 'In use');
  on.setAttribute('aria-hidden', 'true');
  head.append(el('span', 'cell-name', meta.name), on, el('span', 'cell-time', timeLabel(key)));

  const specBox = el('span', 'cell-spec');
  specBox.append(spec.svg);
  const { strip, nodes } = buildStrip(key, frames);

  const cap = el('span', 'cell-cap', CAPTIONS[key]);
  cap.id = `cap-${key}`;
  cap.append(el('span', 'sr-only', detail(key)));

  b.append(head, specBox, strip, cap);
  const still = Math.max(0, frames.indexOf(meta.sample));
  return { key, b, spec, frames, nodes, still, now: -1 };
}

/** Arrow-key target: the nearest cell on the next row up or down, by horizontal centre. */
function rowNeighbour(cells, from, down) {
  const r = from.b.getBoundingClientRect();
  const mid = r.left + r.width / 2;
  const rects = cells.map((c) => ({ c, r: c.b.getBoundingClientRect() }));
  const ahead = rects.filter(({ r: q }) => (down ? q.top > r.top + ROW_SLOP : q.top < r.top - ROW_SLOP));
  if (!ahead.length) return null;
  const rowTop = down ? Math.min(...ahead.map(({ r: q }) => q.top)) : Math.max(...ahead.map(({ r: q }) => q.top));
  const row = ahead.filter(({ r: q }) => Math.abs(q.top - rowTop) < ROW_SLOP);
  row.sort((a, b) => Math.abs(a.r.left + a.r.width / 2 - mid) - Math.abs(b.r.left + b.r.width / 2 - mid));
  return row[0].c;
}

/** A radio group: one tab stop on the style in use; arrows, Home and End move to a style and put it on. */
function initKeys(sheet, cells, onChoose) {
  const stop = (cell) => cells.forEach((c) => { c.b.tabIndex = c === cell ? 0 : -1; });
  cells.forEach((c) => c.b.addEventListener('focus', () => stop(c)));
  sheet.addEventListener('keydown', (e) => {
    const i = cells.findIndex((c) => c.b === e.target);
    if (i < 0 || e.altKey || e.ctrlKey || e.metaKey) return;
    let next = null;
    if (e.key === 'ArrowRight') next = cells[i + 1];
    else if (e.key === 'ArrowLeft') next = cells[i - 1];
    else if (e.key === 'Home') next = cells[0];
    else if (e.key === 'End') next = cells[cells.length - 1];
    else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') next = rowNeighbour(cells, cells[i], e.key === 'ArrowDown');
    else return;
    e.preventDefault();
    if (!next) return;
    next.b.focus();
    onChoose(next.key);
  });
  return stop;
}

/**
 * Builds the sheet into each [data-section] group inside `sheet`.
 * @param {HTMLElement} sheet
 * @param {{ onChoose: (key: string) => void }} options
 * @returns {{ setPressed: (key: string) => void } | null}
 */
export function initPicker(sheet, { onChoose }) {
  const groups = [...sheet.querySelectorAll('[data-section]')];
  if (!groups.length) return null;
  const cells = [];
  groups.forEach((group) => {
    TAB_STYLE_ORDER.filter((k) => TAB_STYLE_META[k].section === group.dataset.section).forEach((key) => {
      const cell = buildCell(key);
      cell.b.addEventListener('click', () => onChoose(key));
      group.append(cell.b);
      cells.push(cell);
    });
  });
  const setStop = initKeys(sheet, cells, onChoose);

  // Garden grows with time on the page, like a turn that started when you arrived.
  let seconds = 0;
  onFrame((dt) => { seconds += dt / 1000; });

  const region = createRegion(sheet, { rootMargin: '120px 0px' });
  const frameIndex = (c, tick) => {
    if (c.key === 'garden') return gardenStage(seconds);
    if (runtime.reduced) return c.still;
    return ((tick % c.frames.length) + c.frames.length) % c.frames.length;
  };
  const render = (tick, force = false) => {
    if (!force && !region.active) return;
    cells.forEach((c) => {
      const i = frameIndex(c, tick);
      if (i === c.now) return;
      if (c.now >= 0) c.nodes[c.now].classList.remove('is-now');
      c.nodes[i].classList.add('is-now');
      c.spec.set(c.frames[i]);
      c.now = i;
    });
  };
  onTick((tick) => render(tick));
  onRuntimeChange((key) => { if (key === 'reduced') render(runtime.tick, true); });
  render(runtime.tick, true);

  const setPressed = (key) => {
    cells.forEach((c) => c.b.setAttribute('aria-checked', String(c.key === key)));
    const picked = cells.find((c) => c.key === key);
    if (picked && !sheet.contains(document.activeElement)) setStop(picked);
  };
  setPressed(runtime.tabStyle);
  return { setPressed };
}

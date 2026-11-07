// DOM builders for the product mocks: spinner glyphs, Ghostty windows, the pill, the TabPulse menu, banners.
// Everything is built with createElement and textContent (CSP: no inline styles or HTML strings).

import {
  DONE_GLYPH, MENU, WAITING_GLYPH, frameAt, pillState, speedFor,
} from '../assets/tabpulse-data.js';
import { starSVG } from '../assets/star.js';
import { onFrame, onRuntimeChange, onTick, runtime, trackAnimation } from './runtime.js';

const ROW_MOVE_MS = 420;
const SPIN_MS = 1600;

/** createElement with a class and text. */
export function el(tag, className = '', text = '') {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
}

/** A line of terminal text: a string, or [[className, text], ...] segments. */
function lineNode(line) {
  const p = el('p');
  if (typeof line === 'string') {
    p.textContent = line || ' ';
    return p;
  }
  line.forEach(([cls, text]) => p.append(cls ? el('span', cls, text) : document.createTextNode(text)));
  return p;
}

// ---------------------------------------------------------------------------
// Spinners: every glyph on the page reads the same global tick.

const spinners = new Set();
let sceneSeconds = 0;
onFrame((dt) => { sceneSeconds += dt / 1000; });

function glyphFor(s, tick) {
  if (s.state === 'waiting') return WAITING_GLYPH;
  if (s.state === 'done') return s.kind === 'row' ? DONE_GLYPH : '';
  return frameAt(runtime.tabStyle, tick, {
    reducedMotion: runtime.reduced,
    elapsedSeconds: s.baseSeconds + sceneSeconds,
  });
}

function paint(s, tick, force = false) {
  if (!force && s.region && !s.region.active) return;
  const glyph = glyphFor(s, tick);
  if (glyph === s.last) return;
  s.last = glyph;
  s.node.textContent = glyph;
}

onTick((tick) => spinners.forEach((s) => paint(s, tick)));
onRuntimeChange(() => spinners.forEach((s) => paint(s, runtime.tick, true)));

/**
 * A spinner glyph box. kind 'tab' (grey, done = blank) or 'row' (menu row, done = ✓).
 * @returns {{ node: HTMLElement, set: (state: string) => void, destroy: () => void }}
 */
export function spinner({ region = null, kind = 'tab', state = 'working', baseSeconds = 0 } = {}) {
  const node = el('span', 'glyph');
  node.setAttribute('aria-hidden', 'true');
  const s = { node, region, kind, state, baseSeconds, last: null };
  spinners.add(s);
  paint(s, runtime.tick, true);
  return {
    node,
    get state() { return s.state; },
    set(next) {
      if (next === s.state) return;
      s.state = next;
      paint(s, runtime.tick, true);
    },
    destroy() { spinners.delete(s); },
  };
}

// ---------------------------------------------------------------------------
// Ghostty window

/**
 * @param {{ tabs: {title: string, state: string, base?: number}[], selected?: number, focused?: boolean,
 *   region?: object, keys?: boolean, body?: Array }} options
 */
export function ghostty({ tabs, selected = 0, focused = false, region = null, keys = false, body = [] }) {
  const root = el('div', 'gw');
  const titlebar = el('div', 'gw-titlebar');
  const lights = el('span', 'gw-lights');
  for (let i = 0; i < 3; i += 1) lights.append(el('span', 'gw-light'));
  const title = el('span', 'gw-title');
  const titleGlyph = spinner({ region, state: 'working' });
  const titleText = el('span', 'gw-title-text');
  title.append(titleGlyph.node, titleText);
  titlebar.append(lights, title);

  const trackrow = el('div', 'gw-trackrow');
  const track = el('div', 'gw-track');
  const plus = el('span', 'gw-plus');
  trackrow.append(track, plus);
  const bodyEl = el('div', 'gw-body');
  root.append(titlebar, trackrow, bodyEl);

  const model = tabs.map((t) => ({ ...t }));
  const views = model.map((t, i) => {
    const tab = el('div', `gw-tab${keys ? ' has-key' : ''}`);
    const inner = el('div', 'gw-tab-in');
    const glyph = spinner({ region, state: t.state, baseSeconds: t.base || 0 });
    const label = el('span', 'gw-tab-title', t.title);
    inner.append(glyph.node, label);
    tab.append(inner);
    if (keys) tab.append(el('span', 'gw-tab-key', `⌘${i + 1}`));
    tab.classList.toggle('is-done', t.state === 'done');
    track.append(tab);
    return { tab, glyph, label };
  });

  let current = selected;
  const syncTitle = () => {
    const t = model[current];
    titleText.textContent = t.title;
    titleGlyph.set(t.state);
    title.classList.toggle('is-done', t.state === 'done');
    titleGlyph.node.hidden = t.state === 'done';
  };

  const api = {
    root,
    get selected() { return current; },
    tabEl: (i) => views[i].tab,
    select(i) {
      views[current].tab.classList.remove('is-selected');
      current = i;
      views[current].tab.classList.add('is-selected');
      syncTitle();
    },
    setTab(i, patch) {
      Object.assign(model[i], patch);
      if (patch.state) {
        views[i].glyph.set(patch.state);
        views[i].tab.classList.toggle('is-done', patch.state === 'done');
      }
      if (patch.title) views[i].label.textContent = patch.title;
      if (i === current) syncTitle();
    },
    flag(i, on) { views[i].tab.classList.toggle('is-flagged', Boolean(on)); },
    setFocused(on) { root.classList.toggle('is-focused', Boolean(on)); },
    setBody(lines) { bodyEl.replaceChildren(...lines.map(lineNode)); },
    destroy() {
      titleGlyph.destroy();
      views.forEach((v) => v.glyph.destroy());
    },
  };
  api.select(selected);
  api.setFocused(focused);
  api.setBody(body);
  return api;
}

// ---------------------------------------------------------------------------
// The pill

export function pill() {
  const root = el('span', 'pill');
  const mark = el('span', 'pill-mark');
  const svg = starSVG();
  mark.append(svg);
  const count = el('span', 'pill-count');
  root.append(mark, count);
  let counts = { working: 0, waiting: 0, finished: 0 };
  let anim = null;
  let dotKinds = '';

  const syncDots = (dots) => {
    const key = dots.join(',');
    if (key === dotKinds) return;
    root.querySelectorAll('.pill-dot').forEach((d) => d.remove());
    dots.forEach((kind) => root.append(el('span', `pill-dot pill-dot--${kind}`)));
    dotKinds = key;
  };

  const apply = () => {
    const p = pillState({ ...counts, reducedMotion: runtime.reduced });
    root.classList.toggle('is-lit', p.background);
    root.dataset.star = p.starColor;
    count.textContent = p.count === null ? '' : String(p.count);
    syncDots(p.dots);
    if (p.moving) {
      if (!anim && typeof svg.animate === 'function') {
        anim = trackAnimation(svg.animate(
          [{ transform: 'rotate(0deg)' }, { transform: 'rotate(360deg)' }],
          { duration: SPIN_MS, iterations: Infinity, easing: 'linear' },
        ));
      }
      if (anim) anim.updatePlaybackRate(speedFor(counts.working));
    } else if (anim) {
      anim.cancel();
      anim = null;
    }
  };

  onRuntimeChange((key) => { if (key === 'reduced') apply(); });
  apply();
  return {
    el: root,
    get counts() { return counts; },
    set(next) {
      counts = { ...counts, ...next };
      apply();
    },
  };
}

// ---------------------------------------------------------------------------
// The TabPulse menu

/** A menu row node: { id, state, title, detail, isNew, time }. */
function rowView(row, region) {
  const node = el('div', 'tprow');
  const glyphBox = el('span', 'tprow-glyph');
  const glyph = spinner({ region, kind: 'row', state: row.state });
  glyphBox.append(glyph.node);
  const title = el('span', 'tprow-title');
  const sub = el('span', 'tprow-sub');
  const time = el('span', 'tprow-time');
  node.append(glyphBox, title, sub, time);
  return { node, glyph, title, sub, time };
}

export function menu({ region = null, footers = [] } = {}) {
  const root = el('div', 'tpmenu');
  const head = el('div', 'tpmenu-head', MENU.header);
  const list = el('div', 'tpmenu-rows');
  const sep = el('div', 'tpmenu-sep');
  const footA = el('div', 'tpmenu-foot');
  const footB = el('div', 'tpmenu-foot');
  root.append(head, list, sep, footA, footB);
  const views = new Map();

  const fill = (v, row) => {
    v.node.dataset.state = row.state;
    v.glyph.set(row.state);
    v.title.textContent = row.title;
    v.sub.textContent = row.sub;
    v.time.textContent = row.time;
  };

  const api = {
    root,
    /** Replace the rows (already sorted). Rows that stay slide to their new place. */
    setRows(rows, { animate = true } = {}) {
      const before = new Map();
      if (animate && !runtime.reduced) views.forEach((v, id) => before.set(id, v.node.offsetTop));
      const keep = new Set(rows.map((r) => r.id));
      views.forEach((v, id) => {
        if (keep.has(id)) return;
        v.glyph.destroy();
        v.node.remove();
        views.delete(id);
      });
      rows.forEach((row) => {
        let v = views.get(row.id);
        if (!v) {
          v = rowView(row, region);
          views.set(row.id, v);
        }
        fill(v, row);
        list.append(v.node);
      });
      if (!before.size) return;
      views.forEach((v, id) => {
        if (!before.has(id)) return;
        const delta = before.get(id) - v.node.offsetTop;
        if (!delta || typeof v.node.animate !== 'function') return;
        trackAnimation(v.node.animate(
          [{ transform: `translateY(${delta}px)` }, { transform: 'translateY(0)' }],
          { duration: ROW_MOVE_MS, easing: 'cubic-bezier(0.22, 1, 0.36, 1)' },
        ));
      });
    },
    setTime(id, text) {
      const v = views.get(id);
      if (v && v.time.textContent !== text) v.time.textContent = text;
    },
    setFooters([a = '', b = ''] = []) {
      footA.textContent = a;
      footB.textContent = b;
    },
    setOpen(open) { root.classList.toggle('is-closed', !open); },
    hover(id) { views.forEach((v, key) => v.node.classList.toggle('is-hover', key === id)); },
    destroy() { views.forEach((v) => v.glyph.destroy()); },
  };
  api.setFooters(footers);
  return api;
}

// ---------------------------------------------------------------------------
// macOS banner

export function banner({ title, body, time = 'now' }) {
  const root = el('div', 'notif');
  const icon = el('img');
  icon.src = './assets/app-icon-64.png';
  icon.alt = '';
  icon.width = 32;
  icon.height = 32;
  root.append(icon, el('span', 'notif-title', title), el('span', 'notif-time', time), el('span', 'notif-body', body));
  return root;
}

/** Text with ⌃⌥⌘J set in the key face: segments are strings, or { kbd: '…' }. */
export function richText(node, segments) {
  node.replaceChildren(...segments.map((s) => (typeof s === 'string' ? document.createTextNode(s) : el('span', 'kbd-inline', s.kbd))));
}

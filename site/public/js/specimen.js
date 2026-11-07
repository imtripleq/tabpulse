// Specimen renderers: each tab spinner glyph drawn large, as what it is made of.
// Braille becomes a grid of dots, quadrant blocks become squares, eighth blocks a bar of steps, arcs a stroke
// on a faint circle. Lit parts take the accent, unlit parts are faint rings. Sparkle and the emoji stay type.
// Each builder makes its nodes once; set(glyph) only flips classes or one attribute, so a tick is cheap.

import { TAB_STYLE_META } from '../assets/tabpulse-data.js';

const NS = 'http://www.w3.org/2000/svg';

// Braille dot bits by [row][column] (dots 1-2-3-7 on the left, 4-5-6-8 on the right).
const BRAILLE_BITS = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]];
const DOT = { r: 3.4, pitch: 10, cellGap: 6 };

// Quadrants [upper left, upper right, lower left, lower right].
const QUADRANTS = {
  '▘': [1, 0, 0, 0], '▝': [0, 1, 0, 0], '▖': [0, 0, 1, 0], '▗': [0, 0, 0, 1],
  '▀': [1, 1, 0, 0], '▄': [0, 0, 1, 1], '▌': [1, 0, 1, 0], '▐': [0, 1, 0, 1],
  '▜': [1, 1, 0, 1], '▟': [0, 1, 1, 1], '▙': [1, 0, 1, 1], '▛': [1, 1, 1, 0],
  '█': [1, 1, 1, 1],
};
const EIGHTHS = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
// Arcs as [start, end] in degrees, clockwise from 3 o'clock (SVG y runs down).
const ARCS = { '◜': [180, 270], '◠': [180, 360], '◝': [270, 360], '◞': [0, 90], '◡': [0, 180], '◟': [90, 180] };

const BRAILLE_STYLES = new Set(['braille', 'bounce', 'sine', 'typing']);

/** How a style is drawn: 'braille', 'quadrant', 'eighth', 'arc', 'emoji' or 'text'. */
function specimenKind(styleKey) {
  if (BRAILLE_STYLES.has(styleKey)) return 'braille';
  if (styleKey === 'snake') return 'quadrant';
  if (styleKey === 'equalizer') return 'eighth';
  if (styleKey === 'arc') return 'arc';
  return TAB_STYLE_META[styleKey].section === 'Emoji' ? 'emoji' : 'text';
}

function svgEl(tag, attrs = {}, parent = null) {
  const node = document.createElementNS(NS, tag);
  Object.entries(attrs).forEach(([k, v]) => node.setAttribute(k, String(v)));
  if (parent) parent.append(node);
  return node;
}

const makeSvg = (w, h, kind) => svgEl('svg', {
  viewBox: `0 0 ${w} ${h}`,
  class: `spec spec-${kind}`,
  preserveAspectRatio: 'xMinYMid meet',
  'aria-hidden': 'true',
  focusable: 'false',
});

function brailleBuilder(cells) {
  const { r, pitch, cellGap } = DOT;
  const x = (c) => r + c * pitch + Math.floor(c / 2) * cellGap;
  const svg = makeSvg(x(cells * 2 - 1) + r, r * 2 + pitch * 3, 'braille');
  const dots = [];
  for (let cell = 0; cell < cells; cell += 1) {
    for (let row = 0; row < 4; row += 1) {
      for (let col = 0; col < 2; col += 1) {
        const c = svgEl('circle', { cx: x(cell * 2 + col), cy: r + row * pitch, r, class: 'dot' }, svg);
        dots.push({ c, cell, bit: BRAILLE_BITS[row][col] });
      }
    }
  }
  const set = (glyph) => {
    const codes = [...glyph].map((ch) => ch.codePointAt(0) - 0x2800);
    dots.forEach((d) => d.c.classList.toggle('on', ((codes[d.cell] ?? 0) & d.bit) !== 0));
  };
  return { svg, set };
}

function quadrantBuilder() {
  const w = 12; const h = 22; const gap = 0.7;
  const svg = makeSvg(w, h, 'quad');
  const rects = [[0, 0], [1, 0], [0, 1], [1, 1]].map(([cx, cy]) => svgEl('rect', {
    x: cx * (w / 2) + gap / 2, y: cy * (h / 2) + gap / 2, width: w / 2 - gap, height: h / 2 - gap, class: 'part',
  }, svg));
  const set = (glyph) => {
    const q = QUADRANTS[glyph] || [0, 0, 0, 0];
    rects.forEach((rect, i) => rect.classList.toggle('on', q[i] === 1));
  };
  return { svg, set };
}

function eighthBuilder() {
  const w = 12; const h = 22; const gap = 0.45; const step = h / 8;
  const svg = makeSvg(w, h, 'eighth');
  // Eight steps, each its own rect, so the unlit ones read as an empty scale.
  const steps = Array.from({ length: 8 }, (_, i) => svgEl('rect', {
    x: 0.5, y: h - (i + 1) * step + gap / 2, width: w - 1, height: step - gap, class: 'part',
  }, svg));
  const set = (glyph) => {
    const level = EIGHTHS.indexOf(glyph) + 1;
    steps.forEach((s, i) => s.classList.toggle('on', i < level));
  };
  return { svg, set };
}

function arcPath(c, r, a0, a1) {
  const p = (a) => [c + r * Math.cos((a * Math.PI) / 180), c + r * Math.sin((a * Math.PI) / 180)];
  const [x0, y0] = p(a0);
  const [x1, y1] = p(a1);
  return `M${x0.toFixed(3)} ${y0.toFixed(3)}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1.toFixed(3)} ${y1.toFixed(3)}`;
}

function arcBuilder() {
  const s = 24; const r = 9.5;
  const svg = makeSvg(s, s, 'arc');
  svgEl('circle', { cx: s / 2, cy: s / 2, r, class: 'ring' }, svg);
  const arc = svgEl('path', { class: 'arc' }, svg);
  const paths = Object.fromEntries(Object.entries(ARCS).map(([g, [a0, a1]]) => [g, arcPath(s / 2, r, a0, a1)]));
  const set = (glyph) => arc.setAttribute('d', paths[glyph] || '');
  return { svg, set };
}

function textBuilder(kind) {
  const emoji = kind === 'emoji';
  const w = emoji ? 24 : 14; const h = emoji ? 24 : 22;
  const svg = makeSvg(w, h, kind);
  const text = svgEl('text', {
    x: w / 2,
    y: emoji ? h / 2 : 17.4,
    'text-anchor': 'middle',
    'dominant-baseline': emoji ? 'central' : 'auto',
    'font-size': emoji ? 17 : 20,
    class: 'glyph',
  }, svg);
  const set = (glyph) => { if (text.textContent !== glyph) text.textContent = glyph; };
  return { svg, set };
}

/** A specimen for one style: { svg, set(glyph), kind }. */
export function buildSpecimen(styleKey) {
  const kind = specimenKind(styleKey);
  let built;
  if (kind === 'braille') built = brailleBuilder(TAB_STYLE_META[styleKey].cells);
  else if (kind === 'quadrant') built = quadrantBuilder();
  else if (kind === 'eighth') built = eighthBuilder();
  else if (kind === 'arc') built = arcBuilder();
  else built = textBuilder(kind);
  return { ...built, kind };
}

// Eight live menu bar marks, drawn from the app's PillView timings, and the Speed up when busy control.
// Speed-up only changes these marks' playback rate (WAAPI updatePlaybackRate keeps each one where it is
// in its cycle, like the app's layer retiming). Tab spinners never speed up.

import {
  BAR_STYLES, SPEED_UP, TAB_SPINNERS, TICK_MS, sampleGlyph, speedFor,
} from '../assets/tabpulse-data.js';
import { starSVG } from '../assets/star.js';
import { el } from './mocks.js';
import { createRegion, onFrame, onRuntimeChange, runtime } from './runtime.js';

const SVG_NS = 'http://www.w3.org/2000/svg';
const BAR_SAMPLES = ['spin', 'breathe', 'hop', 'bloom', 'orbit', 'radar', 'wave', 'equalizer'];
// PillView.swift Equalizer: scaleY levels per bar, per-bar cycle, centred at x 1.7 / 4.9 / 8.1 / 11.3
const EQ_LEVELS = [[0.3, 1, 0.5, 0.8, 0.3], [0.75, 0.35, 1, 0.45, 0.75], [0.5, 0.9, 0.3, 1, 0.5], [0.9, 0.4, 0.7, 0.3, 0.9]];
const EQ_SECONDS = [0.9, 0.75, 1.05, 0.85];
const EQ_X = [1.7, 4.9, 8.1, 11.3];
const BLOOM_FRAMES = TAB_SPINNERS.sparkle; // Bloom steps through the Sparkle glyphs, 0.12 s each at 1x

function ring() {
  const svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('viewBox', '0 0 13 13');
  svg.setAttribute('class', 'bs-ring');
  svg.setAttribute('aria-hidden', 'true');
  const c = document.createElementNS(SVG_NS, 'circle');
  [['cx', '6.5'], ['cy', '6.5'], ['r', '5.8'], ['fill', 'none'], ['stroke', 'currentColor'], ['stroke-width', '1.2']]
    .forEach(([k, v]) => c.setAttribute(k, v));
  svg.append(c);
  return svg;
}

function barMark(key) {
  const mark = el('span', 'pill-mark');
  if (key === 'spin' || key === 'breathe' || key === 'hop') mark.append(starSVG());
  if (key === 'orbit') mark.append(starSVG(), el('span', 'bs-orbit-arm'));
  if (key === 'radar') mark.append(starSVG({ className: 'bs-star' }), ring(), ring());
  if (key === 'wave') for (let i = 0; i < 3; i += 1) mark.append(el('span', 'bs-dot'));
  if (key === 'equalizer') {
    EQ_X.forEach((x, i) => {
      const bar = el('span', 'bs-bar');
      bar.style.left = `${x - 1.1}px`;
      bar.style.setProperty('--still', String(EQ_LEVELS[i][1]));
      bar.style.setProperty('--eq', `bs-eq${i}`);
      bar.style.setProperty('--dur', `${EQ_SECONDS[i]}s`);
      mark.append(bar);
    });
  }
  return mark;
}

const fmtRate = (r) => `${Number(r.toFixed(2))}x`;

/** The line under the control. These eight marks have no cap, so the rate is the app's table value. */
function readout(working, speedsUp) {
  const who = working >= 4 ? '4 or more working' : `${working} working`;
  if (!speedsUp) return `${who}. Speed up when busy is off, so the marks stay at 1x.`;
  const rate = SPEED_UP[Math.min(4, working)];
  if (rate === 1) return `${who}: the marks run at their base speed, 1x.`;
  return `${who}: the marks run at ${fmtRate(rate)}.`;
}

/**
 * @param {HTMLElement|null} host  the sample grid
 * @param {{ toggle?: HTMLInputElement|null, radios?: HTMLInputElement[], out?: HTMLElement|null }} controls
 */
export function initMarks(host, { toggle = null, radios = [], out = null } = {}) {
  if (!host) return;
  let working = 1;
  let speedsUp = toggle ? toggle.checked : true;

  const samples = BAR_SAMPLES.map((key) => {
    const cell = el('div', 'bar-cell');
    const pill = el('span', `pill is-lit bs bs-${key}`);
    pill.dataset.star = runtime.reduced ? 'accent' : 'label';
    const mark = barMark(key);
    const count = el('span', 'pill-count', '1');
    pill.append(mark, count);
    cell.append(pill, el('span', 'bar-cell-name', BAR_STYLES[key].name));
    host.append(cell);
    return { key, pill, mark, count, rate: 1 };
  });
  const bloom = samples.find((s) => s.key === 'bloom');

  const applyRates = () => {
    samples.forEach((s) => {
      s.rate = speedFor(working, s.key, { speedsUp });
      s.count.textContent = String(working);
      if (typeof s.pill.getAnimations !== 'function') return;
      s.pill.getAnimations({ subtree: true }).forEach((a) => a.updatePlaybackRate(s.rate));
    });
    if (out) out.textContent = readout(working, speedsUp);
  };

  // Bloom swaps glyphs, so it keeps its own phase at its own rate instead of the shared tab tick.
  const region = createRegion(host);
  let bloomMs = 0;
  const paintBloom = (force = false) => {
    if (!force && !region.active) return;
    const glyph = runtime.reduced
      ? sampleGlyph('sparkle')
      : BLOOM_FRAMES[Math.floor(bloomMs / TICK_MS) % BLOOM_FRAMES.length];
    if (bloom.mark.textContent !== glyph) bloom.mark.textContent = glyph;
  };
  onFrame((dt) => {
    bloomMs += dt * bloom.rate;
    paintBloom();
  });
  paintBloom(true);

  onRuntimeChange((k) => {
    if (k !== 'reduced') return;
    samples.forEach((s) => { s.pill.dataset.star = runtime.reduced ? 'accent' : 'label'; });
    applyRates(); // CSS animations come back as new ones at 1x after Reduce Motion turns off
    paintBloom(true);
  });

  radios.forEach((r) => r.addEventListener('change', () => {
    if (!r.checked) return;
    working = Math.max(1, Math.min(4, Number.parseInt(r.value, 10) || 1));
    applyRates();
  }));
  if (toggle) {
    toggle.addEventListener('change', () => {
      speedsUp = toggle.checked;
      applyRates();
    });
  }
  const checked = radios.find((r) => r.checked);
  if (checked) working = Math.max(1, Math.min(4, Number.parseInt(checked.value, 10) || 1));
  applyRates();
}

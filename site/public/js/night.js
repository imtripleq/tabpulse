// Chapters drive the stage: whichever chapter sits in the reading band sets the stage's state.
// The sky behind the page deepens after midnight, warms faintly at the horizon before six and turns to
// blue hour as you scroll (CSS view timelines, with a scroll-listener fallback that writes the same three
// numbers). Dawn is the page itself coming up under the last chapter (dawn.css).

import { createRegion, runtime } from './runtime.js';
import { initStage } from './stage.js';

const NARROW = '(max-width: 900px)';
const BAND_WIDE = '-45% 0px -45% 0px';
const BAND_NARROW = '-60% 0px -28% 0px';

const clamp01 = (n) => Math.max(0, Math.min(1, n));

export function initNight() {
  const chapters = [...document.querySelectorAll('.chapter[data-step]')];
  const stageCol = document.querySelector('.stage-col');
  const jumpButton = document.querySelector('#stage-jump');
  const region = createRegion(stageCol);
  const stage = initStage({
    frame: document.querySelector('#stage-frame'),
    stageEl: document.querySelector('#stage'),
    desc: document.querySelector('#stage-desc'),
    noteOut: document.querySelector('#stage-note'),
    jumpNote: document.querySelector('#stage-jump-note'),
    region,
  });

  const activate = (chapter) => {
    chapters.forEach((c) => c.classList.toggle('is-active', c === chapter));
    stage.apply(chapter.dataset.step);
  };

  let io = null;
  const observe = () => {
    if (io) io.disconnect();
    if (!('IntersectionObserver' in window)) return;
    const narrow = window.matchMedia(NARROW).matches;
    io = new IntersectionObserver((entries) => {
      entries.forEach((entry) => { if (entry.isIntersecting) activate(entry.target); });
    }, { rootMargin: narrow ? BAND_NARROW : BAND_WIDE });
    chapters.forEach((c) => io.observe(c));
  };
  observe();
  try {
    window.matchMedia(NARROW).addEventListener('change', observe);
  } catch {
    /* keep the first band */
  }
  activate(chapters[0]);

  if (jumpButton) {
    jumpButton.addEventListener('click', () => {
      if (stage.step !== 'done') activate(chapters.find((c) => c.dataset.step === 'done'));
      stage.jump(jumpButton);
    });
  }

  return {
    region,
    jump: () => stage.jump(stage.step === 'done' ? jumpButton : null),
  };
}

export function initSky() {
  const html = document.documentElement;
  if (runtime.reduced) return; // static gradients instead of a scroll-linked sky
  html.classList.add('sky-on');
  const supportsTimeline = typeof CSS !== 'undefined' && CSS.supports && CSS.supports('animation-timeline: view()');
  if (supportsTimeline) {
    html.classList.add('sky-css');
    return;
  }
  // Fallback: the same three numbers as the CSS view timelines, from the same elements
  const lidEl = document.querySelector('#at-0030');
  const agentsEl = document.querySelector('#at-0315');
  const blueEl = document.querySelector('#at-0650');
  if (!lidEl || !agentsEl || !blueEl) return;
  const cover = (r, vh) => clamp01((vh - r.top) / (vh + r.height));
  let raf = 0;
  const update = () => {
    raf = 0;
    const vh = window.innerHeight;
    const l = lidEl.getBoundingClientRect();
    const a = agentsEl.getBoundingClientRect();
    const b = blueEl.getBoundingClientRect();
    html.style.setProperty('--deep-p', cover(l, vh).toFixed(4));
    html.style.setProperty('--warm-p', clamp01((cover(a, vh) - 0.5) * 2).toFixed(4));
    html.style.setProperty('--blue-p', clamp01((vh - b.top) / ((vh + b.height) / 2)).toFixed(4));
  };
  const queue = () => { if (!raf) raf = requestAnimationFrame(update); };
  window.addEventListener('scroll', queue, { passive: true });
  window.addEventListener('resize', queue);
  update();
}

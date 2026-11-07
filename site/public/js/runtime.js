// One clock for the whole page. Every tab spinner steps on the same 120 ms tick (lockstep, like the app),
// scene timers advance only while their part of the page is on screen and motion is not paused.
// The rAF loop runs only while some region is on screen, the tab is visible and motion is not paused.
// A 60 ms interval stands in only after rAF has stalled (headless capture, throttled frames) and is
// cleared as soon as frames resume.

import { TICK_MS, DEFAULT_TAB_STYLE, TAB_SPINNERS } from '../assets/tabpulse-data.js';

const RM_QUERY = '(prefers-reduced-motion: reduce)';
const MAX_FRAME_MS = 100; // a long frame (tab switch, debugger) never fast-forwards a scene
const STALL_MS = 250;
const WATCHDOG_MS = 60;

// QA capture only: `?still` ends one-shot animations at once, because headless Chrome barely paints frames.
export const qaStill = (() => {
  try {
    return new URLSearchParams(window.location.search).has('still');
  } catch {
    return false;
  }
})();

// `?style=moon` starts the page in that tab spinner style (harmless; handy for QA and for sharing a pick).
const startStyle = (() => {
  try {
    const key = new URLSearchParams(window.location.search).get('style');
    return key && Object.hasOwn(TAB_SPINNERS, key) ? key : DEFAULT_TAB_STYLE;
  } catch {
    return DEFAULT_TAB_STYLE;
  }
})();

const readReduced = () => {
  try {
    return window.matchMedia(RM_QUERY).matches;
  } catch {
    return false;
  }
};

const state = {
  reduced: readReduced(),
  paused: false,
  tick: 0,
  tabStyle: startStyle,
};

const changeListeners = new Set();
const frameListeners = new Set();
const tickListeners = new Set();
const animations = new Set();

let accumulator = 0;
let lastTime = 0;
let rafId = 0;
let lastRafAt = 0;
let stallTimer = 0;
let watchdogId = 0;
const regions = new Set();

/** Read-only view of the shared state. */
export const runtime = {
  get reduced() { return state.reduced; },
  get paused() { return state.paused; },
  get tick() { return state.tick; },
  get tabStyle() { return state.tabStyle; },
};

const emit = (key) => changeListeners.forEach((fn) => fn(key, runtime));

/** Subscribe to 'paused', 'reduced' and 'tabStyle' changes. Returns an unsubscribe function. */
export function onRuntimeChange(fn) {
  changeListeners.add(fn);
  return () => changeListeners.delete(fn);
}

/** Called every animation frame with the elapsed milliseconds (0 while paused). */
export function onFrame(fn) {
  frameListeners.add(fn);
  return () => frameListeners.delete(fn);
}

/** Called once per 120 ms tick with the global tick count. */
export function onTick(fn) {
  tickListeners.add(fn);
  return () => tickListeners.delete(fn);
}

/** Keep a WAAPI animation in step with the pause control. */
export function trackAnimation(anim) {
  if (!anim) return anim;
  const timing = qaStill && anim.effect ? anim.effect.getTiming() : null;
  if (timing && Number.isFinite(timing.iterations)) {
    anim.finish();
    return anim;
  }
  animations.add(anim);
  if (state.paused) anim.pause();
  const forget = () => animations.delete(anim);
  anim.addEventListener('cancel', forget);
  anim.addEventListener('finish', forget);
  return anim;
}

export function setPaused(paused) {
  const next = Boolean(paused);
  if (next === state.paused) return;
  state.paused = next;
  document.documentElement.classList.toggle('is-paused', next);
  animations.forEach((anim) => {
    try {
      if (next) anim.pause();
      else if (anim.playState === 'paused') anim.play();
    } catch {
      animations.delete(anim);
    }
  });
  emit('paused');
  syncLoop();
}

export function setTabStyle(key) {
  if (key === state.tabStyle) return;
  state.tabStyle = key;
  emit('tabStyle');
  tickListeners.forEach((fn) => fn(state.tick));
}

function advance(now) {
  const dt = lastTime ? Math.max(0, Math.min(now - lastTime, MAX_FRAME_MS)) : 0;
  lastTime = now;
  if (state.paused) return;
  frameListeners.forEach((fn) => fn(dt));
  accumulator += dt;
  if (accumulator < TICK_MS) return;
  state.tick += Math.floor(accumulator / TICK_MS);
  accumulator %= TICK_MS;
  tickListeners.forEach((fn) => fn(state.tick));
}

// The loop runs only while some region is on screen, motion is not paused and the page is visible.
const shouldRun = () => !state.paused
  && document.visibilityState === 'visible'
  && [...regions].some((r) => r.active);

function frame() {
  rafId = requestAnimationFrame(frame);
  lastRafAt = performance.now();
  if (watchdogId) {
    // frames are back: drop the timer fallback
    clearInterval(watchdogId);
    watchdogId = 0;
    armStallCheck();
  }
  advance(lastRafAt);
}

// If frames stop arriving while the page is visible (some embeds, headless capture), a timer keeps the
// clock honest. It starts only after a stall and stops as soon as a frame arrives again.
function checkStall() {
  stallTimer = 0;
  if (!rafId) return;
  if (performance.now() - lastRafAt > STALL_MS) {
    watchdogId = setInterval(() => advance(performance.now()), WATCHDOG_MS);
    return;
  }
  armStallCheck();
}

function armStallCheck() {
  clearTimeout(stallTimer);
  stallTimer = setTimeout(checkStall, STALL_MS);
}

function startLoop() {
  if (rafId) return;
  lastTime = 0; // no catch-up after a pause, a hidden tab or a stretch offscreen
  lastRafAt = performance.now();
  rafId = requestAnimationFrame(frame);
  armStallCheck();
}

function stopLoop() {
  if (rafId) cancelAnimationFrame(rafId);
  rafId = 0;
  clearTimeout(stallTimer);
  stallTimer = 0;
  clearInterval(watchdogId);
  watchdogId = 0;
}

function syncLoop() {
  if (shouldRun()) startLoop();
  else stopLoop();
}

let started = false;
export function startClock() {
  if (started) return;
  started = true;
  document.addEventListener('visibilitychange', syncLoop);
  try {
    window.matchMedia(RM_QUERY).addEventListener('change', (e) => {
      state.reduced = e.matches;
      document.documentElement.classList.toggle('rm', e.matches);
      emit('reduced');
      tickListeners.forEach((fn) => fn(state.tick));
    });
  } catch {
    /* older browsers: keep the first reading */
  }
  syncLoop();
}

/** A region of the page that only animates while it is on screen. */
export function createRegion(element, { rootMargin = '0px' } = {}) {
  const region = { active: false, element };
  regions.add(region);
  if (!('IntersectionObserver' in window)) {
    region.active = true;
    syncLoop();
    return region;
  }
  const io = new IntersectionObserver((entries) => {
    entries.forEach((entry) => { region.active = entry.isIntersecting; });
    syncLoop();
  }, { rootMargin });
  io.observe(element);
  return region;
}

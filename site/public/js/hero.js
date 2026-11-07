// The hero: a night desktop with four Ghostty windows in a cascade, eight titled tabs each, all 32
// stepping in lockstep. One flips to ●, and ⌃⌥⌘J moves the camera onto that tab, the way TabPulse
// raises its window and selects its tab. Terminal text is plain session output, not Claude Code's UI.

import { formatClock, rowSubtitle } from '../assets/tabpulse-data.js';
import { ghostty, menu, pill, richText } from './mocks.js';
import { createRegion, onFrame, onRuntimeChange, runtime, trackAnimation } from './runtime.js';

const CALM_FIRST_MS = 3000; // the first tab flips to ● about 3 s in
const CALM_NEXT_MS = 6000;
const AUTO_MS = 5600; // if nobody presses, the page presses once to show what happens
const QA_AUTO_MS = 1200;
const HOLD_MS = 4500; // stay on the tab, then zoom back out
const AGAIN_MS = 4000; // JumpCycle: a second press within 4 s goes to the next waiting tab
const ZOOM_IN_MS = 760;
const ZOOM_OUT_MS = 720;
const EASE_OUT = 'cubic-bezier(0.22, 1, 0.36, 1)';
const EASE_IN_OUT = 'cubic-bezier(0.65, 0, 0.35, 1)';
const BEEP_MS = 360;

// Desktop geometry in Ghostty points (1 pt = 1 CSS px before the camera scales the wall).
const WIN_W = 1056; // eight tabs of about 124 pt, so every title has room
const WIN_H = 124; // title bar 28, tab row 30, three lines of terminal
const STEP_X = 28; // each window sits a little right of the one behind it
const STEP_Y = 86; // and low enough to show its title bar, its tabs and its first line
const HEAD_H = 58;
const FRONT = 3;
const WALL_PAD = 20;
const COMPACT_PAD = 14;
const MAX_K = 1.1;
const MIN_K = 0.78; // below this the tab titles stop reading, so the camera crops instead of shrinking
const COMPACT_K = 0.8;
const HERO_MAX_VH = 0.52; // the wall never takes more than about half of the first view
const HERO_SHORT_VH = 0.4; // on laptop screens it leaves room for the title and the install command
const SHORT_VIEW = '(min-width: 901px) and (max-height: 960px)'; // matches the short query in hero.css
const ZOOM_CAP = 2.3;
const ZOOM_EDGE = 24; // the zoomed tab and its caption keep this much air inside the hero
const COMPACT_FOCUS_W = 300;
const MIN_FOCUS_W = 440; // room for the "waiting for permission" line
const CAPTION_GAP = 14;
const CAPTION_K = 1.4; // the caption's type lands near 18 px, next to a tab zoomed about 1.7 to 2.3x
const CAPTION_W = 330;

const LAYOUT = {
  w: WIN_W + 3 * STEP_X,
  h: 3 * STEP_Y + WIN_H,
  rects: [0, 1, 2, 3].map((i) => ({ x: i * STEP_X, y: i * STEP_Y, w: WIN_W, h: WIN_H })),
};

const ask = (text) => [['t-you', '> '], ['', text]];
const dim = (text) => [['t-dim', text]];
const mid = (text) => [['t-mid', text]];

const WINDOWS = [
  {
    folder: 'api',
    tabs: ['refactor auth', 'rate limiter', 'fix login 500', 'openapi docs', 'retry webhooks', 'cache headers', 'audit log', 'pagination'],
    body: [ask('move the auth middleware onto the new session store'), dim('read src/middleware/auth.ts'), mid('editing src/middleware/auth.ts')],
  },
  {
    folder: 'web',
    tabs: ['dark mode', 'fix hydration', 'nav a11y', 'image sizes', 'form errors', 'lint warnings', 'date picker', 'router upgrade'],
    body: [ask('add a dark mode toggle to the header'), dim('read src/theme/tokens.ts'), mid('thinking')],
  },
  {
    folder: 'shop',
    tabs: ['cart totals', 'tax rounding', 'coupon codes', 'search filters', 'order emails', 'fix flaky test', 'stock sync', 'refund flow'],
    body: [ask('round cart totals the way the tax service does'), dim('running npm test -- totals'), mid('41 passed, 2 failed')],
  },
  {
    folder: 'infra',
    tabs: ['migrate db', 'bump deps', 'ci cache', 'backup script', 'terraform plan', 'log rotation', 'health checks', 'release notes'],
    body: [ask('run migration 0042 on staging'), dim('running psql -f migrations/0042.sql'), mid('copied 1.2M of 2.9M rows')],
  },
];

// The tabs that take turns needing you
const TARGETS = [
  { win: 2, tab: 5, tool: 'Edit', ask: 'fix the flaky cart test', wait: 'waiting for permission to edit src/checkout/cart.test.ts', done: 'edited src/checkout/cart.test.ts, 4 lines' },
  { win: 3, tab: 4, tool: 'Bash', ask: 'plan the new cache cluster', wait: 'waiting for permission to run terraform plan', done: 'plan: 2 to add, 1 to change, 0 to destroy' },
  { win: 1, tab: 2, tool: 'Edit', ask: 'make the nav work from the keyboard', wait: 'waiting for permission to edit src/components/Nav.tsx', done: 'edited src/components/Nav.tsx, 8 lines' },
  { win: 0, tab: 4, tool: 'Bash', ask: 'retry failed webhooks with backoff', wait: 'waiting for permission to run npm run test:webhooks', done: 'tests: 12 passed' },
];
const waitingBody = (t) => [ask(t.ask), [['t-wait', t.wait]]];
const answeredBody = (t) => [ask(t.ask), dim(t.done), mid('thinking')];

const KBD = { kbd: '⌃⌥⌘J' };
const MSG = {
  idle: ['When a tab needs you, ', KBD, ' jumps straight to it.'],
  flagged: ['One tab needs you. Press ', KBD, ' to jump to it.'],
  jumped: (t) => [`You’re on ${t.title} in ${t.folder}. Claude is asking for permission to use ${t.tool}.`],
  again: ['Nothing else needs you. With two waiting, a second press goes to the next one.'],
  early: ['Nothing needs you yet, so TabPulse beeps instead.'],
  answered: ['Back to work. All 32 tabs are working again.'],
};

const TOTAL_TABS = WINDOWS.length * 8;

const gutter = () => Math.min(64, Math.max(16, window.innerWidth * 0.044));
const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));

export function initHero(root) {
  const stage = root.querySelector('#wall-stage');
  const wall = root.querySelector('#wall');
  const caption = root.querySelector('#wall-caption');
  const keycaps = root.querySelector('#jump-keys');
  const prompt = root.querySelector('#jump-prompt');
  const pillSlot = root.querySelector('#hero-pill');
  const screen = root.querySelector('.hero-screen');
  const keys = Object.fromEntries([...keycaps.querySelectorAll('[data-key]')].map((k) => [k.dataset.key, k]));
  const region = createRegion(screen);
  const qaJump = new URLSearchParams(window.location.search).get('qa') === 'jump';

  const heroPill = pill();
  pillSlot.append(heroPill.el);
  const capMenu = menu({ region });
  capMenu.root.querySelector('.tpmenu-sep').remove();
  capMenu.setFooters([]);
  caption.append(capMenu.root);

  let rest = { k: 1, tx: 0, ty: WALL_PAD, compact: false };
  let windows = [];
  let cam = { tx: 0, ty: 0, k: 1 };
  let camAnim = null;
  let phase = 'calm';
  let phaseAt = 0;
  let sceneMs = 0;
  let lastPress = -Infinity;
  let targetIndex = 0;
  let focusedWin = FRONT;
  let userPressed = false;
  let waitedMs = 0;
  let autoQueued = false;
  let autoShown = false; // the page presses the keys for you once; after that the jump is yours

  const target = () => TARGETS[targetIndex % TARGETS.length];
  const targetInfo = () => {
    const t = target();
    return { ...t, title: WINDOWS[t.win].tabs[t.tab], folder: WINDOWS[t.win].folder };
  };
  const say = (segments) => richText(prompt, segments);

  // ---------- building ----------
  function build() {
    wall.style.width = `${LAYOUT.w}px`;
    wall.style.height = `${LAYOUT.h}px`;
    windows = WINDOWS.map((spec, i) => {
      const rect = LAYOUT.rects[i];
      const g = ghostty({
        tabs: spec.tabs.map((title, j) => ({ title, state: 'working', base: (i * 8 + j) * 41 })),
        selected: 0,
        focused: i === FRONT,
        region,
        body: spec.body,
      });
      Object.assign(g.root.style, { left: `${rect.x}px`, top: `${rect.y}px`, width: `${rect.w}px`, height: `${rect.h}px` });
      wall.append(g.root);
      return g;
    });
  }

  // ---------- camera ----------
  /** At rest the whole wall fits; on narrow screens it keeps a legible scale and the screen edge crops it. */
  function restFor(width) {
    const g = gutter();
    const widthK = (width - 2 * g) / LAYOUT.w;
    if (widthK < MIN_K) return { k: COMPACT_K, tx: g, ty: COMPACT_PAD, compact: true };
    const maxVh = window.matchMedia(SHORT_VIEW).matches ? HERO_SHORT_VH : HERO_MAX_VH;
    const heightK = (window.innerHeight * maxVh - 2 * WALL_PAD) / LAYOUT.h;
    const k = Math.max(MIN_K, Math.min(widthK, heightK, MAX_K));
    return { k, tx: (width - LAYOUT.w * k) / 2, ty: WALL_PAD, compact: false };
  }

  const camTransform = (c) => `translate(${c.tx}px, ${c.ty}px) scale(${c.k})`;
  function setCamera(next, ms, easing = EASE_OUT) {
    const from = camTransform(cam);
    const to = camTransform(next);
    cam = next;
    if (camAnim) {
      camAnim.cancel();
      camAnim = null;
    }
    wall.style.transform = to;
    if (!ms || runtime.reduced || typeof wall.animate !== 'function') return;
    camAnim = trackAnimation(wall.animate([{ transform: from }, { transform: to }], { duration: ms, easing }));
  }

  /** What the camera frames: the title bar, the tab strip up to the target tab, and the waiting line. */
  function focusRect() {
    const t = target();
    const r = LAYOUT.rects[t.win];
    const tab = windows[t.win].tabEl(t.tab);
    const tabLeft = r.x + tab.offsetLeft;
    const tabRight = tabLeft + tab.offsetWidth;
    if (rest.compact) {
      const center = (tabLeft + tabRight) / 2;
      return { x: center - COMPACT_FOCUS_W / 2, y: r.y, w: COMPACT_FOCUS_W, h: HEAD_H + 4, tabLeft };
    }
    const w = Math.max(tabRight - r.x + 16, MIN_FOCUS_W);
    return { x: r.x, y: r.y, w, h: r.h, tabLeft }; // the whole window height, so the caption sits below it
  }

  const captionScale = (width) => (rest.compact ? Math.min(1, (width - 32) / CAPTION_W) : CAPTION_K);

  /** Zoom so the framed strip and the caption under it both fit inside the hero, with air on every side. */
  function zoomLayout() {
    const W = stage.clientWidth;
    const H = stage.clientHeight;
    const R = focusRect();
    const ck = captionScale(W);
    const capH = (caption.offsetHeight || 84) * ck;
    const k = Math.min(ZOOM_CAP, (W - 2 * ZOOM_EDGE) / R.w, (H - 2 * ZOOM_EDGE - CAPTION_GAP - capH) / R.h);
    const top = Math.max(ZOOM_EDGE * 0.5, (H - (R.h * k + CAPTION_GAP + capH)) / 2);
    const next = { k, tx: (W - R.w * k) / 2 - R.x * k, ty: top - R.y * k };
    const capX = clamp(next.tx + R.tabLeft * k, 16, W - 16 - CAPTION_W * ck);
    return { cam: next, cap: { x: capX, y: top + R.h * k + CAPTION_GAP, k: ck } };
  }

  function placeCaption(cap) {
    Object.assign(caption.style, { left: `${Math.round(cap.x)}px`, top: `${Math.round(cap.y)}px` });
    caption.style.setProperty('--cap-k', String(cap.k));
  }

  function fit() {
    rest = restFor(stage.clientWidth);
    stage.style.setProperty('--wall-h', `${Math.round(LAYOUT.h * rest.k + 2 * rest.ty)}px`);
    if (phase === 'zoomed') {
      const z = zoomLayout();
      setCamera(z.cam, 0);
      placeCaption(z.cap);
    } else {
      setCamera(rest, 0);
    }
  }

  // ---------- story ----------
  function counts(waiting) {
    heroPill.set({ working: TOTAL_TABS - waiting, waiting, finished: 0 });
  }

  function resetToCalm() {
    phase = 'calm';
    phaseAt = sceneMs;
    wall.classList.remove('is-zoomed');
    caption.classList.remove('is-on');
    keycaps.classList.remove('is-armed');
    counts(0);
  }

  function flag() {
    const t = target();
    phase = 'flagged';
    phaseAt = sceneMs;
    waitedMs = 0;
    autoQueued = false;
    windows[t.win].setTab(t.tab, { state: 'waiting' });
    windows[t.win].flag(t.tab, true);
    counts(1);
    keycaps.classList.add('is-armed');
    const info = targetInfo();
    capMenu.setRows([{
      id: 'wait', state: 'waiting', title: info.title, sub: rowSubtitle('waiting', `permission to use ${info.tool}`), time: formatClock(0),
    }], { animate: false });
    say(MSG.flagged);
  }

  function jump() {
    const t = target();
    const w = windows[t.win];
    windows[focusedWin].setFocused(false);
    windows.forEach((win) => win.root.classList.remove('is-target'));
    focusedWin = t.win;
    w.setFocused(true);
    w.root.classList.add('is-target');
    w.select(t.tab);
    w.setBody(waitingBody(t));
    wall.classList.add('is-zoomed');
    const z = zoomLayout();
    placeCaption(z.cap);
    caption.classList.add('is-on');
    setCamera(z.cam, ZOOM_IN_MS, EASE_OUT);
    phase = 'zoomed';
    phaseAt = sceneMs;
    lastPress = sceneMs;
    say(MSG.jumped(targetInfo()));
  }

  function answer() {
    const t = target();
    const w = windows[t.win];
    w.setTab(t.tab, { state: 'working' });
    w.flag(t.tab, false);
    w.setBody(answeredBody(t));
    // the window settles back into the stack while the others fade up over it
    w.root.classList.remove('is-target');
    counts(0);
    keycaps.classList.remove('is-armed');
    caption.classList.remove('is-on');
    wall.classList.remove('is-zoomed');
    setCamera(rest, ZOOM_OUT_MS, EASE_IN_OUT);
    phase = 'returning';
    phaseAt = sceneMs;
    say(MSG.answered);
  }

  function beep() {
    keycaps.classList.remove('is-beep');
    void keycaps.offsetWidth; // restart the shake
    keycaps.classList.add('is-beep');
    setTimeout(() => keycaps.classList.remove('is-beep'), BEEP_MS);
  }

  /** ⌃⌥⌘J, from the real keys, J on the focused keycaps, or a click on the keycaps. */
  function press({ auto = false } = {}) {
    if (!auto) userPressed = true;
    if (phase === 'flagged') {
      jump();
      return;
    }
    if (phase === 'zoomed') {
      if (sceneMs - lastPress < AGAIN_MS) say(MSG.again);
      lastPress = sceneMs;
      return;
    }
    beep();
    if (phase === 'calm') say(MSG.early);
  }

  const timers = new Set();
  const later = (fn, ms) => {
    const id = setTimeout(() => { timers.delete(id); fn(); }, ms);
    timers.add(id);
  };

  /** The keycaps press in order, the way fingers land on a chord, then J fires the jump. */
  function pressSequence({ auto = false } = {}) {
    const order = [['ctrl', 0], ['alt', 70], ['meta', 140], ['j', 260]];
    order.forEach(([key, at]) => later(() => keys[key].classList.add('is-down'), at));
    later(() => press({ auto }), 270);
    later(() => Object.values(keys).forEach((k) => k.classList.remove('is-down')), 430);
  }

  function step(dt) {
    if (!region.active) return;
    sceneMs += dt;
    const since = sceneMs - phaseAt;
    if (phase === 'calm') {
      const wait = targetIndex === 0 ? CALM_FIRST_MS : CALM_NEXT_MS;
      if (since >= wait) flag();
    } else if (phase === 'flagged') {
      waitedMs += dt;
      const autoAt = qaJump ? QA_AUTO_MS : AUTO_MS;
      if (!autoQueued && !runtime.reduced && (qaJump || (!userPressed && !autoShown)) && since >= autoAt) {
        autoQueued = true;
        autoShown = true;
        pressSequence({ auto: true });
      }
    } else if (phase === 'zoomed') {
      waitedMs += dt;
      if (sceneMs - lastPress >= HOLD_MS) answer();
    } else if (phase === 'returning' && since >= ZOOM_OUT_MS) {
      targetIndex += 1;
      resetToCalm();
      say(MSG.idle);
    }
    if (phase === 'flagged' || phase === 'zoomed') {
      capMenu.setTime('wait', formatClock(waitedMs / 1000 + 4));
    }
  }

  // ---------- wiring ----------
  keycaps.addEventListener('click', (e) => {
    // A keyboard "click" (Enter or Space) presses straight away; a pointer click plays the chord.
    if (e.detail === 0) press();
    else pressSequence();
  });

  onFrame(step);
  onRuntimeChange((key) => {
    if (key === 'reduced') fit();
  });
  let resizeRaf = 0;
  const onResize = () => {
    cancelAnimationFrame(resizeRaf);
    resizeRaf = requestAnimationFrame(fit);
  };
  if ('ResizeObserver' in window) new ResizeObserver(onResize).observe(stage);
  window.addEventListener('resize', onResize);

  build();
  resetToCalm();
  fit();
  say(MSG.idle);

  return {
    region,
    press,
    /** Mirror the physical modifier keys on the keycaps. */
    mirror({ ctrl, alt, meta, j }) {
      keys.ctrl.classList.toggle('is-down', ctrl);
      keys.alt.classList.toggle('is-down', alt);
      keys.meta.classList.toggle('is-down', meta);
      keys.j.classList.toggle('is-down', j);
    },
    pressJ() {
      keys.j.classList.add('is-down');
      later(() => keys.j.classList.remove('is-down'), 140);
      press();
    },
  };
}

// The night stage: a laptop on the desk, one Ghostty window with four sessions, the TabPulse menu,
// macOS banners, and a lid that really closes. Each chapter sets one state; timers count up live.
// While the lid is shut a note floats where the screen was: what is still running, with a live tab spinner.

import {
  MENU, NOTIFICATIONS, formatAgo, formatClock, rowSubtitle,
} from '../assets/tabpulse-data.js';
import {
  banner, el, ghostty, menu, pill, richText, spinner,
} from './mocks.js';
import { onFrame, onRuntimeChange, runtime, trackAnimation } from './runtime.js';

const LID_CLOSED_DEG = -78; // short of flat, so the shape still reads as a closed laptop
const LID_CLOSE_MS = 1400;
const LID_OPEN_MS = 1150;
const BANNER_IN_MS = 560;
const NARROW_BELOW = 560;
const NARROW_MAX_VH = 0.44; // on a phone the pinned stage leaves more than half the screen to the chapter
const BEEP_MS = 360;

const DIMS = {
  wide: {
    screen: { w: 840, h: 525 }, bezel: { t: 14, x: 14, b: 18 }, canvasW: 1000, canvasH: 636,
    persp: 5200, eye: 430, deckOver: 8, menuBar: ['Ghostty', 'Shell', 'Edit', 'View', 'Window', 'Help'],
    win: { x: 22, y: 46, w: 500, h: 344 }, notifW: 344,
  },
  narrow: {
    screen: { w: 360, h: 330 }, bezel: { t: 10, x: 8, b: 12 }, canvasW: 412, canvasH: 398,
    persp: 7000, eye: 280, deckOver: 6, menuBar: ['Ghostty', 'Shell', 'Edit'],
    // the window sits under the open menu, so its tabs stay in view on a phone
    win: { x: 8, y: 238, w: 344, h: 84 }, notifW: 336,
  },
};

const SESSIONS = {
  auth: { title: 'refactor auth', folder: 'api' },
  flaky: { title: 'fix flaky test', folder: 'shop' },
  notes: { title: 'release notes', folder: 'docs' },
  db: { title: 'migrate db', folder: 'billing' },
};
const TAB_ORDER = ['auth', 'flaky', 'notes', 'db'];

// Plain session output of our own, not Claude Code's interface
const ask = (text) => [['t-you', '> '], ['', text]];
const BODIES = {
  auth: [
    ask('move auth onto the new session store'),
    [['t-dim', 'edited src/middleware/auth.ts, 27 lines']],
    [['t-mid', 'running the auth tests']],
  ],
  authDone: [
    'Done. Auth reads from the new store',
    'and all 214 tests pass.',
    '',
    [['t-you', '> ']],
  ],
  flakyDone: [
    'Fixed. The test raced the cart debounce',
    'and now waits for the total.',
    '',
    [['t-you', '> ']],
  ],
  notesDone: [
    'Wrote the 0.9.0 entries in CHANGELOG.md.',
    '',
    [['t-you', '> ']],
  ],
  dbDone: [
    'Migration 0042 ran on staging and the',
    'row counts match.',
    '',
    [['t-you', '> ']],
  ],
  flakyWaiting: [
    ask('fix the flaky cart test'),
    [['t-wait', 'waiting for permission to edit cart.test.ts']],
  ],
};
const doneBody = { auth: BODIES.authDone, flaky: BODIES.flakyDone, notes: BODIES.notesDone, db: BODIES.dbDone };

const row = (id, state, detail, secs, isNew = false) => ({ id, state, detail, secs, isNew });

const STEPS = {
  start: {
    clock: ['Thu 23:10', '23:10'], menu: true,
    tabs: { auth: 'working', flaky: 'working', notes: 'working', db: 'working' },
    rows: [row('db', 'working', 'running Bash', 720), row('auth', 'working', 'thinking', 511),
      row('flaky', 'working', 'running Bash', 250), row('notes', 'working', 'thinking', 42)],
    footers: [MENU.ghosttyFooter.ready, MENU.awakeFooter.awake],
    pill: { working: 4, waiting: 0, finished: 0 },
    desc: '23:10. Four Ghostty tabs show the same spinner frame. The menu bar reads 4, and the open TabPulse menu lists the four sessions with their timers.',
  },
  waiting: {
    clock: ['Thu 23:42', '23:42'], menu: true, flagged: 'flaky',
    tabs: { auth: 'working', flaky: 'waiting', notes: 'working', db: 'working' },
    rows: [row('flaky', 'waiting', 'permission to use Edit', 38), row('db', 'working', 'running Bash', 2640),
      row('auth', 'working', 'thinking', 2431), row('notes', 'working', 'thinking', 1962)],
    footers: [MENU.ghosttyFooter.ready, MENU.awakeFooter.awake],
    pill: { working: 3, waiting: 1, finished: 0 },
    desc: '23:42. The fix flaky test tab shows a dot. The menu bar reads 3 with an orange dot, and the session moved to the top of the menu: needs you, permission to use Edit.',
  },
  remind: {
    clock: ['Thu 23:47', '23:47'], menu: false, flagged: 'flaky',
    tabs: { auth: 'working', flaky: 'waiting', notes: 'working', db: 'working' },
    banners: [{ title: NOTIFICATIONS.stillNeedsYou.title(SESSIONS.flaky.title), body: NOTIFICATIONS.stillNeedsYou.body(SESSIONS.flaky.folder, 5) }],
    pill: { working: 3, waiting: 1, finished: 0 },
    desc: `23:47. One banner: ${NOTIFICATIONS.stillNeedsYou.title(SESSIONS.flaky.title)}. ${NOTIFICATIONS.stillNeedsYou.body(SESSIONS.flaky.folder, 5)}.`,
  },
  lid: {
    clock: ['Fri 00:30', '00:30'], menu: false, lid: true,
    tabs: { auth: 'working', flaky: 'working', notes: 'done', db: 'working' },
    note: { lead: 'Lid closed, with Keep awake with lid closed turned on.', live: 'Three sessions are still working.' },
    pill: { working: 3, waiting: 0, finished: 1 },
    desc: '00:30. The lid closes and the screen goes dark. Three sessions are still working, and with Keep awake with lid closed turned on, TabPulse keeps the Mac awake. Release notes has finished.',
  },
  agents: {
    clock: ['Fri 03:15', '03:15'], menu: false, lid: true,
    tabs: { auth: 'done', flaky: 'done', notes: 'done', db: 'working' },
    note: { lead: 'Lid still closed. A workflow review runs in the background.', live: 'Migrate db is still working.' },
    pill: { working: 1, waiting: 0, finished: 1 },
    desc: '03:15. The lid is still closed. One session is still working: migrate db, with a workflow review running in the background.',
  },
  done: {
    clock: ['Fri 06:50', '06:50'], menu: false, jumpable: true,
    tabs: { auth: 'done', flaky: 'done', notes: 'done', db: 'done' },
    banners: [{ title: NOTIFICATIONS.finished.title(SESSIONS.db.title), body: NOTIFICATIONS.finished.body(SESSIONS.db.folder, formatClock(28320)) }],
    stacked: true,
    pill: { working: 0, waiting: 0, finished: 1 },
    desc: `06:50. The lid opens. Everything finished overnight. Every tab has its plain title back. A banner reads ${NOTIFICATIONS.finished.title(SESSIONS.db.title)}. ${NOTIFICATIONS.finished.body(SESSIONS.db.folder, formatClock(28320))}. The menu bar shows a green dot and no count.`,
  },
  dawn: {
    clock: ['Fri 07:02', '07:02'], menu: true, light: true,
    tabs: { auth: 'done', flaky: 'done', notes: 'done', db: 'done' },
    rows: [row('db', 'done', '', 720), row('auth', 'done', '', 16320), row('flaky', 'done', '', 20520), row('notes', 'done', '', 24600)],
    footers: [MENU.ghosttyFooter.ready, ''],
    pill: { working: 0, waiting: 0, finished: 0 },
    desc: '07:02. Light menu bar. The star is grey and still, and the menu lists four finished sessions.',
  },
};

// Newest unseen finished session first (JumpCycle with nothing waiting)
const UNSEEN_ORDER = ['db', 'auth', 'flaky', 'notes'];

const rowView = (r, liveSeconds) => {
  const secs = r.secs + liveSeconds;
  const isDone = r.state === 'done';
  return {
    id: r.id,
    state: r.state,
    title: SESSIONS[r.id].title,
    sub: rowSubtitle(r.state, r.detail, { isNew: r.isNew }),
    time: isDone ? formatAgo(secs) : formatClock(secs),
  };
};

export function initStage({ frame, stageEl, desc, noteOut, jumpNote, region = null }) {
  let mode = '';
  let parts = null;
  let stepKey = '';
  let step = null;
  let live = 0;
  let lastWhole = -1;
  let lidClosed = false;
  let unseen = [];
  const anims = { lid: null, shade: null };
  const noteGlyph = spinner({ region, state: 'working' }); // same tick and style as the tabs

  /** The note over the closed lid: one line of context, then a live spinner on what is still working. */
  function renderNote(note) {
    if (!noteOut) return;
    if (!note) {
      noteOut.classList.remove('is-on'); // the old text fades out with it
      return;
    }
    const live = el('span', 'stage-note-live');
    live.append(noteGlyph.node, el('span', '', note.live));
    noteOut.replaceChildren(el('span', 'stage-note-lead', note.lead), live);
    noteOut.classList.add('is-on');
  }

  function build(nextMode) {
    if (parts) {
      parts.win.destroy();
      parts.menu.destroy();
    }
    mode = nextMode;
    const d = DIMS[mode];
    const lidW = d.screen.w + d.bezel.x * 2;
    const lidH = d.screen.h + d.bezel.t + d.bezel.b;
    stageEl.replaceChildren();
    stageEl.dataset.mode = mode;
    Object.assign(stageEl.style, { width: `${d.canvasW}px`, height: `${d.canvasH}px` });

    const laptop = el('div', 'laptop');
    const left = (d.canvasW - lidW) / 2;
    Object.assign(laptop.style, {
      left: `${left}px`, top: '6px', width: `${lidW}px`, height: `${lidH}px`,
      perspectiveOrigin: `50% ${lidH - d.eye}px`,
    });
    laptop.style.setProperty('--persp', `${d.persp}px`);
    laptop.style.setProperty('--bezel-t', `${d.bezel.t}px`);
    laptop.style.setProperty('--bezel-x', `${d.bezel.x}px`);
    laptop.style.setProperty('--bezel-b', `${d.bezel.b}px`);

    const deck = el('div', 'deck');
    Object.assign(deck.style, {
      left: `${-d.deckOver}px`, top: `${lidH}px`, width: `${lidW + d.deckOver * 2}px`, height: `${Math.round(lidH * 0.97)}px`,
    });
    deck.append(el('div', 'deck-edge'));

    const lid = el('div', 'lid');
    const front = el('div', 'lid-front');
    const back = el('div', 'lid-back');
    const screen = el('div', 'screen');
    screen.dataset.appearance = 'dark';
    Object.assign(screen.style, { width: `${d.screen.w}px`, height: `${d.screen.h}px` });
    front.append(screen);
    lid.append(front, back);
    laptop.append(deck, lid);

    // menu bar
    const bar = el('div', 'macbar');
    const menus = el('span', 'macbar-menus');
    d.menuBar.forEach((name, i) => menus.append(el('span', i === 0 ? 'macbar-app' : '', name)));
    const status = el('span', 'macbar-status');
    const barPill = pill();
    const clock = el('span', 'macbar-clock');
    status.append(barPill.el, clock);
    bar.append(menus, status);

    // Ghostty
    const win = ghostty({
      tabs: TAB_ORDER.map((id, i) => ({ title: SESSIONS[id].title, state: 'working', base: i * 300 })),
      selected: 0,
      focused: true,
      region,
      keys: true,
      body: BODIES.auth,
    });
    Object.assign(win.root.style, { left: `${d.win.x}px`, top: `${d.win.y}px`, width: `${d.win.w}px`, height: `${d.win.h}px` });

    // TabPulse menu, under the pill
    const tpMenu = menu({ region });
    const notifs = el('div', 'notif-stack');
    Object.assign(notifs.style, { right: '12px', top: '34px', width: `${d.notifW}px` });
    const shade = el('div', 'screen-shade');
    screen.append(bar, win.root, tpMenu.root, notifs, shade);

    stageEl.append(laptop);
    parts = {
      d, laptop, lid, deck, screen, bar, barPill, clock, win, menu: tpMenu, notifs, shade,
    };
    lidClosed = false;
    placeMenu();
  }

  function placeMenu() {
    const { d, menu: m, barPill } = parts;
    // offsets ignore transforms, so this holds while the lid is mid-turn or the stage is scaled
    const pillRight = barPill.el.offsetLeft + barPill.el.offsetWidth;
    const x = Math.max(6, Math.min(pillRight + 8 - 330, d.screen.w - 336));
    Object.assign(m.root.style, { left: `${x}px`, top: '27px' });
  }

  function fit() {
    const width = frame.clientWidth;
    const nextMode = width < NARROW_BELOW ? 'narrow' : 'wide';
    if (nextMode !== mode) {
      build(nextMode);
      const key = stepKey;
      stepKey = '';
      apply(key || 'start', { animate: false });
    }
    const d = DIMS[mode];
    const maxH = mode === 'wide' ? window.innerHeight - 150 : window.innerHeight * NARROW_MAX_VH;
    const s = Math.min(width / d.canvasW, Math.max(maxH, 200) / d.canvasH, 1.15);
    const h = Math.round(d.canvasH * s);
    frame.style.setProperty('--stage-h', `${h}px`);
    frame.style.setProperty('--stage-s', s.toFixed(3));
    stageEl.style.transform = `translateX(${(width - d.canvasW * s) / 2}px) scale(${s})`;
    placeMenu();
  }

  function setLid(closed, animate) {
    if (closed === lidClosed) return;
    lidClosed = closed;
    const { lid, shade } = parts;
    const to = closed ? LID_CLOSED_DEG : 0;
    const from = closed ? 0 : LID_CLOSED_DEG;
    Object.values(anims).forEach((a) => a && a.cancel());
    if (runtime.reduced) {
      lid.style.transform = 'rotateX(0deg)';
      shade.style.opacity = closed ? '0.84' : '0';
      return;
    }
    lid.style.transform = `rotateX(${to}deg)`;
    shade.style.opacity = closed ? '1' : '0';
    if (!animate || typeof lid.animate !== 'function') return;
    const ms = closed ? LID_CLOSE_MS : LID_OPEN_MS;
    // Closing: slow start, then the last few degrees settle. Opening: a quick lift that eases in.
    const easing = closed ? 'cubic-bezier(0.55, 0, 0.25, 1)' : 'cubic-bezier(0.3, 0.1, 0.15, 1)';
    anims.lid = trackAnimation(lid.animate([{ transform: `rotateX(${from}deg)` }, { transform: `rotateX(${to}deg)` }], { duration: ms, easing }));
    anims.shade = trackAnimation(shade.animate(
      closed ? [{ opacity: 0 }, { opacity: 0.6, offset: 0.5 }, { opacity: 1 }] : [{ opacity: 1 }, { opacity: 0 }],
      { duration: closed ? ms : ms * 0.7, easing: 'linear' },
    ));
  }

  function setBanners(list, stacked, animate) {
    const { notifs } = parts;
    notifs.replaceChildren(...(list || []).map(banner));
    notifs.classList.toggle('is-stacked', Boolean(stacked));
    if (!list || !animate || runtime.reduced || typeof notifs.animate !== 'function') return;
    trackAnimation(notifs.animate(
      [{ transform: 'translateX(380px)', opacity: 0.4 }, { transform: 'translateX(0)', opacity: 1 }],
      { duration: BANNER_IN_MS, easing: 'cubic-bezier(0.22, 1, 0.36, 1)', delay: 220, fill: 'backwards' },
    ));
  }

  function renderRows() {
    const { menu: m } = parts;
    if (step.rows) step.rows.forEach((r) => m.setTime(r.id, rowView(r, live).time));
  }

  function apply(key, { animate = true } = {}) {
    if (key === stepKey || !STEPS[key]) return;
    const prev = step;
    stepKey = key;
    step = STEPS[key];
    live = 0;
    lastWhole = -1;
    const p = parts;

    p.screen.dataset.appearance = step.light ? 'light' : 'dark';
    p.clock.textContent = step.clock[mode === 'wide' ? 0 : 1];
    renderNote(step.note);

    TAB_ORDER.forEach((id, i) => {
      p.win.setTab(i, { state: step.tabs[id] });
      p.win.flag(i, step.flagged === id);
    });
    if (!step.jumpable) p.win.select(0);
    const authState = step.tabs.auth;
    const selectedId = TAB_ORDER[p.win.selected];
    p.win.setBody(step.tabs[selectedId] === 'done' ? doneBody[selectedId] : (authState === 'done' ? BODIES.authDone : BODIES.auth));

    p.barPill.set(step.pill);

    if (step.rows) p.menu.setRows(step.rows.map((r) => rowView(r, 0)), { animate: animate && prev && prev.menu });
    if (step.footers) p.menu.setFooters(step.footers);
    p.menu.setOpen(Boolean(step.menu));


    const sameBanners = prev && prev.banners && step.banners && prev.banners[0].title === step.banners[0].title;
    if (!sameBanners) setBanners(step.banners, step.stacked, animate);
    setLid(Boolean(step.lid), animate);

    if (step.jumpable) {
      unseen = [...UNSEEN_ORDER];
      if (jumpNote) jumpNote.textContent = '';
    }
    if (desc) desc.textContent = step.desc;
  }

  function beep(button) {
    if (!button) return;
    button.classList.remove('is-beep');
    void button.offsetWidth;
    button.classList.add('is-beep');
    setTimeout(() => button.classList.remove('is-beep'), BEEP_MS);
  }

  /** ⌃⌥⌘J on the stage. Waiting: jump to the tab. Nothing waiting: newest unseen finished, then a beep. */
  function jump(button = null) {
    if (!step) return;
    const p = parts;
    if (step.flagged) {
      const i = TAB_ORDER.indexOf(step.flagged);
      p.win.select(i);
      p.win.setBody(BODIES.flakyWaiting);
      p.menu.setOpen(false);
      return;
    }
    if (!step.jumpable) {
      beep(button);
      return;
    }
    if (!unseen.length) {
      beep(button);
      if (jumpNote) richText(jumpNote, ['Nothing left to jump to, so TabPulse beeps.']);
      return;
    }
    const id = unseen.shift();
    const i = TAB_ORDER.indexOf(id);
    p.win.select(i);
    p.win.setBody(doneBody[id]);
    if (!unseen.length) {
      p.barPill.set({ finished: 0 });
      p.notifs.replaceChildren();
      p.notifs.classList.remove('is-stacked');
    }
    const left = unseen.length;
    if (jumpNote) {
      richText(jumpNote, [`Jumped to ${SESSIONS[id].title}. ${left ? `${left} finished ${left === 1 ? 'session' : 'sessions'} you haven’t seen.` : 'You’ve seen them all, so the green dot is gone.'}`]);
    }
  }

  onFrame((dt) => {
    if (!step) return;
    live += dt / 1000;
    const whole = Math.floor(live);
    if (whole !== lastWhole) {
      lastWhole = whole;
      renderRows();
    }
  });
  onRuntimeChange((key) => {
    if (key !== 'reduced' || !parts) return;
    const closed = lidClosed;
    lidClosed = !closed;
    setLid(closed, false);
  });

  let raf = 0;
  const onResize = () => {
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(fit);
  };
  if ('ResizeObserver' in window) new ResizeObserver(onResize).observe(frame);
  window.addEventListener('resize', onResize);

  fit();
  return { apply, jump, get step() { return stepKey; } };
}

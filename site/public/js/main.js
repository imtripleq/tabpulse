// Night shift: wiring. One clock, one pause control, one ⌃⌥⌘J.

import { initTabTitle } from '../assets/tab-title.js';
import { initCopy } from './copy.js';
import { initHero } from './hero.js';
import { initNight, initSky } from './night.js';
import { qaStill, runtime, setPaused, startClock } from './runtime.js';
import { glyphWidth, initStyles } from './styles.js';

const html = document.documentElement;
html.classList.add('js');
html.classList.toggle('rm', runtime.reduced);
html.classList.toggle('qa-still', qaStill);
html.style.setProperty('--glyph-w', glyphWidth(runtime.tabStyle));

function initMotionToggles() {
  const toggles = [...document.querySelectorAll('[data-motion-toggle]')];
  // The label says what a press does next, so the state lives in the label and a class, not in aria-pressed
  const sync = () => {
    toggles.forEach((t) => {
      t.classList.toggle('is-paused', runtime.paused);
      const label = t.querySelector('.motion-label');
      if (label) label.textContent = runtime.paused ? 'Play animation' : 'Pause animation';
    });
  };
  toggles.forEach((t) => t.addEventListener('click', () => {
    setPaused(!runtime.paused);
    sync();
  }));
  sync();
}

const isTyping = (target) => target instanceof Element && Boolean(target.closest('input, textarea, select, [contenteditable="true"]'));

function initKeys(hero, night) {
  const heroKeys = document.querySelector('#jump-keys');
  const stageJump = document.querySelector('#stage-jump');
  const mirror = (e, jDown) => {
    if (!hero.region.active) return;
    hero.mirror({ ctrl: e.ctrlKey, alt: e.altKey, meta: e.metaKey, j: jDown });
  };
  document.addEventListener('keydown', (e) => {
    const isJ = e.code === 'KeyJ';
    const chord = e.ctrlKey && e.altKey && e.metaKey;
    mirror(e, isJ && chord);
    if (!isJ || e.repeat) return;
    if (chord) {
      e.preventDefault();
      if (hero.region.active) hero.press();
      else if (night.region.active) night.jump();
      return;
    }
    // J on its own only works on a focused jump control, so it never fires while someone
    // types, navigates with a screen reader or speaks commands (WCAG 2.1.4).
    if (e.ctrlKey || e.altKey || e.metaKey || e.shiftKey || isTyping(e.target)) return;
    if (document.activeElement === heroKeys) {
      e.preventDefault();
      hero.pressJ();
    } else if (stageJump && document.activeElement === stageJump) {
      e.preventDefault();
      stageJump.click();
    }
  });
  document.addEventListener('keyup', (e) => mirror(e, false));
  window.addEventListener('blur', () => hero.mirror({ ctrl: false, alt: false, meta: false, j: false }));
}

startClock();
const hero = initHero(document.querySelector('#top'));
const night = initNight();
initStyles();
initCopy();
initMotionToggles();
initKeys(hero, night);
initSky();
initTabTitle({ styleKey: runtime.tabStyle, label: 'TabPulse' });

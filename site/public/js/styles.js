// Styles: the spinner sheet (pick one and every tab on the page switches, the hero wall and this page's
// hidden-tab title included), a Ghostty window beside it showing the pick on a real tab strip, and the
// menu bar marks with Speed up when busy.

import { TAB_STYLE_META } from '../assets/tabpulse-data.js';
import { setTabTitleStyle } from '../assets/tab-title.js';
import { initMarks } from './marks.js';
import { ghostty } from './mocks.js';
import { initPicker } from './picker.js';
import { createRegion, runtime, setTabStyle } from './runtime.js';

/** Glyph box width for a style: 0.6 em a cell, emoji a little wider. */
export function glyphWidth(key) {
  const meta = TAB_STYLE_META[key];
  return meta.section === 'Emoji' ? '1.3em' : `${(0.6 * meta.cells).toFixed(2)}em`;
}

const noteFor = (key) => (key === 'braille'
  ? 'Braille, the default, is on every tab on this page.'
  : `${TAB_STYLE_META[key].name} is on every tab on this page.`);

function initPreview(slot) {
  const region = createRegion(slot);
  const win = ghostty({
    tabs: [
      { title: 'refactor auth', state: 'working' },
      { title: 'release notes', state: 'working', base: 200 },
      { title: 'fix flaky test', state: 'waiting' },
    ],
    selected: 0,
    focused: true,
    region,
    body: [
      [['t-you', '> '], ['', 'move auth onto the new session store']],
      [['t-dim', 'two tabs working, one waiting on you']],
    ],
  });
  slot.append(win.root);
}

/** The full gallery is a 650 KB GIF: it loads the first time someone opens it, and never with Reduce Motion on. */
function initGallery(details) {
  const img = details && details.querySelector('img[data-src]');
  if (!img) return;
  details.addEventListener('toggle', () => {
    if (!details.open || runtime.reduced || img.hasAttribute('src')) return;
    img.src = img.dataset.src;
  });
}

export function initStyles() {
  const sheet = document.querySelector('#tab-sheet');
  const note = document.querySelector('#tab-note');
  const slot = document.querySelector('#tab-preview');
  if (slot) initPreview(slot);

  let picker = null;
  const choose = (key) => {
    if (!TAB_STYLE_META[key]) return;
    setTabStyle(key);
    document.documentElement.style.setProperty('--glyph-w', glyphWidth(key));
    setTabTitleStyle(key);
    if (picker) picker.setPressed(key);
    if (note) note.textContent = noteFor(key);
  };
  if (sheet) picker = initPicker(sheet, { onChoose: choose });
  if (note) note.textContent = noteFor(runtime.tabStyle);

  initGallery(document.querySelector('details.bar-gallery'));
  initMarks(document.querySelector('#bar-samples'), {
    toggle: document.querySelector('#speed-on'),
    radios: [...document.querySelectorAll('input[name="working"]')],
    out: document.querySelector('#speed-readout'),
  });
  return { choose };
}

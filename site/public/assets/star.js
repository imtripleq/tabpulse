// The TabPulse ✳ as the app draws it (PillView.init): a 13 x 13 box, four lines through (6.5, 6.5)
// at 0°, 45°, 90° and 135°, half-length 5.6, line width 1.5, round caps. Drawn as strokes, not a font
// glyph, so it turns around its true center and never becomes the green emoji square.

const SVG_NS = 'http://www.w3.org/2000/svg';
const STAR_BOX = 13;
const STAR_CENTER = 6.5;
const STAR_HALF_LENGTH = 5.6;
const STAR_LINE_WIDTH = 1.5;

const round = (n) => Number(n.toFixed(3));

/** The whole star as one SVG path `d`, viewBox 0 0 13 13, strokes in the app's order (0°, 45°, 90°, 135°). */
const STAR_PATH = [0, 1, 2, 3].map((i) => {
  const a = (i * Math.PI) / 4;
  const dx = STAR_HALF_LENGTH * Math.cos(a);
  const dy = STAR_HALF_LENGTH * Math.sin(a);
  return `M${round(STAR_CENTER + dx)} ${round(STAR_CENTER + dy)}L${round(STAR_CENTER - dx)} ${round(STAR_CENTER - dy)}`;
}).join('');

/**
 * The ✳ as an SVGSVGElement (built with createElementNS, no innerHTML).
 * size: rendered width and height in CSS px (default 13, the pill size).
 * color: stroke color (default currentColor).
 * label: if given, the SVG gets role="img" and that aria-label; otherwise aria-hidden="true".
 * className: optional class attribute.
 */
export function starSVG({
  size = STAR_BOX, color = 'currentColor', label = '', className = '',
} = {}) {
  const attrs = {
    viewBox: `0 0 ${STAR_BOX} ${STAR_BOX}`,
    width: size,
    height: size,
    fill: 'none',
    stroke: color,
    'stroke-width': STAR_LINE_WIDTH,
    'stroke-linecap': 'round',
    ...(className ? { class: className } : {}),
    ...(label ? { role: 'img', 'aria-label': label } : { 'aria-hidden': 'true', focusable: 'false' }),
  };
  const svg = document.createElementNS(SVG_NS, 'svg');
  Object.entries(attrs).forEach(([k, v]) => svg.setAttribute(k, String(v)));
  const path = document.createElementNS(SVG_NS, 'path');
  path.setAttribute('d', STAR_PATH);
  svg.appendChild(path);
  return svg;
}

// Reusable, animatable product components built from the real Zoomies assets/UI specs.
Z.C = {
  navy: '#0b1a20', teal: '#1b8686', tealDark: '#123a40', dash: '#45d0c4', orange: '#f7a043', brown: '#b8591c', cream: '#fff3dc',
  red: '#ff3b30', blue: '#007aff', green: '#34c759', yellow: '#ffcc00',
};

// Layered app icon (1024 canvas; scale the wrap). Parts are positioned in icon pixel space.
Z.icon = (parent) => {
  const C = Z.C;
  const wrap = Z.el(parent, 'div', { width: '1024px', height: '1024px' });
  const full = { width: '1024px', height: '1024px' };
  const bg = Z.el(wrap, 'div', { ...full, borderRadius: '230px', background: 'radial-gradient(circle at 50% 30%, #18323b 0%, #0c1a20 60%, #081116 100%)', boxShadow: '0 60px 160px rgba(0,0,0,.65), inset 0 0 0 3px rgba(255,255,255,.06)' });
  const square = Z.svg(wrap, 1024, 1024, `<rect x="150" y="170" width="725" height="690" rx="26" fill="${C.tealDark}"/>`);
  const teal = Z.svg(wrap, 1024, 1024, `<path d="M372 860 C 410 720, 470 610, 560 520 C 640 450, 730 425, 875 425 L 875 834 Q 875 860 849 860 Z" fill="${C.teal}"/>`);
  const dashes = Z.svg(wrap, 1024, 1024, `
    <rect class="dr" x="150" y="170" width="725" height="690" rx="26" fill="none" stroke="${C.dash}" stroke-width="9" stroke-dasharray="26 18" pathLength="1000" opacity=".85"/>
    <path class="dc" d="M372 860 C 410 720, 470 610, 560 520 C 640 450, 730 425, 875 425" fill="none" stroke="${C.dash}" stroke-width="9" stroke-dasharray="26 18"/>`);
  const catWrap = Z.el(wrap, 'div', { ...full, transformOrigin: '420px 640px' });
  const head = Z.el(catWrap, 'img', { ...full, transformOrigin: '420px 620px' }); head.src = '../assets/cat_head.png';
  const paw = Z.el(wrap, 'img', { ...full, transformOrigin: '418px 800px' }); paw.src = '../assets/cat_paw.png';
  // eyelids for wink/blink (left-lower eye centre ~ (276,468), right-upper eye ~ (500,345))
  const lid = (cx, cy, r) => Z.svg(catWrap, 1024, 1024, `<g transform="translate(${cx} ${cy})"><circle r="${r}" fill="#f5a449" stroke="${C.brown}" stroke-width="10"/><path d="M${-r * 0.62} 4 Q 0 ${r * 0.5} ${r * 0.62} 4" fill="none" stroke="#6b2c0c" stroke-width="12" stroke-linecap="round"/></g>`);
  const lidL = lid(276, 468, 90), lidR = lid(500, 346, 86);
  [square, teal, dashes, catWrap, head, paw, lidL, lidR].forEach((e) => Z.set(e, { x: 512, y: 512 }));
  Z.set(lidL, { x: 512, y: 512, o: 0 }); Z.set(lidR, { x: 512, y: 512, o: 0 });
  const dr = dashes.querySelector('.dr'), dc = dashes.querySelector('.dc');
  return {
    wrap, bg, square, teal, dashes, catWrap, head, paw, lidL, lidR,
    ants(t, speed = 60) { dr.style.strokeDashoffset = -t * speed; dc.style.strokeDashoffset = -t * speed * 1.4; },
    draw(p) { dr.setAttribute('stroke-dasharray', p >= 1 ? '26 18' : `${p * 1000} 1000`); },
    blink(amount, which = 'both') {
      const set = (e, a) => { e.style.opacity = a > 0.02 ? 1 : 0; e.firstElementChild.firstElementChild.style.transform = `scaleY(${0.2 + a * 0.8})`; };
      if (which !== 'R') set(lidL, amount); if (which !== 'L') set(lidR, amount);
    },
  };
};

// Background: deep navy with drifting brand-coloured glows and a dot grid that pulses.
Z.bg = (parent, { glowA = 'rgba(27,134,134,.35)', glowB = 'rgba(247,160,67,.18)' } = {}) => {
  const base = Z.el(parent, 'div', { width: '1920px', height: '1080px', background: 'radial-gradient(ellipse at 50% 45%, #0f2a31 0%, #081419 55%, #04090c 100%)' });
  const gA = Z.el(parent, 'div', { width: '1300px', height: '1300px', borderRadius: '50%', background: `radial-gradient(circle, ${glowA} 0%, rgba(0,0,0,0) 65%)` });
  const gB = Z.el(parent, 'div', { width: '1100px', height: '1100px', borderRadius: '50%', background: `radial-gradient(circle, ${glowB} 0%, rgba(0,0,0,0) 65%)` });
  const dots = Z.el(parent, 'div', { width: '2400px', height: '1500px', backgroundImage: 'radial-gradient(rgba(120,220,210,.22) 1.6px, transparent 2px)', backgroundSize: '48px 48px', webkitMaskImage: 'radial-gradient(ellipse at center, #000 20%, transparent 70%)' });
  return {
    base, gA, gB, dots,
    render(t, pulse = 0, extra = {}) {
      Z.set(gA, { x: 700 + Math.sin(t * 0.7) * 160, y: 420 + Math.cos(t * 0.5) * 90, s: 1 + pulse * 0.08 });
      Z.set(gB, { x: 1250 + Math.cos(t * 0.6) * 170, y: 640 + Math.sin(t * 0.8) * 110, s: 1 + pulse * 0.12 });
      Z.set(dots, { x: 960 + (extra.dx || 0), y: 540 + (extra.dy || 0) + t * -14, s: (extra.ds || 1) + pulse * 0.02, o: (extra.do ?? 1) * (0.55 + pulse * 0.45) });
    },
  };
};

// The "bug" we capture: a web login page with an overflowing Sign-in button. 560x500 box.
Z.loginPage = (parent) => {
  const page = Z.el(parent, 'div', { width: '560px', height: '500px', background: 'linear-gradient(160deg,#eef1f6,#e3e8f0)', overflow: 'hidden', borderRadius: '6px' });
  const card = Z.el(page, 'div', { left: '90px', top: '50px', width: '380px', height: '400px', borderRadius: '22px', background: '#fff', boxShadow: '0 18px 40px rgba(30,40,60,.14)' });
  const logo = Z.el(card, 'div', { left: '160px', top: '34px', width: '60px', height: '60px', borderRadius: '18px', background: 'linear-gradient(135deg,#6d6bf2,#4a48c9)' });
  Z.el(card, 'div', { left: '0px', top: '112px', width: '380px', textAlign: 'center', font: '700 28px system-ui', color: '#161b22' }, 'Welcome back');
  ['Email', 'Password'].forEach((ph, i) => {
    const f = Z.el(card, 'div', { left: '40px', top: 172 + i * 62 + 'px', width: '300px', height: '48px', borderRadius: '12px', background: '#f1f3f7', border: '1.5px solid #dde2ea', font: '500 16px system-ui', color: '#9aa3b2', padding: '13px 16px' }, ph);
    f.className = 'field';
  });
  const btn = Z.el(card, 'div', { left: '120px', top: '312px', width: '330px', height: '52px', borderRadius: '14px', background: '#5856d6', color: '#fff', font: '700 18px system-ui', display: 'flex', alignItems: 'center', justifyContent: 'flex-start', paddingLeft: '10px', transform: 'rotate(2.5deg)', boxShadow: '0 8px 20px rgba(88,86,214,.35)' }, 'Sign i');
  return { page, card, logo, btn };
};

// Zoomies editor toolbar: exact symbols, grouping and colours from EditorWindowController.swift.
Z.toolbar = (parent, scale = 1.6) => {
  const bar = Z.el(parent, 'div', { display: 'flex', gap: 8 * scale + 'px', alignItems: 'center', transformOrigin: '0 0' });
  bar.style.position = 'absolute';
  const groupsDef = [
    ['pencil.tip', 'line.diagonal', 'arrow.right', 'square', 'circle', 'textformat', '1.circle', 'rectangle.dashed', 'COLOR'],
    ['arrow.uturn.left', 'arrow.uturn.right', 'eraser'],
    ['minus.magnifyingglass', 'ZOOM', 'plus.magnifyingglass'],
    ['xmark', 'tray.and.arrow.down'],
  ];
  const groups = [], buttons = [];
  let swatch = null;
  groupsDef.forEach((defs) => {
    const g = document.createElement('div');
    Object.assign(g.style, { position: 'relative', display: 'flex', gap: 2 * scale + 'px', padding: 3 * scale + 'px', borderRadius: 9 * scale + 'px', background: '#2b2e2e', border: `${0.5 * scale}px solid rgba(255,255,255,.08)`, boxShadow: '0 10px 30px rgba(0,0,0,.35)' });
    bar.appendChild(g); groups.push(g); g.buttons = [];
    defs.forEach((name) => {
      const b = document.createElement('div');
      const w = name === 'ZOOM' ? 40 : 26;
      Object.assign(b.style, { position: 'relative', width: w * scale + 'px', height: 26 * scale + 'px', borderRadius: 6 * scale + 'px', display: 'flex', alignItems: 'center', justifyContent: 'center' });
      g.appendChild(b);
      if (name === 'COLOR') {
        swatch = document.createElement('div');
        Object.assign(swatch.style, { width: 18 * scale + 'px', height: 18 * scale + 'px', borderRadius: 9 * scale + 'px', background: Z.C.red, boxShadow: 'inset 0 0 0 1.5px rgba(255,255,255,.25)' });
        b.appendChild(swatch);
      } else if (name === 'ZOOM') {
        b.textContent = '100%'; Object.assign(b.style, { font: `500 ${11 * scale}px system-ui`, color: 'rgba(235,235,245,.6)' });
      } else {
        const ic = Z.symbol(b, name, 15 * scale, '#dedfe0', { position: 'relative' });
        b.icon = ic;
      }
      b.name = name; g.buttons.push(b); buttons.push(b);
    });
  });
  const setActive = (idx) => buttons.forEach((b, i) => {
    b.style.background = i === idx ? '#253e54' : 'transparent';
    if (b.icon) b.icon.style.background = i === idx ? '#8ac5ff' : '#dedfe0';
  });
  return { bar, groups, buttons, swatch, setActive };
};

// per-letter kinetic text. Returns spans; animate with Z.setInline.
Z.letters = (parent, text, css = {}) => {
  const line = Z.el(parent, 'div', { whiteSpace: 'pre', ...css });
  const spans = [...text].map((ch) => { const s = document.createElement('span'); s.textContent = ch; s.style.display = 'inline-block'; line.appendChild(s); return s; });
  return { line, spans };
};
Z.setInline = (e, { x = 0, y = 0, s = 1, sx = 1, sy = 1, r = 0, o = 1, blur = 0 } = {}) => {
  e.style.transform = `translate(${x}px,${y}px) rotate(${r}deg) scale(${s * sx},${s * sy})`;
  e.style.opacity = Z.clamp(o);
  e.style.filter = blur > 0.05 ? `blur(${blur}px)` : '';
};
// dashed marquee selection rectangle with marching ants + size readout
Z.marquee = (parent, color = Z.C.dash) => {
  const box = Z.el(parent, 'div', { width: '10px', height: '10px' });
  box.innerHTML = `<svg width="100%" height="100%" style="position:absolute;inset:0;overflow:visible"><rect x="0" y="0" width="100%" height="100%" fill="rgba(69,208,196,.08)" stroke="${color}" stroke-width="4" stroke-dasharray="16 11"/></svg>`;
  const rect = box.querySelector('rect');
  const readout = Z.el(parent, 'div', { font: '600 20px ui-monospace, SFMono-Regular, monospace', color: '#fff', background: 'rgba(0,0,0,.55)', padding: '6px 10px', borderRadius: '8px', whiteSpace: 'nowrap' });
  const cross = Z.el(parent, 'div', { width: '64px', height: '64px' });
  cross.innerHTML = `<svg width="64" height="64" viewBox="-32 -32 64 64"><g stroke="#fff" stroke-width="3" stroke-linecap="round"><line x1="-28" y1="0" x2="-8" y2="0"/><line x1="8" y1="0" x2="28" y2="0"/><line x1="0" y1="-28" x2="0" y2="-8"/><line x1="0" y1="8" x2="0" y2="28"/></g><circle r="3" fill="#fff"/></svg>`;
  return {
    box, readout, cross,
    render(t, x0, y0, x1, y1, o = 1, showCross = true) {
      const w = Math.max(1, x1 - x0), h = Math.max(1, y1 - y0);
      Object.assign(box.style, { width: w + 'px', height: h + 'px' });
      Z.set(box, { x: x0 + w / 2, y: y0 + h / 2, o });
      rect.style.strokeDashoffset = -t * 70;
      readout.textContent = `${Math.round(w)} × ${Math.round(h)}`;
      Z.set(readout, { x: x1 + 70, y: y1 + 36, o: o * (w > 30 ? 1 : 0) });
      Z.set(cross, { x: x1, y: y1, o: showCross ? o : 0 });
    },
  };
};

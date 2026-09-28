// v3: components measured 1:1 from the real app screenshots (../zoomies_web/reference, 2x retina px) + Swift source.
Z.R = {
  red: '#ee6149',          // #ff3b30 as rendered in the reference screenshots
  panelBg: 'linear-gradient(180deg,#29282d 0%,#252429 45%,#26252a 100%)',
  hintCol: 'rgba(235,235,245,.55)',
  NAME0: 'Screenshot_2026-09-28_09.41.12_204',
  NAME: 'login-button-bug',
  NOTE: 'Sign in button overflows the card, label is cut off',
  CAP: { x: 960, y: 560, s: 1.1 }, // login page on screen during capture (560x500 * 1.1)
};

const hintRow = (parent, items, top) => {
  const row = Z.el(parent, 'div', { left: '39px', top: top + 'px', display: 'flex', gap: '26px', font: '400 22px system-ui', color: Z.R.hintCol, whiteSpace: 'nowrap' });
  return items.map((h) => { const s = document.createElement('span'); s.textContent = h; row.appendChild(s); return s; });
};
const panelShell = (parent, w, h) => Z.el(parent, 'div', {
  width: w + 'px', height: h + 'px', borderRadius: '24px', background: Z.R.panelBg,
  boxShadow: '0 0 0 1px rgba(255,255,255,.13), 0 30px 80px rgba(0,0,0,.55)',
});

// Rename panel (RenamePanelController 410x215pt; reference 883x427px)
Z.R.renamePanel = (parent) => {
  const p = panelShell(parent, 883, 427);
  Z.el(p, 'div', { left: '39px', top: '36px', font: '600 26px system-ui', color: '#e8e8ea' }, 'Filename');
  const field = Z.el(p, 'div', { left: '38px', top: '80px', width: '808px', height: '44px', background: '#242428', boxShadow: '0 0 0 3px #3b6690', borderRadius: '3px', padding: '6px 8px', font: '400 26px/32px system-ui', color: '#fff', whiteSpace: 'pre' });
  const sel = document.createElement('span'); sel.style.background = '#6b86b0'; field.appendChild(sel);
  const txt = document.createElement('span'); field.appendChild(txt);
  const caret = document.createElement('span'); caret.style.cssText = 'display:inline-block;width:2px;height:28px;background:#fff;vertical-align:-5px;margin-left:1px'; field.appendChild(caret);
  const hints = hintRow(p, ['Enter: Save', '⌘↩: Copy+Save', '⌘⌫: Copy+Delete', 'Esc: Delete', 'Tab: Note'], 146);
  return {
    el: p, hints,
    set(t, { selected = null, typed = '', caretOn = true, tabGlow = 0 }) {
      sel.textContent = selected || ''; txt.textContent = selected ? '' : typed;
      caret.style.opacity = !selected && caretOn ? 1 : 0;
      hints[4].style.color = tabGlow > 0.01 ? `rgba(255,255,255,${0.55 + 0.45 * tabGlow})` : '';
    },
  };
};
// Note panel (reference 1115x268px): title, flat text area, six hints
Z.R.notePanel = (parent) => {
  const p = panelShell(parent, 1115, 268);
  Z.el(p, 'div', { left: '39px', top: '37px', font: '600 26px system-ui', color: '#e8e8ea' }, 'Note');
  const area = Z.el(p, 'div', { left: '39px', top: '82px', width: '1037px', height: '119px', background: '#1e1e1e', padding: '10px 16px', font: '400 26px/34px system-ui', color: '#fff', whiteSpace: 'pre-wrap' });
  const txt = document.createElement('span'); area.appendChild(txt);
  const caret = document.createElement('span'); caret.style.cssText = 'display:inline-block;width:2px;height:30px;background:#fff;vertical-align:-6px;margin-left:1px'; area.appendChild(caret);
  const hints = hintRow(p, ['Enter: Save', '⌘↩: Copy+Save', '⌘⌫: Copy+Delete', 'Esc: Delete', 'Shift+Tab: Rename', 'Tab: Editor'], 220);
  return {
    el: p, hints,
    set(t, { typed = '', caretOn = true, tabGlow = 0 }) {
      txt.textContent = typed; caret.style.opacity = caretOn ? 1 : 0;
      hints[5].style.color = tabGlow > 0.01 ? `rgba(255,255,255,${0.55 + 0.45 * tabGlow})` : '';
    },
  };
};
// Final annotations on the captured page (560x500 space): arrow, rect, markers 1 & 2 — thin strokes like the app
Z.R.annotations = (parent) => {
  const d = Z.svg(parent, 560, 500, `
    <g fill="none" stroke="${Z.R.red}" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round">
      <path class="ar" d="M 520 150 L 470 318" pathLength="1"/>
      <path class="ah" d="M 458 300 L 470 320 L 484 303"/>
      <rect class="rc" x="196" y="338" width="356" height="92" rx="4" pathLength="1"/>
    </g>
    <g class="m1"><circle r="17" fill="none" stroke="${Z.R.red}" stroke-width="3"/><text y="7" text-anchor="middle" font-size="19" font-weight="600" font-family="system-ui" fill="${Z.R.red}">1</text></g>
    <g class="m2"><circle r="17" fill="none" stroke="${Z.R.red}" stroke-width="3"/><text y="7" text-anchor="middle" font-size="19" font-weight="600" font-family="system-ui" fill="${Z.R.red}">2</text></g>`);
  const q = (c) => d.querySelector('.' + c);
  const [ar, ah, rc, m1, m2] = ['ar', 'ah', 'rc', 'm1', 'm2'].map(q);
  return {
    el: d,
    set({ arrow = 1, head = 1, rect = 1, mk1 = 1, mk2 = 1 } = {}) {
      ar.style.strokeDasharray = `${arrow} 1`; ar.style.opacity = arrow > 0 ? 1 : 0;
      ah.setAttribute('transform', `translate(470 320) scale(${head}) translate(-470 -320)`);
      rc.style.strokeDasharray = `${rect} 1`; rc.style.opacity = rect > 0 ? 1 : 0;
      m1.setAttribute('transform', `translate(552 338) scale(${mk1})`);
      m2.setAttribute('transform', `translate(262 384) scale(${mk2})`);
    },
  };
};
// Editor window (reference 1156x812px): traffic lights, dark toolbar tray with the real toolbar, canvas at 100%
Z.R.editor = (parent, annFactory = Z.R.annotations) => {
  const win = Z.el(parent, 'div', { width: '1156px', height: '812px', borderRadius: '22px', background: 'linear-gradient(180deg,#252429,#26262b)', boxShadow: '0 0 0 1px rgba(255,255,255,.12), 0 40px 110px rgba(0,0,0,.6)', overflow: 'hidden' });
  ['#ec6a5e', '#f4bf4f', '#61c554'].forEach((c, i) => Z.el(win, 'div', { left: 14 + i * 40 + 'px', top: '14px', width: '24px', height: '24px', borderRadius: '50%', background: c }));
  const tray = Z.el(win, 'div', { left: '33px', top: '71px', width: '1090px', height: '86px', borderRadius: '30px', background: '#191b1b', boxShadow: 'inset 0 0 0 1.5px #343737' });
  const tb = Z.toolbar(win, 2);
  tb.groups.forEach((g) => { g.style.background = '#393c3c'; g.style.borderRadius = '16px'; g.style.boxShadow = 'none'; });
  tb.swatch.style.background = Z.R.red;
  const canvas = Z.el(win, 'div', { left: '187px', top: '205px', width: '616px', height: '550px', overflow: 'hidden' });
  const imgWrap = Z.el(canvas, 'div', { width: '560px', height: '500px', transformOrigin: '0 0', transform: 'scale(1.1)' });
  Z.loginPage(imgWrap).page.style.borderRadius = '0';
  const ann = annFactory(imgWrap);
  const setActive = (idx) => tb.buttons.forEach((b, i) => {
    b.style.background = i === idx ? '#374f65' : 'transparent';
    if (b.icon) b.icon.style.background = i === idx ? '#8ac5ff' : '#dedfe0';
  });
  return {
    el: win, tb, ann, setActive,
    layout() { // centre toolbar in tray, centre canvas in content area
      const bw = tb.bar.offsetWidth, bh = tb.bar.offsetHeight;
      tb.bar.style.transform = `translate(${33 + (1090 - bw) / 2}px, ${71 + (86 - bh) / 2}px)`;
      canvas.style.left = (1156 - 616) / 2 + 'px';
    },
  };
};
// The saved/copied result: annotated image with the note burned in below (WorkflowNoteRenderer: white strip,
// black system font, size max(12, w*0.04), padding max(8, w*0.02)). Width 616 (= 560 * 1.1).
Z.R.resultImage = (parent, annFactory = Z.R.annotations) => {
  const w = 616, fs = Math.max(12, w * 0.04), pad = Math.max(8, w * 0.02);
  const box = Z.el(parent, 'div', { width: w + 'px', background: '#fff', boxShadow: '0 30px 80px rgba(0,0,0,.5)' });
  const img = document.createElement('div'); img.style.cssText = `position:relative;width:${w}px;height:550px;overflow:hidden`;
  box.appendChild(img);
  const inner = Z.el(img, 'div', { width: '560px', height: '500px', transformOrigin: '0 0', transform: 'scale(1.1)' });
  Z.loginPage(inner).page.style.borderRadius = '0';
  annFactory(inner).set({});
  const note = document.createElement('div');
  note.style.cssText = `position:relative;padding:${pad}px;font:400 ${fs}px/${fs * 1.4}px system-ui;color:#000;background:#fff`;
  note.textContent = Z.R.NOTE; box.appendChild(note);
  return { el: box, note };
};
// Subtitle pill (promo overlay, not app UI): keycaps + text, bottom centre, crossfading entries [beat, html]
Z.R.subtitle = (root) => {
  const mk = () => Z.el(root, 'div', { display: 'flex', alignItems: 'center', gap: '16px', padding: '14px 26px', borderRadius: '999px', background: 'rgba(12,16,18,.78)', backdropFilter: 'blur(14px)', boxShadow: '0 0 0 1px rgba(255,255,255,.1), 0 20px 50px rgba(0,0,0,.4)', font: '600 32px system-ui', color: '#fff', whiteSpace: 'nowrap' });
  const slots = [mk(), mk()];
  return {
    render(t, entries, y = 985, tOut = 1e9, sc = 1) {
      const bt = t / Z.BEAT; let idx = -1;
      entries.forEach((e, i) => { if (bt >= e[0]) idx = i; });
      slots.forEach((s) => (s.style.opacity = 0));
      if (idx < 0) return;
      const out = 1 - Z.ease.inOutCubic(Z.prog(t, tOut, tOut + 0.4));
      const cur = slots[idx % 2], p = Z.soft(t - Z.b(entries[idx][0]) - (idx > 0 ? 0.15 : 0), 0.5);
      const html = (e) => (typeof e[1] === 'function' ? e[1](t) : e[1]);
      const h1 = html(entries[idx]); if (cur._html !== h1) { cur.innerHTML = h1; cur._html = h1; }
      Z.set(cur, { x: 960, y: y + (1 - p) * 14 * sc, o: p * out, s: sc });
      if (idx > 0) {
        const prev = slots[(idx - 1) % 2], q = Z.prog(t, Z.b(entries[idx][0]), Z.b(entries[idx][0]) + 0.2);
        const h0 = html(entries[idx - 1]); if (prev._html !== h0) { prev.innerHTML = h0; prev._html = h0; }
        Z.set(prev, { x: 960, y, o: (1 - q) * out, s: sc });
      }
    },
  };
};
Z.R.key = (k, hot = false) => `<span style="display:inline-block;min-width:44px;text-align:center;padding:4px 10px;border-radius:9px;background:${hot ? '#f7a043' : '#2b2e2e'};color:${hot ? '#2a1405' : '#fff'};box-shadow:inset 0 -2px 0 rgba(0,0,0,.35),0 0 0 1px rgba(255,255,255,.14);font:700 26px system-ui">${k}</span>`;

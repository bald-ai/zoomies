// v4 components: full annotation set, ⌘ badges, left-hand keyboard, key recap tape, flow indicator, rename option cards.
Z.R4 = { blue: '#3a86f5' };

// Every editor tool on the captured page (560x500 page space). set() takes 0..1 progress per item.
Z.R4.annotations = (parent) => {
  const r = Z.R.red, b = Z.R4.blue;
  const d = Z.svg(parent, 560, 500, `
    <g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="3.5">
      <path class="pen" stroke="${r}" pathLength="1" d="M186 192 q12 -8 24 0 t24 0 t24 0 t24 0 t24 0 t24 0 t24 0 t18 -2"/>
      <path class="ln" stroke="${r}" pathLength="1" d="M470 58 L470 442"/>
      <path class="ar" stroke="${r}" pathLength="1" d="M530 196 L505 326"/>
      <path class="ah" stroke="${r}" d="M491 311 L505 328 L516 308"/>
      <rect class="rc" stroke="${r}" pathLength="1" x="196" y="338" width="356" height="92" rx="4"/>
      <ellipse class="el" stroke="${b}" pathLength="1" cx="252" cy="388" rx="58" ry="28"/>
    </g>
    <g class="tx"><rect class="sel" x="-8" y="-28" width="190" height="40" fill="none" stroke="#fff" stroke-width="2" stroke-dasharray="6 5" style="mix-blend-mode:difference"/>
      <text class="txt" x="0" y="0" font-size="26" font-weight="700" font-family="system-ui" fill="${b}"></text></g>
    <g class="m1"><circle r="17" fill="none" stroke="${r}" stroke-width="3"/><text y="7" text-anchor="middle" font-size="19" font-weight="600" font-family="system-ui" fill="${r}">1</text></g>
    <g class="m2"><circle r="17" fill="none" stroke="${r}" stroke-width="3"/><text y="7" text-anchor="middle" font-size="19" font-weight="600" font-family="system-ui" fill="${r}">2</text></g>`);
  const q = (c) => d.querySelector('.' + c);
  const el = Object.fromEntries(['pen', 'ln', 'ar', 'ah', 'rc', 'el', 'tx', 'sel', 'txt', 'm1', 'm2'].map((c) => [c, q(c)]));
  const draw = (e, p) => { e.style.strokeDasharray = `${p} 1`; e.style.opacity = p > 0 ? 1 : 0; };
  const TEXT = 'label cut off';
  return {
    el: d,
    set({ pen = 1, line = 1, arrow = 1, head = 1, rect = 1, ellipse = 1, text = 1, sel = 0, tx = 0, ty = 0, mk1 = 1, mk2 = 1 } = {}) {
      draw(el.pen, pen); draw(el.ln, line); draw(el.ar, arrow); draw(el.rc, rect); draw(el.el, ellipse);
      el.ah.setAttribute('transform', `translate(505 328) scale(${head}) translate(-505 -328)`);
      el.txt.textContent = TEXT.slice(0, Math.round(text * TEXT.length));
      el.tx.setAttribute('transform', `translate(${36 + tx} ${486 + ty})`);
      el.sel.style.opacity = sel;
      el.m1.setAttribute('transform', `translate(552 338) scale(${mk1})`);
      el.m2.setAttribute('transform', `translate(168 388) scale(${mk2})`);
    },
  };
};

// ⌘-hold badges (reference 6): keycap under every toolbar control + hint bar above the toolbar
Z.R4.badges = (editor) => {
  const labels = ['W', 'D', 'A', 'R', 'E', 'T', 'F', 'S', 'Q', '⌘Z', '⌘⇧Z', '⌥⌫', '⌘−', '⌘0', '⌘+', 'Esc', '↩'];
  const badges = editor.tb.buttons.map((btn, i) => {
    const b = document.createElement('div');
    b.textContent = labels[i];
    Object.assign(b.style, { position: 'absolute', left: '50%', top: 'calc(100% + 14px)', transform: 'translateX(-50%)', minWidth: '46px', padding: '3px 8px', borderRadius: '8px', background: '#2a2a2e', boxShadow: 'inset 0 0 0 1.5px rgba(255,255,255,.45)', font: '700 21px system-ui', color: '#fff', textAlign: 'center', opacity: 0, zIndex: 5 });
    btn.appendChild(b);
    return b;
  });
  const bar = Z.el(editor.el, 'div', { left: '22px', top: '14px', width: '1112px', height: '52px', borderRadius: '14px', background: '#2c2c30', font: '600 26px system-ui', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: 0 }, 'Hover over a shortcut to see it spelled out.');
  return (p, t) => {
    badges.forEach((b, i) => { const q = Z.clamp(p * 1.6 - i * 0.03); b.style.opacity = q; b.style.transform = `translateX(-50%) translateY(${(1 - q) * -8}px)`; });
    bar.style.opacity = p;
  };
};

// Left-hand keyboard: every bound key labelled with its editor action; pressed keys glow orange.
Z.R4.keyboard = (parent) => {
  const U = 78, G = 9;
  const dot = (c) => `<span style="display:inline-block;width:14px;height:14px;border-radius:50%;background:${c};box-shadow:0 0 0 1.5px rgba(255,255,255,.35)"></span>`;
  const rows = [
    [['Esc', 1.25, 'Cancel'], ['1', 1, dot('#ee6149')], ['2', 1, dot('#3a86f5')], ['3', 1, dot('#34c759')], ['4', 1, dot('#000')], ['5', 1, dot('#ffcc00')], ['6', 1, dot('#fff')]],
    [['Tab', 1.5, 'Next step'], ['Q', 1, 'Colour'], ['W', 1, 'Pen'], ['E', 1, 'Ellipse'], ['R', 1, 'Rect'], ['T', 1, 'Text']],
    [['Caps', 1.8, ''], ['A', 1, 'Arrow'], ['S', 1, 'Select'], ['D', 1, 'Line'], ['F', 1, 'Marker'], ['G', 1, '']],
    [['⇧', 2.3, 'Back'], ['Z', 1, 'Undo'], ['X', 1, 'Cut'], ['C', 1, 'Copy'], ['V', 1, 'Paste']],
    [['fn', 1, ''], ['⌃', 1, ''], ['⌥', 1, ''], ['⌘', 1.5, 'Badges']],
  ];
  const kb = Z.el(parent, 'div', { width: '640px', height: 5 * (U + G) + 70 + 'px' });
  const title = Z.el(kb, 'div', { left: '0px', top: '0px', font: '700 30px system-ui', color: '#fff', whiteSpace: 'nowrap' }, 'Every tool under your <span style="color:#f7a043">left hand</span>');
  const keys = {};
  rows.forEach((row, ri) => {
    let x = 0;
    row.forEach(([k, w, lbl]) => {
      const bound = lbl !== '';
      const key = Z.el(kb, 'div', { left: x + 'px', top: 60 + ri * (U + G) + 'px', width: w * U + (w - 1) * G + 'px', height: U + 'px', borderRadius: '14px', background: '#23272a', boxShadow: 'inset 0 -3px 0 rgba(0,0,0,.45), 0 0 0 1px rgba(255,255,255,.1)', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '4px', color: bound ? '#fff' : 'rgba(255,255,255,.3)' });
      Z.el(key, 'div', { position: 'relative', font: `700 ${k.length > 1 ? 22 : 28}px system-ui` }, k);
      const l = Z.el(key, 'div', { position: 'relative', font: '600 14px system-ui', color: 'rgba(69,208,196,.9)', whiteSpace: 'nowrap' }, lbl);
      keys[k] = { key, l, bound };
      x += w * U + w * G + (w - 1) * 0;
    });
  });
  return {
    el: kb, title,
    // lit: { KEY: 0..1 }
    render(lit = {}) {
      for (const [k, o] of Object.entries(keys)) {
        const v = lit[k] || 0;
        o.key.style.background = v > 0.01 ? `rgba(247,160,67,${0.25 + 0.75 * v})` : o.bound ? '#23272a' : '#1b1e20';
        o.key.style.color = v > 0.5 ? '#2a1405' : o.bound ? '#fff' : 'rgba(255,255,255,.3)';
        o.l.style.color = v > 0.5 ? '#2a1405' : 'rgba(69,208,196,.9)';
        o.key.style.transform = `translateY(${v * 4}px) scale(${1 - v * 0.03})`;
        o.key.style.boxShadow = v > 0.01 ? `0 0 ${30 * v}px rgba(247,160,67,${0.6 * v}), inset 0 -1px 0 rgba(0,0,0,.3)` : 'inset 0 -3px 0 rgba(0,0,0,.45), 0 0 0 1px rgba(255,255,255,.1)';
      }
    },
  };
};

// Recap tape shown on each window transition: "<Window> — you pressed: [keys...]"
Z.R4.recap = (parent) => {
  const box = Z.el(parent, 'div', { display: 'flex', alignItems: 'center', gap: '12px', padding: '12px 22px', borderRadius: '18px', background: 'rgba(12,16,18,.85)', boxShadow: '0 0 0 1px rgba(255,255,255,.12), 0 20px 50px rgba(0,0,0,.45)', font: '600 26px system-ui', color: 'rgba(235,244,245,.75)', whiteSpace: 'nowrap' });
  let cur = null;
  return {
    el: box,
    render(t, entries, y = 170) {
      const bt = t / Z.BEAT; let e = null;
      entries.forEach((x) => { if (bt >= x.b && bt < x.b + (x.len || 2.6)) e = x; });
      if (!e) { box.style.opacity = 0; return; }
      if (cur !== e) {
        box.innerHTML = `<span style="color:#f7a043;font-weight:700">${e.title}</span><span>you pressed</span>` + e.keys.map((k) => `<span class="rk" style="display:inline-block">${k.startsWith('<') ? k : Z.R.key(k)}</span>`).join('');
        cur = e;
      }
      const dt = t - Z.b(e.b), outP = Z.ease.inOutCubic(Z.prog(t, Z.b(e.b + (e.len || 2.6) - 0.4), Z.b(e.b + (e.len || 2.6))));
      const p = Z.soft(dt, 0.45);
      Z.set(box, { x: 960, y: y - (1 - p) * 20, o: p * (1 - outP), s: e.s || 1 });
      [...box.querySelectorAll('.rk')].forEach((k, i) => { const q = Z.soft(dt - 0.1 - i * 0.05, 0.35); k.style.opacity = q; k.style.transform = `translateY(${(1 - q) * 10}px) scale(${0.8 + 0.2 * q})`; });
    },
  };
};
Z.R4.txt = (s) => `<span style="font:italic 500 24px system-ui;color:#fff;opacity:.85">${s}</span>`;

// Flow indicator: Rename ⇄ Note ⇄ Editor, active highlight slides; the key that moved it pops above the arrow
Z.R4.flow = (parent) => {
  const wrap = Z.el(parent, 'div', { width: '720px', height: '70px', borderRadius: '999px', background: 'rgba(12,16,18,.8)', boxShadow: '0 0 0 1px rgba(255,255,255,.12)' });
  const hl = Z.el(wrap, 'div', { top: '7px', width: '200px', height: '56px', borderRadius: '999px', background: '#f7a043' });
  const names = ['Rename', 'Note', 'Editor'];
  const labels = names.map((n, i) => Z.el(wrap, 'div', { left: 20 + i * 240 + 'px', top: '7px', width: '200px', height: '56px', display: 'flex', alignItems: 'center', justifyContent: 'center', font: '700 28px system-ui' }, n));
  [0, 1].forEach((i) => Z.el(wrap, 'div', { left: 220 + i * 240 + 'px', top: '14px', width: '40px', textAlign: 'center', font: '600 28px system-ui', color: 'rgba(255,255,255,.4)' }, '⇄'));
  const pop = Z.el(parent, 'div', {});
  return {
    el: wrap,
    render(t, states, vis, y = 70) {
      const bt = t / Z.BEAT; let i = 0, prev = 0, tb = -1, key = '';
      states.forEach(([b, idx, k]) => { if (bt >= b) { prev = i; i = idx; tb = b; key = k; } });
      const p = Z.ease.inOutCubic(Z.clamp((t - Z.b(tb)) / 0.35));
      const pos = Z.lerp(prev, i, tb < 0 ? 1 : p);
      hl.style.left = 20 + pos * 240 + 'px';
      labels.forEach((l, k) => (l.style.color = Math.abs(pos - k) < 0.5 ? '#2a1405' : 'rgba(255,255,255,.75)'));
      Z.set(wrap, { x: 960, y, o: vis });
      const kp = Z.pulse(t - Z.b(tb), 2.2) * (tb >= 0 && key ? 1 : 0);
      if (pop._k !== key) { pop.innerHTML = key ? `<div style="display:flex;gap:8px;align-items:center;font:700 24px system-ui;color:#fff">${key}</div>` : ''; pop._k = key; }
      const px = 960 - 360 + 20 + ((prev + i) / 2) * 240 + 100;
      Z.set(pop, { x: px, y: y + 70 + (1 - Z.soft(t - Z.b(tb), 0.3)) * -12, o: vis * Z.clamp(kp * 1.4) });
    },
  };
};

// Rename-panel option cards: the five ways out of the Rename panel
Z.R4.optionCards = (parent) => {
  const K = Z.R.key;
  const defs = [
    [K('↩'), 'Save', 'done in 2 seconds'],
    [K('⌘') + K('↩'), 'Copy + Save', 'ready to paste'],
    [K('⌘') + K('⌫'), 'Copy + Delete', 'clipboard only, no file'],
    [K('Esc'), 'Delete', 'asks first · Go Back: R'],
    [K('Tab'), 'Add a note', 'keep going'],
  ];
  const cards = defs.map(([keys, title, sub]) => {
    const c = Z.el(parent, 'div', { width: '300px', height: '150px', borderRadius: '20px', background: 'rgba(14,18,20,.88)', boxShadow: '0 0 0 1px rgba(255,255,255,.12), 0 20px 50px rgba(0,0,0,.4)', padding: '18px 20px', whiteSpace: 'nowrap' });
    Z.el(c, 'div', { position: 'relative', display: 'flex', gap: '8px' }, keys);
    Z.el(c, 'div', { position: 'relative', marginTop: '14px', font: '700 30px system-ui', color: '#fff' }, title);
    Z.el(c, 'div', { position: 'relative', marginTop: '4px', font: '500 21px system-ui', color: 'rgba(235,244,245,.6)' }, sub);
    return c;
  });
  return {
    render(t, beats, tOut, y = 860) {
      const bt = t / Z.BEAT, out = Z.ease.inOutCubic(Z.prog(t, tOut, tOut + 0.45));
      let active = -1; beats.forEach((b, i) => { if (bt >= b) active = i; });
      cards.forEach((c, i) => {
        const dt = t - Z.b(beats[i]), p = Z.soft(dt, 0.5), on = i === active;
        Z.set(c, { x: 960 + (i - 2) * 324, y: y + (1 - p) * 30 + out * 30, o: p * (1 - out) * (on ? 1 : 0.55), s: on ? 1 + Z.pulse(dt, 6) * 0.04 : 0.96 });
        c.style.boxShadow = on ? '0 0 0 2.5px #f7a043, 0 20px 50px rgba(0,0,0,.45)' : '0 0 0 1px rgba(255,255,255,.12), 0 20px 50px rgba(0,0,0,.4)';
      });
      return active;
    },
  };
};

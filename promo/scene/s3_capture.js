// S3 — beats 15.5-24: double wipe into a desktop built from components, mini ⌥⇧4 HUD, marquee around the
// broken login page, shutter at beat 20 lifts the capture out as a card; card ends at Z.CARD for S4.
Z.CAP = [1050, 352, 1610, 852];            // capture rect on screen (login page bounds)
Z.CARD = { x: 960, y: 470, s: 1.12 };      // card resting transform at beat 24 (S4 starts from here)
Z.scene({
  name: 'capture', from: 15.5, to: 24,
  build(root) {
    const R = Z.rng(5);
    this.desk = Z.el(root, 'div', { width: '1920px', height: '1080px', transformOrigin: '1330px 600px' });
    Z.el(this.desk, 'div', { width: '1920px', height: '1080px', background: 'radial-gradient(ellipse at 20% 80%, #1b5f63 0%, rgba(0,0,0,0) 50%), radial-gradient(ellipse at 85% 15%, #7a4a20 0%, rgba(0,0,0,0) 45%), linear-gradient(160deg,#0d2228,#071014)' });
    // menu bar with the real Zoomies tray icon (SF "camera")
    this.menu = Z.el(this.desk, 'div', { width: '1920px', height: '40px', background: 'rgba(20,24,26,.72)', backdropFilter: 'blur(20px)', borderBottom: '1px solid rgba(255,255,255,.06)', display: 'flex', alignItems: 'center', gap: '28px', padding: '0 24px', font: '600 16px system-ui', color: 'rgba(255,255,255,.9)' });
    ['●', 'Code', 'File', 'Edit', 'Selection', 'View'].forEach((w, i) => { const s = document.createElement('span'); s.textContent = w; if (i > 1) s.style.fontWeight = 400; this.menu.appendChild(s); });
    this.tray = Z.symbol(this.desk, 'camera', 24, '#fff');
    Z.el(this.desk, 'div', { left: '1790px', top: '10px', font: '500 16px system-ui', color: 'rgba(255,255,255,.9)' }, 'Sat 9:41');
    const win = (x, y, w, h, title) => {
      const el = Z.el(this.desk, 'div', { width: w + 'px', height: h + 'px', borderRadius: '14px', background: '#16191b', border: '1px solid rgba(255,255,255,.1)', boxShadow: '0 40px 90px rgba(0,0,0,.55)', overflow: 'hidden' });
      el.home = [x + w / 2, y + h / 2];
      const tb = Z.el(el, 'div', { width: '100%', height: '46px', background: '#202426', borderBottom: '1px solid rgba(0,0,0,.4)' });
      ['#ff5f57', '#febc2e', '#28c840'].forEach((c, i) => Z.el(tb, 'div', { left: 18 + i * 22 + 'px', top: '16px', width: '13px', height: '13px', borderRadius: '50%', background: c }));
      Z.el(tb, 'div', { left: '0px', top: '13px', width: '100%', textAlign: 'center', font: '500 15px system-ui', color: 'rgba(255,255,255,.55)' }, title);
      return el;
    };
    this.code = win(110, 120, 880, 820, 'login.tsx — app');
    this.lines = [];
    const cols = ['#c792ea', '#82aaff', '#f7a043', '#c3e88d', '#89ddff', '#eeffff'];
    for (let i = 0; i < 22; i++) {
      const row = Z.el(this.code, 'div', { left: '0px', top: 70 + i * 32 + 'px', width: '100%', height: '32px' });
      Z.el(row, 'div', { left: '22px', top: '6px', font: '500 15px ui-monospace, monospace', color: 'rgba(255,255,255,.25)' }, String(i + 1).padStart(2, ' '));
      let x = 80 + (i % 7 === 0 ? 0 : (Math.floor(R() * 3) + 1) * 28);
      const n = 1 + Math.floor(R() * 4);
      for (let k = 0; k < n; k++) { const w = 40 + R() * 140; Z.el(row, 'div', { left: x + 'px', top: '10px', width: w + 'px', height: '12px', borderRadius: '6px', background: cols[Math.floor(R() * cols.length)], opacity: 0.85 }); x += w + 14; }
      this.lines.push(row);
    }
    this.browser = win(860, 160, 940, 820, '');
    this.url = Z.el(this.browser, 'div', { left: '300px', top: '9px', width: '340px', height: '28px', borderRadius: '8px', background: 'rgba(255,255,255,.07)', font: '500 15px system-ui', color: 'rgba(255,255,255,.7)', textAlign: 'center', paddingTop: '4px' }, 'localhost:3000/login');
    Z.el(this.browser, 'div', { left: '0px', top: '46px', width: '100%', height: '774px', background: 'linear-gradient(160deg,#eef1f6,#e3e8f0)' });
    this.page = Z.loginPage(this.browser);
    Object.assign(this.page.page.style, { left: Z.CAP[0] - 860 + 'px', top: Z.CAP[1] - 160 + 'px', borderRadius: '0px' });
    // dim overlay (macOS style) via a huge box-shadow around the selection hole
    this.hole = Z.el(root, 'div', { boxShadow: '0 0 0 3000px rgba(0,0,0,.5)' });
    this.sel = Z.marquee(root);
    this.keys = ['⌥', '⇧', '4'].map((l) => Z.keycap(root, l, 110));
    // lifted capture card (a real copy of the captured components)
    this.card = Z.el(root, 'div', { width: '560px', height: '500px', borderRadius: '14px', overflow: 'hidden', boxShadow: '0 50px 120px rgba(0,0,0,.6), 0 0 0 1px rgba(255,255,255,.15)' });
    this.cardPage = Z.loginPage(this.card);
    this.headline = Z.letters(root, 'Exactly what your agent needs to see.', { font: '750 64px system-ui', color: '#fff', textShadow: '0 8px 30px rgba(0,0,0,.6)' });
    // wipes
    this.wipeA = Z.el(root, 'div', { width: '1400px', height: '1800px', background: Z.C.teal });
    this.wipeB = Z.el(root, 'div', { width: '1400px', height: '1800px', background: Z.C.orange });
    Z.shake(16, 12); Z.shake(20, 26, 7); Z.shake(16.5, 5); Z.shake(17, 5); Z.shake(17.5, 8);
  },
  render(t, root, { fx }) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT;
    // wipes: cover at beat 16, exit by 16.6
    const wp = (d) => e.inOutCubic(Z.prog(t, B(15.5 + d), B(16.6 + d)));
    Z.set(this.wipeB, { x: Z.lerp(-800, 2900, wp(0)), y: 540, skx: -20 });
    Z.set(this.wipeA, { x: Z.lerp(-800, 2900, wp(0.12)), y: 540, skx: -20 });
    const show = bt >= 16;
    this.desk.style.visibility = show ? 'visible' : 'hidden';
    const d16 = t - B(16);
    // desktop elements fly in
    Z.set(this.menu, { x: 960, y: 20 - (1 - Z.spring(d16, 2.5, 0.5)) * 60 });
    Z.set(this.tray, { x: 1740, y: 20, s: Z.spring(d16 - 0.15, 3, 0.3) * (1 + Z.pulse(t - B(20), 8) * 0.8), o: show ? 1 : 0 });
    this.tray.style.background = t > B(20) && t < B(21) ? Z.C.dash : '#fff';
    [[this.code, 0.08, -1], [this.browser, 0.22, 1]].forEach(([w, delay, dir]) => {
      const p = Z.spring(d16 - delay, 1.9, 0.42);
      Z.set(w, { x: w.home[0] + (1 - p) * dir * 300, y: w.home[1] + (1 - p) * 700, r: (1 - p) * dir * 12, o: d16 > delay ? 1 : 0 });
    });
    this.lines.forEach((l, i) => { const p = Z.spring(d16 - 0.3 - i * 0.025, 3, 0.5); l.style.transform = `translateX(${(1 - p) * -60}px)`; l.style.opacity = Z.clamp(p); });
    // mini HUD keys
    this.keys.forEach((k, i) => {
      const dt = t - B(16.5 + i * 0.5), p = Z.spring(dt, 3, 0.32), w = Z.wobble(dt, 3.5, 7);
      const out = e.inBack(Z.prog(t, B(18.2), B(18.8)));
      k.face.style.transform = `translateY(${Z.pulse(dt, 14) * 8}px)`;
      Z.set(k, { x: 960 + (i - 1) * 130, y: 960 + out * 200, s: p * (1 - out * 0.5), sx: 1 + w * 0.15, sy: 1 - w * 0.2, o: dt > 0 ? 1 - out : 0 });
    });
    // marquee + dim
    const [x0, y0, x1, y1] = Z.CAP;
    const dp = e.inOutCubic(Z.prog(t, B(18), B(19.75))) + Z.wobble(t - B(19.75), 3, 8) * 0.02 * (bt > 19.75 ? 1 : 0);
    const selOn = bt >= 18 && bt < 20;
    const cx = Z.lerp(x0 + 20, x1, dp), cy = Z.lerp(y0 + 20, y1, dp);
    this.sel.render(t, x0, y0, cx, cy, selOn ? 1 : 0);
    Object.assign(this.hole.style, { width: cx - x0 + 'px', height: cy - y0 + 'px' });
    Z.set(this.hole, { x: (x0 + cx) / 2, y: (y0 + cy) / 2, o: selOn ? Z.prog(t, B(18), B(18.3)) : 0 });
    // shutter + card lift
    const d20 = t - B(20);
    Z.flash(Z.pulse(d20, 10) * (d20 >= 0 ? 0.85 : 0));
    const lift = Z.spring(d20, 1.4, 0.45), lw = Z.wobble(d20, 2.2, 4);
    const exit = e.inOutCubic(Z.prog(t, B(22.5), B(24)));
    const cardX = Z.lerp((x0 + x1) / 2, Z.CARD.x, lift), cardY = Z.lerp((y0 + y1) / 2, Z.CARD.y - 30, lift) + exit * 30;
    Z.set(this.card, { x: cardX, y: cardY, s: Z.lerp(1, Z.CARD.s + 0.06, lift) - exit * 0.06, r: lw * -3 + (1 - lift) * 2, o: d20 >= 0 ? 1 : 0 });
    Z.set(this.desk, { x: 960, y: 540 + exit * 120, s: 1 - Z.clamp(lift) * 0.07 - exit * 0.1, blur: Z.clamp(lift) * 10 + exit * 10, o: 1 - exit });
    this.desk.style.filter += ` brightness(${1 - Z.clamp(lift) * 0.45})`;
    Z.fx.ring(fx, d20, cardX, cardY, { r0: 300, r1: 900, width: 16, color: '#fff', life: 0.45 });
    Z.fx.burst(fx, d20, cardX, cardY, { n: 50, seed: 21, speed: 1500, size: 12, life: 1, gravity: 1200 });
    // headline on beats 21-22 (per-letter cascade), leaves with exit
    const hp = t - B(21);
    Z.set(this.headline.line, { x: 960, y: 130 - exit * 80, o: 1 - exit });
    this.headline.spans.forEach((s, k) => {
      const p = Z.spring(hp - k * 0.018, 3, 0.4);
      Z.setInline(s, { y: (1 - p) * 50, o: hp - k * 0.018 > 0 ? 1 : 0, r: (1 - p) * 12, blur: (1 - Z.clamp(p)) * 6 });
    });
    const agent = this.headline.spans.slice(18, 23);
    agent.forEach((s) => (s.style.color = t > B(22) ? Z.C.orange : '#fff'));
  },
});

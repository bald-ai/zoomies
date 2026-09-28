// S4 — beats 24-40: rename panel (typing "login-bug" on 16ths, Enter at 27), editor window grows around the
// capture, real toolbar assembles on 8ths (28-32), rect/arrow/markers drawn on beats, note typed, Q colour cycle,
// whip-pan exit into S5 at beat 40.
Z.scene({
  name: 'editor', from: 24, to: 40,
  build(root) {
    this.bg = Z.bg(root);
    this.group = Z.el(root, 'div', { width: '1920px', height: '1080px' });
    this.win = Z.el(this.group, 'div', { borderRadius: '18px', background: '#131515', border: '1.5px solid #343737', boxShadow: '0 60px 140px rgba(0,0,0,.6)' });
    this.tb = Z.toolbar(this.group, 2.2);
    // canvas image (captured page + annotations + note strip)
    this.wrap = Z.el(this.group, 'div', { width: '560px', height: '500px' });
    this.strip = Z.el(this.wrap, 'div', { top: '500px', width: '560px', height: '0px', background: '#1c1f21', overflow: 'hidden', borderRadius: '0 0 14px 14px', padding: '0 20px', font: '600 21px system-ui', color: '#f2f4f5', lineHeight: '30px', paddingTop: '12px' });
    this.noteWords = 'fix 1 & 2 — button overflows the card, label is clipped'.split(' ').map((w) => { const s = document.createElement('span'); s.textContent = w; s.style.display = 'inline-block'; s.style.marginRight = '0.28em'; this.strip.appendChild(s); return s; });
    this.pageBox = Z.el(this.wrap, 'div', { width: '560px', height: '500px', borderRadius: '14px', overflow: 'hidden', boxShadow: '0 30px 80px rgba(0,0,0,.5)' });
    this.page = Z.loginPage(this.pageBox);
    this.ann = Z.svg(this.wrap, 560, 500, `
      <g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="6">
        <rect class="a-rect" x="192" y="340" width="362" height="92" rx="10" pathLength="1"/>
        <path class="a-arrow" d="M 505 150 Q 470 250 470 330" pathLength="1"/>
        <path class="a-head" d="M 450 305 L 470 334 L 492 306"/>
      </g>
      <g class="a-m1"><circle r="24" fill="none" stroke-width="5"/><text y="9" text-anchor="middle" font: font-size="27" font-weight="800" font-family="system-ui">1</text></g>
      <g class="a-m2"><circle r="24" fill="none" stroke-width="5"/><text y="9" text-anchor="middle" font-size="27" font-weight="800" font-family="system-ui">2</text></g>`);
    this.a = Object.fromEntries(['a-rect', 'a-arrow', 'a-head', 'a-m1', 'a-m2'].map((c) => [c, this.ann.querySelector('.' + c)]));
    this.tag = Z.el(this.group, 'div', { padding: '8px 16px', borderRadius: '10px', background: 'rgba(20,22,24,.9)', border: '1px solid rgba(255,255,255,.12)', font: '600 22px system-ui', color: '#fff', whiteSpace: 'nowrap' }, 'login-bug<span style="color:#8e8e93">.png</span>');
    // rename panel (RenamePanelController layout)
    this.panel = Z.el(this.group, 'div', { width: '760px', height: '160px', borderRadius: '14px', background: 'rgba(38,40,42,.94)', border: '1px solid rgba(255,255,255,.12)', boxShadow: '0 40px 90px rgba(0,0,0,.6)', transformOrigin: '50% 0%' });
    Z.el(this.panel, 'div', { left: '26px', top: '20px', font: '600 19px system-ui', color: '#f2f2f7' }, 'Filename');
    this.field = Z.el(this.panel, 'div', { left: '26px', top: '52px', width: '708px', height: '48px', borderRadius: '9px', background: '#1d1d1f', boxShadow: '0 0 0 3.5px rgba(10,132,255,.55), inset 0 0 0 1px rgba(255,255,255,.1)', font: '400 24px system-ui', color: '#fff', padding: '9px 14px', whiteSpace: 'pre' });
    this.hints = Z.el(this.panel, 'div', { left: '26px', top: '116px', display: 'flex', gap: '26px', font: '400 16px system-ui', color: 'rgba(235,235,245,.6)', whiteSpace: 'nowrap' });
    this.enterHint = null;
    ['Enter: Save', '⌘↩: Copy+Save', '⌘⌫: Copy+Delete', 'Esc: Delete', 'Tab: Note'].forEach((h, i) => { const s = document.createElement('span'); s.textContent = h; this.hints.appendChild(s); if (!i) this.enterHint = s; });
    this.chip = Z.keycap(this.group, 'R', 64);
    this.qChip = Z.keycap(this.group, 'Q', 64);
    this.label = Z.el(this.group, 'div', { font: '800 46px system-ui', color: '#fff', whiteSpace: 'nowrap', padding: '10px 22px', borderRadius: '14px', background: 'rgba(247,160,67,.95)', boxShadow: '0 20px 50px rgba(0,0,0,.5)' });
    this.label.style.color = '#2a1405';
    Z.shake(27, 10); Z.shake(32.5, 6); Z.shake(34.5, 8); Z.shake(35.5, 8);
  },
  render(t, root, { fx }) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT;
    const kick = Z.beatPulse(t, 24, 40);
    this.bg.render(t, kick);
    // whip-pan exit
    const whip = e.inExpo(Z.prog(t, B(39.3), B(40)));
    Z.set(this.group, { x: 960 - whip * 2600, y: 540, sx: 1 + whip * 0.4, blur: whip * 40 });
    // card: continues from S3 then settles into editor canvas
    const grow = e.outExpo(Z.prog(t, B(27), B(28)));
    const wy = Z.lerp(Z.CARD.y, 520, grow), ws = Z.lerp(Z.CARD.s, 1.3, grow) * (1 + Z.pulse(t - B(27), 10) * 0.03);
    Z.set(this.wrap, { x: 960, y: wy, s: ws });
    // rename panel
    const pIn = Z.spring(t - B(24), 2.6, 0.4), pOut = e.inBack(Z.prog(t, B(27), B(27.45)));
    Z.set(this.panel, { x: 960, y: 865 + (1 - pIn) * 200 - pOut * 120, s: Z.clamp(pIn * 1.2, 0, 1.1) * (1 - pOut * 0.3), sy: 1 - pOut, o: bt >= 24 && pOut < 1 ? 1 : 0 });
    const typed = 'login-bug'.slice(0, Math.max(0, Math.min(9, Math.floor((bt - 24.5) / 0.25) + 1)));
    const caret = Math.floor(t * 4) % 2 || bt < 26.6 ? '|' : ' ';
    this.field.textContent = typed + caret;
    this.field.style.transform = `scale(${1 + Z.pulse(t - B(24.5 + Math.max(0, typed.length - 1) * 0.25), 18) * 0.012})`;
    this.enterHint.style.color = bt > 27 ? '#fff' : '';
    // editor window grows out of the card
    const ww = Z.lerp(560 * Z.CARD.s, 1560, grow), wh = Z.lerp(500 * Z.CARD.s, 1000, grow);
    Object.assign(this.win.style, { width: ww + 'px', height: wh + 'px' });
    Z.set(this.win, { x: 960, y: Z.lerp(Z.CARD.y, 540, grow), o: bt >= 27 ? 1 : 0, s: 1 + Z.wobble(t - B(28), 2, 6) * 0.01 });
    // filename tag lands on the card corner
    const tagP = Z.spring(t - B(27.2), 3, 0.35);
    Z.set(this.tag, { x: 960 + 280 * ws - 110, y: wy - 250 * ws - 30, s: tagP, r: (1 - tagP) * -15, o: bt > 27.2 ? 1 : 0 });
    // toolbar assembles on 8ths
    Z.set(this.tb.bar, { x: 960, y: 108 });
    // camera: push in on the toolbar while it assembles, then a gentle push on the canvas while drawing
    const g0 = this.tb.groups[0], focusX = 960 - this.tb.bar.offsetWidth / 2 + g0.offsetLeft + g0.offsetWidth / 2;
    const z1 = e.outExpo(Z.prog(t, B(27.8), B(28.5))) * (1 - e.inOutCubic(Z.prog(t, B(31), B(31.6))));
    const z2 = e.outExpo(Z.prog(t, B(32.2), B(33))) * (1 - e.inOutCubic(Z.prog(t, B(37.1), B(37.5))));
    const cs = 1 + 0.75 * z1 + 0.1 * z2;
    Z.camera.s = cs;
    Z.camera.x = z1 * (0 - (focusX - 960) * cs);
    Z.camera.y = z1 * (420 - 540 - (108 - 540) * cs) + z2 * (-(560 - 540) * cs + 20);
    this.tb.groups.forEach((g, gi) => {
      const g0 = gi === 0 ? 27.75 : 31.25 + gi * 0.25, p = Z.spring(t - B(g0), 2.8, 0.4);
      g.style.transform = `translateY(${(1 - p) * -40}px) scale(${Z.clamp(p * 1.2, 0, 1.1)})`;
      g.style.opacity = bt > g0 ? 1 : 0;
      g.buttons.forEach((b, k) => {
        const b0 = gi === 0 ? 28 + k * 0.5 : g0 + 0.1 + k * 0.08, bp = Z.spring(t - B(b0), 3.4, 0.3);
        b.style.transform = `translateY(${(1 - bp) * 30}px) rotate(${(1 - bp) * -40}deg) scale(${Z.clamp(bp * 1.3, 0, 1.25)})`;
        b.style.opacity = bt > b0 ? 1 : 0;
      });
    });
    // tool sequence: [beat, button index, key]
    const seq = [[28, -1, ''], [32.5, 3, 'R'], [33.5, 2, 'A'], [34.5, 6, 'F'], [36.5, 5, 'T'], [37.5, 8, 'Q']];
    let cur = seq[0]; for (const s of seq) if (bt >= s[0]) cur = s;
    this.tb.setActive(cur[1] === 8 ? -1 : cur[1]);
    const btn = this.tb.buttons[Math.max(0, cur[1])];
    if (cur[1] >= 0) btn.style.transform = `scale(${1 + Z.pulse(t - B(cur[0]), 10) * 0.35})`;
    // key chip above active tool
    if (this.chip.parentNode !== btn) btn.appendChild(this.chip);
    const cp = Z.spring(t - B(cur[0]), 3.2, 0.3), cOut = Z.prog(t, B(cur[0] + 0.8), B(cur[0] + 0.98));
    if (cur[1] >= 0 && cur[1] < 8) { this.chip.face.textContent = cur[2]; }
    Z.set(this.chip, { x: btn.offsetWidth / 2, y: 110 + (1 - cp) * 30, s: cp * (1 - cOut), o: cur[1] >= 0 && cur[1] < 8 ? 1 - cOut : 0 });
    // colour cycle: default palette order red → blue → green → black → yellow
    const pal = [Z.C.red, Z.C.blue, Z.C.green, '#000000', Z.C.yellow];
    const ci = bt < 37.5 ? 0 : Math.min(4, Math.floor((bt - 37.5) / 0.5) + 1);
    const col = pal[ci];
    this.tb.swatch.style.background = col;
    this.tb.swatch.style.transform = `scale(${1 + Z.pulse(t - B(37.5 + (ci - 1) * 0.5), 9) * 0.6 * (ci > 0)})`;
    const swBtn = this.tb.buttons[8]; if (this.qChip.parentNode !== swBtn) swBtn.appendChild(this.qChip);
    const qd = t - B(37.5 + Math.max(0, ci - 1) * 0.5);
    Z.set(this.qChip, { x: swBtn.offsetWidth / 2, y: 110 + Z.pulse(qd, 12) * 14, s: bt >= 37.5 ? 1 + Z.pulse(qd, 10) * 0.25 : 0, o: bt >= 37.5 ? 1 : 0 });
    this.qChip.face.style.transform = `translateY(${Z.pulse(qd, 14) * 6}px)`;
    // annotations
    const A = this.a;
    ['a-rect', 'a-arrow', 'a-head'].forEach((k) => A[k].setAttribute('stroke', col));
    ['a-m1', 'a-m2'].forEach((k) => { A[k].firstElementChild.setAttribute('stroke', col); A[k].lastElementChild.setAttribute('fill', col); });
    const rp = e.inOutCubic(Z.prog(t, B(32.5), B(33.1)));
    A['a-rect'].style.strokeDasharray = `${rp} 1`; A['a-rect'].style.opacity = rp > 0 ? 1 : 0;
    const ap = e.outCubic(Z.prog(t, B(33.5), B(33.9)));
    A['a-arrow'].style.strokeDasharray = `${ap} 1`; A['a-arrow'].style.opacity = ap > 0 ? 1 : 0;
    const hp = Z.spring(t - B(33.9), 4, 0.3);
    A['a-head'].setAttribute('transform', `translate(470 334) scale(${hp}) translate(-470 -334)`);
    [['a-m1', 34.5, 556, 340], ['a-m2', 35.5, 186, 440]].forEach(([k, b0, x, y]) => {
      const mp = Z.spring(t - B(b0), 3.5, 0.28);
      A[k].setAttribute('transform', `translate(${x} ${y}) scale(${mp})`);
      Z.fx.ring(fx, t - B(b0), 960 + (x - 280) * ws, wy + (y - 250) * ws, { r0: 20, r1: 140, width: 8, color: col === '#000000' ? '#fff' : col, life: 0.45 });
      Z.fx.burst(fx, t - B(b0), 960 + (x - 280) * ws, wy + (y - 250) * ws, { n: 14, seed: b0 * 10, speed: 600, size: 8, life: 0.55, colors: [col === '#000000' ? '#fff' : col, '#fff'] });
    });
    Z.fx.speedLines(fx, t - B(32.5), 960 + 93 * ws, wy + 136 * ws, { n: 18, r0: 230, r1: 420, life: 0.35, width: 4, color: 'rgba(255,255,255,.8)' });
    // note strip + typed words on 16ths
    const sh = e.outExpo(Z.prog(t, B(36.25), B(36.6)));
    this.strip.style.height = sh * 84 + 'px';
    this.pageBox.style.borderRadius = sh > 0 ? '14px 14px 0 0' : '14px';
    this.noteWords.forEach((s, k) => {
      const dt = t - B(36.5 + k * 0.125), p = Z.spring(dt, 4, 0.4);
      Z.setInline(s, { y: (1 - p) * 20, o: dt > 0 ? 1 : 0, s: Z.clamp(p * 1.2, 0, 1.1) });
    });
    // caption under the editor
    const labels = [[32.5, 'Draw'], [34.5, 'Number it'], [36.5, 'Prompt it'], [37.5, 'Q · next colour']];
    let lab = null; for (const l of labels) if (bt >= l[0]) lab = l;
    this.label.textContent = lab ? lab[1] : '';
    const lp = lab ? Z.spring(t - B(lab[0]), 3, 0.4) : 0;
    Z.set(this.label, { x: 1500, y: 470 + (1 - lp) * 30, o: lab ? Z.clamp(lp) : 0, r: (1 - lp) * 6 });
  },
});

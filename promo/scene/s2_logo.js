// S2 — beats 8-16: DROP. Cat bursts out of the captured square, icon frame builds, ZOOMIES letters on 16ths,
// four product verbs on beats 12-15, zoom-through exit into S3.
Z.scene({
  name: 'logo', from: 8, to: 16,
  build(root) {
    this.bg = Z.bg(root, { glowB: 'rgba(247,160,67,.28)' });
    this.rays = Z.el(root, 'div', { width: '2600px', height: '2600px', borderRadius: '50%', background: 'repeating-conic-gradient(from 0deg, rgba(69,208,196,.10) 0deg 6deg, rgba(0,0,0,0) 6deg 18deg)', webkitMaskImage: 'radial-gradient(circle, #000 0%, transparent 60%)' });
    this.group = Z.el(root, 'div', { width: '1920px', height: '1080px', transformOrigin: '960px 540px' });
    this.icon = Z.icon(this.group);
    this.word = Z.letters(this.group, 'Zoomies', { font: '800 190px ui-rounded, system-ui', color: '#fff', letterSpacing: '2px', textShadow: '0 12px 40px rgba(0,0,0,.45)' });
    this.word.line.className = 'rounded';
    this.verbs = [['camera', 'Capture'], ['pencil.tip', 'Rename'], ['arrow.right', 'Annotate'], ['doc.on.clipboard', 'Paste']].map(([sym, txt], i) => {
      const chip = Z.el(this.group, 'div', { display: 'flex', alignItems: 'center', gap: '12px', padding: '12px 22px 12px 16px', borderRadius: '999px', background: i === 3 ? Z.C.orange : 'rgba(255,255,255,.08)', border: '1.5px solid rgba(255,255,255,.12)', font: '650 30px system-ui', color: i === 3 ? '#2a1405' : '#eaf7f5', whiteSpace: 'nowrap' });
      Z.symbol(chip, sym, 30, i === 3 ? '#2a1405' : Z.C.dash, { position: 'relative' });
      chip.appendChild(document.createTextNode(txt));
      return chip;
    });
    Z.shake(8, 30, 6); Z.shake(9, 8);
  },
  render(t, root, { fx }) {
    const B = Z.b, e = Z.ease, I = this.icon;
    const d8 = t - B(8), kick = Z.beatPulse(t, 8, 16);
    const exit = Z.prog(t, B(15.1), B(16));
    this.bg.render(t, kick);
    Z.set(this.rays, { x: 960, y: 540, r: t * 12, s: 0.6 + Z.spring(d8, 1.5, 0.4) * 0.5 + kick * 0.05, o: 0.9 });
    Z.flash(Z.pulse(t - B(7.5), 9) * 0.9);
    // icon placement: centre -> left for lockup
    const slide = e.outExpo(Z.prog(t, B(9.5), B(10.3)));
    const ix = Z.lerp(960, 560, slide), iy = Z.lerp(540, 470, slide), is = Z.lerp(0.62, 0.46, slide) * (1 + kick * 0.025);
    Z.set(I.wrap, { x: ix, y: iy, s: is, r: Z.wobble(t - B(9.5), 1.6, 4) * -4 * (t > B(9.5) ? 1 : 0) });
    // frame builds
    const bgS = Z.spring(d8 - 0.05, 2.4, 0.35);
    Z.set(I.bg, { x: 512, y: 512, s: 0.75 + 0.25 * bgS, o: Z.clamp(bgS * 2) });
    I.teal.style.clipPath = `inset(${(1 - e.outExpo(Z.prog(d8, 0.05, 0.5))) * 100}% 0 0 0)`;
    I.ants(t);
    // cat pop: squash & stretch + overshoot + wobble
    const sp = Z.spring(d8, 2.3, 0.3), w = Z.wobble(d8, 3, 4.5);
    Z.set(I.catWrap, { x: 512, y: 512 + (1 - sp) * 260, s: Z.clamp(sp * 1.4, 0, 1.2), sx: 1 - w * 0.2, sy: 1 + w * 0.28, r: (1 - sp) * -25 + w * 5 });
    const pw = Z.spring(t - B(9), 3, 0.3), pww = Z.wobble(t - B(9), 4, 7);
    Z.set(I.paw, { x: 512, y: 512 - (1 - pw) * 90, s: Z.clamp(pw * 1.3, 0, 1.15), o: t > B(9) ? 1 : 0, sx: 1 + pww * 0.2, sy: 1 - pww * 0.25, r: (1 - pw) * 30 });
    const blinkP = (b0) => { const d = t - B(b0); return d > 0 && d < 0.2 ? Math.sin((d / 0.2) * Math.PI) : 0; };
    I.blink(Math.max(blinkP(11), blinkP(14.25)));
    // FX at the drop (icon centre)
    Z.fx.speedLines(fx, d8, 960, 540, { n: 48, life: 0.55, r0: 280, r1: 1400, width: 7, color: '#fff3dc' });
    Z.fx.ring(fx, d8, 960, 540, { r0: 200, r1: 900, width: 26, color: Z.C.dash, life: 0.6 });
    Z.fx.ring(fx, d8 - 0.08, 960, 540, { r0: 150, r1: 700, width: 12, color: Z.C.orange, life: 0.6 });
    Z.fx.burst(fx, d8, 960, 480, { n: 90, seed: 8, speed: 2000, size: 18, life: 1.5, gravity: 1400 });
    Z.fx.burst(fx, t - B(9), ix - 40, iy + 160, { n: 14, seed: 9, speed: 600, size: 10, life: 0.6, spread: 2 });
    // wordmark letters on 16ths
    const wx = 1270, wy = 430;
    Z.set(this.word.line, { x: wx, y: wy, s: 1 + kick * 0.02 });
    this.word.spans.forEach((s, k) => {
      const dt = t - B(10 + k * 0.25), p = Z.spring(dt, 3.2, 0.33), ww = Z.wobble(dt, 4, 7);
      Z.setInline(s, { y: (1 - p) * 120, s: Z.clamp(p * 1.5, 0, 1.3), sx: 1 + ww * 0.12, sy: 1 - ww * 0.15, r: (1 - p) * -30, o: dt > 0 ? 1 : 0 });
      Z.fx.burst(fx, dt, wx - 330 + k * 105, wy + 70, { n: 8, seed: 20 + k, speed: 500, size: 8, life: 0.5, spread: 1.6 });
    });
    // verbs on beats
    let vx = 905;
    this.verbs.forEach((c, i) => {
      const dt = t - B(12 + i), p = Z.spring(dt, 3, 0.35);
      const w = c.offsetWidth; vx += w / 2;
      Z.set(c, { x: vx + (1 - p) * 60, y: 655, s: Z.clamp(p * 1.3, 0, 1.2) * (1 + Z.pulse(dt, 10) * 0.12), o: dt > 0 ? 1 : 0, r: (1 - p) * 10 });
      vx += w / 2 + 20;
    });
    // zoom-through exit
    Z.set(this.group, { x: 960, y: 540, s: 1 + e.inExpo(exit) * 5, blur: e.inExpo(exit) * 30 });
    this.group.style.transformOrigin = `${ix}px ${iy}px`;
  },
});

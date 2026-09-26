// S1 — beats 0-8: ⌥ ⇧ 4 keycaps slam on beats 0/1/2, crosshair drags a marquee during the riser, shutter at 7.5.
Z.S1_RECT = [735.6, 328, 1185.1, 755.8]; // matches icon dashed square at scale .62 centred (match cut into S2)
Z.scene({
  name: 'intro', from: 0, to: 8,
  build(root) {
    this.bg = Z.bg(root);
    this.keys = ['⌥', '⇧', '4'].map((l) => Z.keycap(root, l, 200));
    this.intro = Z.el(root, 'div', { font: '700 40px system-ui', color: '#eafaf7', whiteSpace: 'nowrap' }, 'INTRODUCING');
    this.caption = Z.el(root, 'div', { font: '600 26px system-ui', letterSpacing: '.35em', color: 'rgba(222,240,238,.75)', whiteSpace: 'nowrap' }, 'OPTION · SHIFT · 4');
    this.sel = Z.marquee(root);
    this.fill = Z.el(root, 'div', { background: Z.C.tealDark, borderRadius: '10px' });
    this.hint = Z.el(root, 'div', { font: '500 24px ui-monospace, SFMono-Regular, monospace', color: 'rgba(160,230,222,.8)', whiteSpace: 'nowrap' }, 'drag to capture');
    Z.shake(0, 7); Z.shake(1, 9); Z.shake(2, 14); Z.shake(7.5, 20, 7);
  },
  render(t, root, { fx }) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT;
    const riser = Z.prog(t, B(3), B(7.5));
    this.bg.render(t, Z.beatPulse(t, 0, 2, 7) * 0.8, { ds: 1 + riser * 0.25, do: 0.6 + riser * 0.6 });
    Z.camera.s = 1 + e.inCubic(riser) * 0.07 + Z.pulse(t - B(7.5), 7) * 0.08;
    Z.camera.r = Math.sin(riser * 3) * 0.6 * riser;
    // keycaps
    const exit = Z.prog(t, B(2.6), B(3.2));
    this.keys.forEach((k, i) => {
      const dt = t - B(i), sp = Z.spring(dt, 3, 0.3), w = Z.wobble(dt, 3.4, 7);
      const press = Z.pulse(dt, 14) + Z.pulse(t - B(2.5), 16) * 0.8;
      k.face.style.transform = `translateY(${press * 10}px)`;
      const x = 960 + (i - 1) * 250 * (1 + e.inBack(exit) * 1.8), y = 520 - (1 - sp) * 90 + exit * exit * 40;
      Z.set(k, { x, y, s: sp * (1 - e.inBack(exit, 2.2)), sx: 1 + w * 0.16, sy: 1 - w * 0.2, r: (1 - sp) * (i - 1) * 25 + exit * (i - 1) * 40, o: dt >= 0 ? 1 : 0 });
      Z.fx.ring(fx, dt, x, 520, { r0: 60, r1: 260, width: 8, color: 'rgba(69,208,196,.9)', life: 0.5 });
      Z.fx.burst(fx, dt, x, 600, { n: 16, seed: 3 + i, speed: 700, size: 9, life: 0.7, spread: 2.2, colors: ['#45d0c4', '#fff3dc', '#f7a043'] });
    });
    const capP = Z.spring(t - B(1.5), 2.5, 0.5);
    Z.set(this.caption, { x: 960, y: 715 + (1 - capP) * 30, o: capP * (1 - exit) });
    // marquee drag with anticipation + overshoot settle
    const [x0, y0, x1, y1] = Z.S1_RECT;
    const dragP = e.inOutCubic(Z.prog(t, B(3.4), B(6.6)));
    const settle = Z.spring(t - B(3.4), 0.55, 0.55);
    const p = Z.clamp(dragP * 0.85 + settle * 0.15, 0, 1.2) - Z.wobble(t - B(6.6), 2, 6) * 0.015;
    const on = Z.prog(t, B(3), B(3.3));
    const cx = Z.lerp(x0 + 30, x1, p), cy = Z.lerp(y0 + 30, y1, p);
    const startJiggle = Z.pulse(t - B(3.4), 10);
    this.sel.render(t, x0 - startJiggle * 10, y0 - startJiggle * 10, cx, cy, on, bt < 7.5);
    Z.set(this.sel.cross, { x: bt < 3.4 ? Z.lerp(1000, x0, e.outExpo(Z.prog(t, B(3), B(3.4)))) : cx, y: bt < 3.4 ? Z.lerp(620, y0, e.outExpo(Z.prog(t, B(3), B(3.4)))) : cy, o: on * (bt < 7.5 ? 1 : 0), s: 1 + Z.pulse(t - B(3.4), 12) * 0.5, r: riser * 90 });
    const introO = Z.prog(t, B(4.5), B(5.5)) * (1 - Z.prog(t, B(7.3), B(7.5)));
    this.intro.style.letterSpacing = (0.15 + riser * 0.38) + 'em';
    Z.set(this.intro, { x: (x0 + cx) / 2 + 12, y: (y0 + cy) / 2, o: introO, s: 0.9 + riser * 0.2, blur: (1 - Z.clamp(introO * 1.5)) * 8 });
    Z.set(this.hint, { x: 960, y: y1 + 70, o: on * (1 - Z.prog(t, B(6), B(7))) * 0.9 });
    // shutter: region fills, white flash, ring & confetti hint
    const sh = t - B(7.5);
    Z.flash(Z.pulse(sh, 9) * (sh >= 0 ? 1 : 0));
    Object.assign(this.fill.style, { width: x1 - x0 + 'px', height: y1 - y0 + 'px' });
    Z.set(this.fill, { x: (x0 + x1) / 2, y: (y0 + y1) / 2, o: sh >= 0 ? 1 : 0, s: 1 + Z.pulse(sh, 10) * 0.04 });
    if (sh >= 0) this.sel.box.style.zIndex = 2;
    // inward-sucking particles during riser
    const R = Z.rng(42);
    for (let i = 0; i < 70; i++) {
      const a = R() * Math.PI * 2, ph = (R() + riser * (1.5 + R())) % 1, rad = 1100 * (1 - e.inCubic(ph));
      if (riser <= 0 || sh > 0) break;
      fx.fillStyle = i % 3 ? 'rgba(69,208,196,.7)' : 'rgba(247,160,67,.8)';
      fx.globalAlpha = Z.clamp(riser * 2) * ph;
      fx.fillRect(960 + Math.cos(a) * rad, 540 + Math.sin(a) * rad * 0.6, 3 + ph * 4, 3 + ph * 4);
    }
    fx.globalAlpha = 1;
    Z.fx.ring(fx, sh, 960, 540, { r0: 250, r1: 900, width: 18, life: 0.4 });
  },
});

// S6 — beats 56-64: finale. White-out → icon slam (56), slide + wordmark cascade (57), tagline (58),
// ⌥⇧4 keys (59), STAMP (60): marquee captures the whole lockup + URL, wink (61), hold, fade to black.
Z.scene({
  name: 'finale', from: 56, to: 64.5,
  build(root) {
    this.bg = Z.bg(root, { glowB: 'rgba(247,160,67,.3)' });
    this.rays = Z.el(root, 'div', { width: '2800px', height: '2800px', borderRadius: '50%', background: 'repeating-conic-gradient(from 0deg, rgba(247,160,67,.09) 0deg 5deg, rgba(0,0,0,0) 5deg 15deg)', webkitMaskImage: 'radial-gradient(circle, #000 0%, transparent 62%)' });
    this.icon = Z.icon(root);
    this.word = Z.letters(root, 'Zoomies', { font: '800 176px ui-rounded, system-ui', color: '#fff', letterSpacing: '2px', textShadow: '0 12px 40px rgba(0,0,0,.45)' });
    this.word.line.className = 'rounded';
    this.tagWrap = Z.el(root, 'div', { overflow: 'hidden', padding: '4px 0' });
    this.tag = Z.el(this.tagWrap, 'div', { position: 'relative', font: '600 44px system-ui', color: 'rgba(230,248,245,.9)', whiteSpace: 'nowrap' }, 'Screenshots for <span style="color:#f7a043">agentic coding</span>.');
    this.keys = ['⌥', '⇧', '4'].map((l) => Z.keycap(root, l, 84));
    this.keyLbl = Z.el(root, 'div', { font: '600 30px system-ui', color: 'rgba(230,248,245,.7)', whiteSpace: 'nowrap' }, 'to capture');
    this.url = Z.el(root, 'div', { display: 'flex', gap: '26px', alignItems: 'center', font: '600 30px system-ui', color: 'rgba(230,248,245,.85)', whiteSpace: 'nowrap' },
      '<span style="font-family:ui-monospace,monospace;color:#fff">github.com/bald-ai/zoomies</span><span style="opacity:.35">•</span><span>macOS 14+</span><span style="opacity:.35">•</span><span>Free &amp; open source</span>');
    this.frame = Z.svg(root, 1500, 560, `<rect class="fr" x="0" y="0" width="1500" height="560" rx="28" fill="none" stroke="${Z.C.dash}" stroke-width="5" stroke-dasharray="22 15" pathLength="1000"/>`);
    this.fr = this.frame.querySelector('.fr');
    this.corners = [0, 1, 2, 3].map(() => Z.el(root, 'div', { width: '26px', height: '26px', borderRadius: '6px', background: '#fff', boxShadow: '0 0 0 5px rgba(69,208,196,.5)' }));
    this.black = Z.el(root, 'div', { width: '1920px', height: '1080px', background: '#000' });
    Z.shake(56, 34, 6); Z.shake(57, 8); Z.shake(60, 26, 6);
  },
  render(t, root, { fx }) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT, I = this.icon;
    const d56 = t - B(56), d60 = t - B(60);
    const kick = Z.beatPulse(t, 56, 60) + Z.pulse(d60, 5);
    this.bg.render(t, kick);
    Z.flash(Z.pulse(d56, 6) + Z.pulse(d60, 9) * 0.5);
    Z.set(this.rays, { x: 960, y: 520, r: -t * 10, s: 0.5 + Z.spring(d56, 1.2, 0.5) * 0.6 + kick * 0.04 });
    // gentle hold push + final fade
    Z.camera.s = 1 + e.inOutCubic(Z.prog(t, B(60), B(64))) * 0.05;
    Z.set(this.black, { x: 960, y: 540, o: Z.prog(t, 29.45, 29.98) });
    // icon slam then slide left
    const slide = e.outExpo(Z.prog(t, B(57), B(57.7)));
    const sp = Z.spring(d56, 2.2, 0.3), w = Z.wobble(d56, 3, 4.5);
    const is = Z.lerp(0.6, 0.4, slide) * (0.3 + 0.7 * sp) * (1 + kick * 0.02);
    const ix = Z.lerp(960, 560, slide), iy = Z.lerp(520, 470, slide);
    Z.set(I.wrap, { x: ix, y: iy, s: is, sx: 1 - w * 0.12, sy: 1 + w * 0.16, r: (1 - sp) * 20 + Z.wobble(t - B(57), 1.6, 4) * -5 * (bt > 57) });
    I.ants(t);
    const cp = Z.spring(d56 - 0.06, 2.4, 0.3), cw = Z.wobble(d56 - 0.06, 3, 4.5);
    Z.set(I.catWrap, { x: 512, y: 512 + (1 - cp) * 200, s: Z.clamp(cp * 1.3, 0, 1.2), sx: 1 - cw * 0.2, sy: 1 + cw * 0.28 });
    const pw = Z.spring(d56 - 0.2, 3, 0.3);
    Z.set(I.paw, { x: 512, y: 512 - (1 - pw) * 90, s: Z.clamp(pw * 1.3, 0, 1.15), o: d56 > 0.2 ? 1 : 0 });
    const wink = (b0, d = 0.28) => { const q = (t - B(b0)) / d; return q > 0 && q < 1 ? Math.sin(q * Math.PI) : 0; };
    I.blink(wink(61, 0.5), 'L');
    Z.fx.speedLines(fx, d56, 960, 520, { n: 56, r0: 300, r1: 1500, life: 0.6, width: 8, color: '#fff3dc' });
    Z.fx.ring(fx, d56, 960, 520, { r0: 250, r1: 1100, width: 30, color: Z.C.orange, life: 0.7 });
    Z.fx.ring(fx, d56 - 0.1, 960, 520, { r0: 200, r1: 900, width: 14, color: Z.C.dash, life: 0.7 });
    Z.fx.burst(fx, d56, 960, 460, { n: 110, seed: 56, speed: 2300, size: 18, life: 1.6, gravity: 1400 });
    // wordmark drops in (bounce), 32nd cascade
    const wx = 1235, wy = 400;
    Z.set(this.word.line, { x: wx, y: wy, s: 1 + kick * 0.015 });
    this.word.spans.forEach((s, k) => {
      const dt = t - B(57.1) - k * 0.045, p = Z.spring(dt, 2.8, 0.3), ww = Z.wobble(dt - 0.12, 4, 7);
      Z.setInline(s, { y: -(1 - p) * 500, sx: 1 + ww * 0.15 * (dt > 0.12), sy: 1 - ww * 0.18 * (dt > 0.12), o: dt > 0 ? 1 : 0, r: (1 - p) * (k % 2 ? 20 : -20) });
    });
    // tagline mask reveal
    const tp = e.outExpo(Z.prog(t, B(58), B(58.6)));
    Z.set(this.tagWrap, { x: wx, y: 540 });
    this.tag.style.transform = `translateY(${(1 - tp) * 70}px)`;
    // keys on 16ths at 59
    this.keys.forEach((k, i) => {
      const dt = t - B(59 + i * 0.25), p = Z.spring(dt, 3.2, 0.3), ww = Z.wobble(dt, 3.5, 7);
      k.face.style.transform = `translateY(${Z.pulse(dt, 14) * 7}px)`;
      Z.set(k, { x: 930 + i * 100, y: 660, s: p, sx: 1 + ww * 0.15, sy: 1 - ww * 0.2, o: dt > 0 ? 1 : 0 });
    });
    const lp = Z.spring(t - B(59.75), 2.6, 0.4);
    Z.set(this.keyLbl, { x: 1310 + (1 - lp) * 30, y: 660, o: Z.clamp(lp) });
    // STAMP at 60: marquee captures the lockup, URL line
    const fp = e.inOutCubic(Z.prog(t, B(59.6), B(60)));
    const fs = 1 + Z.pulse(d60, 8) * 0.04;
    Z.set(this.frame, { x: 960, y: 510, s: fs, o: fp > 0 ? 1 : 0 });
    this.fr.setAttribute('stroke-dasharray', fp >= 1 ? '22 15' : `${fp * 1000} 1000`);
    this.fr.style.strokeDashoffset = fp >= 1 ? -t * 60 : 0;
    [[210, 230], [1710, 230], [210, 790], [1710, 790]].forEach(([x, y], i) => {
      const p = Z.spring(d60 - i * 0.03, 3.5, 0.3);
      Z.set(this.corners[i], { x: 960 + (x - 960) * fs, y: 510 + (y - 510) * fs, s: p, r: 45 * (1 - p), o: d60 > 0 ? 1 : 0 });
    });
    const up = Z.spring(d60 - 0.1, 2.6, 0.4);
    Z.set(this.url, { x: 960, y: 900 + (1 - up) * 40, o: Z.clamp(up) });
    Z.fx.burst(fx, d60, 960, 230, { n: 60, seed: 60, speed: 1500, size: 14, life: 1.4, gravity: 1200, spread: 2.4 });
    Z.fx.ring(fx, d60, 960, 510, { r0: 700, r1: 1300, width: 20, color: '#fff', life: 0.5 });
  },
});

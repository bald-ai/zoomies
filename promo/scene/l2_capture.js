// L2 — beats 7.6-16: "01 Capture". Browser with the bug, ⌥⇧4 presses (9, 9.25, 9.5), marquee 10-11.8,
// soft shutter at 12, the captured page lifts out and glides to the editor position (Z.L.EDIT_CARD) by 15.
Z.scene({
  name: 'capture', from: 7.6, to: 16,
  build(root) {
    this.bg = Z.bg(root, { glowA: 'rgba(27,134,134,.22)', glowB: 'rgba(247,160,67,.10)' });
    this.cap = Z.caption(root);
    this.keys = ['⌥', '⇧', '4'].map((l) => Z.keycap(root, l, 58));
    this.browser = Z.el(root, 'div', { width: '1240px', height: '780px', borderRadius: '16px', background: '#1a1e20', border: '1px solid rgba(255,255,255,.1)', boxShadow: '0 40px 100px rgba(0,0,0,.5)', overflow: 'hidden' });
    const tb = Z.el(this.browser, 'div', { width: '100%', height: '52px', background: '#202527' });
    ['#ff5f57', '#febc2e', '#28c840'].forEach((c, i) => Z.el(tb, 'div', { left: 20 + i * 22 + 'px', top: '20px', width: '13px', height: '13px', borderRadius: '50%', background: c }));
    Z.el(tb, 'div', { left: '440px', top: '11px', width: '360px', height: '30px', borderRadius: '8px', background: 'rgba(255,255,255,.07)', font: '500 16px system-ui', color: 'rgba(255,255,255,.7)', textAlign: 'center', paddingTop: '5px' }, 'localhost:3000/login');
    Z.el(this.browser, 'div', { top: '52px', width: '100%', height: '728px', background: '#e8ecf2' });
    this.card = Z.annotatedCard(root);
    this.card.set({ rect: 0, mk1: 0, mk2: 0, note: 0, chars: 0 });
    this.card.pageBox.firstElementChild.style.background = '#e8ecf2';
    this.hole = Z.el(root, 'div', { boxShadow: '0 0 0 3000px rgba(0,0,0,.42)', borderRadius: '4px' });
    this.sel = Z.marquee(root);
  },
  render(t) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT;
    this.bg.render(t, 0, { do: 0.5 });
    this.cap.render(t, [[8.2, '01', 'Capture']], B(14.8));
    // keys next to caption, soft press
    this.keys.forEach((k, i) => {
      const o = Z.env(t, B(8.5), B(14.8));
      k.face.style.transform = `translateY(${Z.pulse(t - B(9 + i * 0.25), 12) * 7}px)`;
      Z.set(k, { x: 530 + i * 70, y: 108, o });
    });
    // browser rises in, fades out after the shutter
    const bIn = Z.soft(t - B(8), 1), bOut = e.inOutCubic(Z.prog(t, B(12.3), B(13.3)));
    Z.set(this.browser, { x: 960, y: 590 + (1 - bIn) * 40, o: bIn * (1 - bOut), s: 1 - bOut * 0.03 });
    // card = the page inside the browser, then the lifted capture
    const C = Z.L.CAP_CARD, E = Z.L.EDIT_CARD, mv = e.inOutCubic(Z.prog(t, B(13), B(15)));
    const lift = Z.soft(t - B(12), 0.6);
    Z.set(this.card.wrap, { x: Z.lerp(C.x, E.x, mv), y: Z.lerp(C.y + (1 - bIn) * 40, E.y, mv) - lift * 6 * (1 - mv), s: Z.lerp(C.s, E.s, mv) * (1 + lift * 0.02 * (1 - mv)), o: bIn });
    this.card.pageBox.style.boxShadow = `0 ${10 + lift * 30}px ${30 + lift * 60}px rgba(0,0,0,${0.1 + lift * 0.4})`;
    this.card.pageBox.style.borderRadius = lift > 0 ? '14px' : '4px';
    // marquee
    const x0 = C.x - 280 * C.s - 10, y0 = C.y - 250 * C.s - 10, x1 = C.x + 280 * C.s + 10, y1 = C.y + 250 * C.s + 10;
    const dp = e.inOutCubic(Z.prog(t, B(10), B(11.8)));
    const on = bt >= 9.8 && bt < 12 ? Z.soft(t - B(9.8), 0.3) : 0;
    const cx = Z.lerp(x0 + 20, x1, dp), cy = Z.lerp(y0 + 20, y1, dp);
    this.sel.render(t, x0, y0, cx, cy, on);
    Object.assign(this.hole.style, { width: cx - x0 + 'px', height: cy - y0 + 'px' });
    Z.set(this.hole, { x: (x0 + cx) / 2, y: (y0 + cy) / 2, o: on });
    Z.flash(Z.pulse(t - B(12), 12) * (bt >= 12 ? 0.3 : 0));
  },
});

// L3 — beats 15.5-28: "02 Mark it up" → "Add a prompt". Editor chrome fades in around the card (16), real toolbar,
// rectangle (18), numbered markers (20, 21), note typed under the image (22-24). Chrome fades out 26.5; card stays
// at Z.L.EDIT_CARD for L4.
Z.scene({
  name: 'markup', from: 15.5, to: 28,
  build(root) {
    this.bg = Z.bg(root, { glowA: 'rgba(27,134,134,.22)', glowB: 'rgba(247,160,67,.10)' });
    this.cap = Z.caption(root);
    this.win = Z.el(root, 'div', { width: '1320px', height: '850px', borderRadius: '18px', background: '#131515', border: '1.5px solid #343737', boxShadow: '0 50px 120px rgba(0,0,0,.5)' });
    this.tb = Z.toolbar(root, 1.7);
    this.card = Z.annotatedCard(root);
    this.card.pageBox.style.boxShadow = '0 20px 50px rgba(0,0,0,.35)';
    this.hint = Z.el(root, 'div', { display: 'flex', gap: '14px', alignItems: 'center', font: '600 26px system-ui', color: 'rgba(230,240,242,.8)', whiteSpace: 'nowrap' });
  },
  render(t) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT, E = Z.L.EDIT_CARD;
    this.bg.render(t, 0, { do: 0.5 });
    this.cap.render(t, [[16.2, '02', 'Mark it up'], [22, '02', 'Add a prompt']], B(26.3));
    const chrome = Z.env(t, B(15.8), B(26.5), 0.9, 0.6);
    Z.set(this.win, { x: 960, y: 590, o: chrome, s: 0.97 + 0.03 * chrome });
    Z.set(this.tb.bar, { x: 960, y: 222 - (1 - Z.soft(t - B(16.3), 0.8)) * 14, o: Z.env(t, B(16.3), B(26.5), 0.8, 0.5) });
    const active = bt >= 22 ? 5 : bt >= 20 ? 6 : bt >= 18 ? 3 : -1;
    this.tb.setActive(active);
    this.tb.buttons.forEach((b, i) => (b.style.transform = i === active ? `scale(${1 + Z.pulse(t - B([0, 0, 0, 18, 0, 22, 20][i] || 0), 9) * 0.12})` : ''));
    // card (static position; continuity from L2 and into L4)
    Z.set(this.card.wrap, { x: E.x, y: E.y, s: E.s });
    this.card.set({
      rect: e.inOutCubic(Z.prog(t, B(18), B(18) + 0.6)),
      mk1: Z.calm(t - B(20)),
      mk2: Z.calm(t - B(21)),
      note: Z.soft(t - B(21.7), 0.6),
      chars: Z.clamp((t - B(22)) / (B(24) - B(22))) * Z.L.NOTE.length,
    });
    // tiny keyboard hint that follows the action (R, F, T)
    const hints = [[18, 'R', 'Rectangle'], [20, 'F', 'Numbered marker'], [22, 'T', 'Note for your agent']];
    let h = null; hints.forEach((x) => { if (bt >= x[0]) h = x; });
    if (h) this.hint.innerHTML = `<span style="font:700 22px system-ui;color:#fff;background:#2b2e2e;border:1px solid rgba(255,255,255,.15);border-radius:8px;padding:4px 12px">${h[1]}</span>${h[2]}`;
    Z.set(this.hint, { x: 1450, y: 980, o: h ? Z.soft(t - B(h[0]), 0.5) * chrome : 0 });
  },
});

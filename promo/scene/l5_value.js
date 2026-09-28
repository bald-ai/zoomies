// L5 — beats 35.8-40: the value, in numbers. "Seconds, not minutes." + 2s capture (36) / 5s annotate+prompt (38).
const L5S = Z.CFG.valueShift || 0;
Z.scene({
  name: 'value', from: 35.8 + L5S, to: 40 + L5S,
  build(root) {
    this.bg = Z.bg(root, { glowA: 'rgba(27,134,134,.22)', glowB: 'rgba(247,160,67,.14)' });
    this.head = Z.words(root, 'Seconds, not minutes.', { font: '800 88px system-ui', color: '#fff', letterSpacing: '-0.02em' });
    this.rows = [['2', Z.C.orange, 'to capture &amp; copy'], ['5', Z.C.dash, 'to capture, annotate &amp; prompt']].map(([n, c, lbl]) => {
      const row = Z.el(root, 'div', { left: '560px', display: 'flex', alignItems: 'baseline', gap: '34px', whiteSpace: 'nowrap' });
      const num = Z.el(row, 'div', { position: 'relative', width: '200px', textAlign: 'right', font: `800 150px system-ui`, color: c, fontVariantNumeric: 'tabular-nums' });
      Z.el(row, 'div', { position: 'relative', font: '600 50px system-ui', color: 'rgba(235,244,245,.9)' }, lbl);
      return { row, num, n: +n };
    });
  },
  render(t) {
    t -= Z.b(L5S);
    const B = Z.b;
    this.bg.render(t, 0, { do: 0.5 });
    const out = Z.ease.inOutCubic(Z.prog(t, B(39.3), B(39.9)));
    Z.set(this.head.line, { x: 960, y: 290, o: 1 - out });
    Z.revealWords(this.head, t, B(36), 0.1, 26);
    this.rows.forEach((r, i) => {
      const t0 = B(36.4 + i * 1.6), p = Z.soft(t - t0, 0.7);
      Z.setInline(r.row, { y: 470 + i * 190 + (1 - p) * 24, o: p * (1 - out) });
      const count = Math.max(1, Math.round(Z.ease.outCubic(Z.clamp((t - t0) / 0.6)) * r.n));
      r.num.textContent = count + 's';
    });
  },
});

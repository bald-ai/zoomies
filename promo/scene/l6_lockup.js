// L6 — beats 40-48: calm lockup. Icon settles in (40), wordmark (40.5), tagline (42), dashed "capture" frame
// + URL (44), blinks at 43 & 46, fade to black at the end.
const L6S = Z.CFG.lockupShift || 0;
Z.scene({
  name: 'lockup', from: 40 + L6S, to: 1e3,
  build(root) {
    this.bg = Z.bg(root, { glowA: 'rgba(27,134,134,.26)', glowB: 'rgba(247,160,67,.14)' });
    this.icon = Z.icon(root);
    this.word = Z.el(root, 'div', { font: '800 170px system-ui', color: '#fff', letterSpacing: '-0.02em' }, 'Zoomies');
    this.tag = Z.el(root, 'div', { font: '600 46px system-ui', color: 'rgba(230,248,245,.9)', whiteSpace: 'nowrap' }, 'Show your agent what you mean.');
    this.url = Z.el(root, 'div', { display: 'flex', gap: '24px', alignItems: 'center', font: '600 30px system-ui', color: 'rgba(230,248,245,.8)', whiteSpace: 'nowrap' },
      '<span style="font-family:ui-monospace,monospace;color:#fff">github.com/bald-ai/zoomies</span><span style="opacity:.35">•</span><span>macOS 14+</span><span style="opacity:.35">•</span><span>Free &amp; open source</span>');
    this.frame = Z.svg(root, 1400, 520, `<rect class="fr" x="0" y="0" width="1400" height="520" rx="26" fill="none" stroke="${Z.C.dash}" stroke-width="4" stroke-dasharray="20 14" pathLength="1000" opacity=".55"/>`);
    this.fr = this.frame.querySelector('.fr');
    this.black = Z.el(root, 'div', { width: '1920px', height: '1080px', background: '#000' });
  },
  render(t) {
    t -= Z.b(L6S);
    const B = Z.b, e = Z.ease, I = this.icon, D = (Z.CFG.duration || 30) - Z.b(L6S);
    this.bg.render(t, 0, { do: 0.5 });
    const p = Z.soft(t - B(40), 1.2);
    Z.set(I.wrap, { x: 610, y: 470 + Math.sin(t * 1.6) * 5, s: 0.4 * (0.92 + 0.08 * p), o: p });
    I.ants(t, 30);
    const blink = (b0) => { const q = (t - B(b0)) / 0.22; return q > 0 && q < 1 ? Math.sin(q * Math.PI) : 0; };
    I.blink(Math.max(blink(43), blink(46)));
    const w = Z.soft(t - B(40.5), 0.9);
    Z.set(this.word, { x: 1195, y: 420 + (1 - w) * 24, o: w });
    const g = Z.soft(t - B(42), 0.9);
    Z.set(this.tag, { x: 1195, y: 550 + (1 - g) * 18, o: g });
    const fp = e.inOutCubic(Z.prog(t, B(44), B(45.2)));
    Z.set(this.frame, { x: 960, y: 480, o: fp > 0 ? 1 : 0 });
    this.fr.setAttribute('stroke-dasharray', fp >= 1 ? '20 14' : `${fp * 1000} 1000`);
    this.fr.style.strokeDashoffset = fp >= 1 ? -(t - B(45.2)) * 25 : 0;
    const u = Z.soft(t - B(44.3), 0.9);
    Z.set(this.url, { x: 960, y: 870 + (1 - u) * 16, o: u });
    Z.set(this.black, { x: 960, y: 540, o: Z.prog(t, D - 0.65, D - 0.05) });
  },
});

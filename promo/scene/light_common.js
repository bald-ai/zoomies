// Light cut helpers: calm easing, fade-ups, word reveals, step captions, shared hero-card geometry.
Z.L = {
  CAP_CARD: { x: 960, y: 610, s: 1.2 },  // login page inside the browser (capture shot)
  EDIT_CARD: { x: 960, y: 548, s: 1.08 }, // captured card inside the editor (and start of the agent shot)
  NOTE: 'fix 1 & 2 — button overflows the card, label is clipped',
};
Z.soft = (dt, dur = 0.8) => Z.ease.outQuint(Z.clamp(dt / dur));
Z.calm = (dt) => Z.spring(dt, 1.4, 0.78); // barely-overshooting settle
// opacity/offset envelope: in at t0 (dur), out at t1 (outDur)
Z.env = (t, t0, t1 = 1e9, dur = 0.7, outDur = 0.45) => Z.soft(t - t0, dur) * (1 - Z.ease.inOutCubic(Z.prog(t, t1, t1 + outDur)));
Z.words = (parent, text, css = {}) => {
  const line = Z.el(parent, 'div', { whiteSpace: 'nowrap', ...css });
  const spans = text.split(' ').map((w, i, a) => {
    const s = document.createElement('span'); s.innerHTML = w; s.style.display = 'inline-block';
    if (i < a.length - 1) s.style.marginRight = '0.26em';
    line.appendChild(s); return s;
  });
  return { line, spans };
};
Z.revealWords = (w, t, t0, stagger = 0.07, dist = 22) => w.spans.forEach((s, k) => {
  const p = Z.soft(t - t0 - k * stagger, 0.7);
  Z.setInline(s, { y: (1 - p) * dist, o: p, blur: (1 - p) * 4 });
});
// step caption, top-left editorial: [beat, badge, text] entries, crossfading
Z.caption = (root) => {
  const mk = () => {
    const c = Z.el(root, 'div', { left: '150px', top: '70px', display: 'flex', alignItems: 'center', gap: '22px', whiteSpace: 'nowrap' });
    const badge = Z.el(c, 'div', { position: 'relative', font: '700 26px ui-monospace, SFMono-Regular, monospace', color: Z.C.orange, padding: '6px 12px', borderRadius: '10px', border: '2px solid rgba(247,160,67,.5)' });
    const text = Z.el(c, 'div', { position: 'relative', font: '700 54px system-ui', color: '#fff', letterSpacing: '-0.01em' });
    return { c, badge, text };
  };
  const slots = [mk(), mk()];
  return {
    render(t, entries, tOut = 1e9) {
      const bt = t / Z.BEAT; let idx = -1;
      entries.forEach((e, i) => { if (bt >= e[0]) idx = i; });
      slots.forEach((s) => (s.c.style.opacity = 0));
      if (idx < 0) return;
      const out = 1 - Z.ease.inOutCubic(Z.prog(t, tOut, tOut + 0.4));
      const cur = slots[idx % 2], [b0, badge, text] = entries[idx], p = Z.soft(t - Z.b(b0) - (idx > 0 ? 0.25 : 0), 0.7);
      cur.badge.textContent = badge; cur.badge.style.display = badge ? '' : 'none'; cur.text.innerHTML = text;
      cur.c.style.opacity = p * out; cur.c.style.transform = `translateY(${(1 - p) * 18}px)`;
      if (idx > 0) {
        const prev = slots[(idx - 1) % 2], q = Z.prog(t, Z.b(b0), Z.b(b0) + 0.3);
        const [, pb, pt] = entries[idx - 1];
        prev.badge.textContent = pb; prev.badge.style.display = pb ? '' : 'none'; prev.text.innerHTML = pt;
        prev.c.style.opacity = (1 - q) * out; prev.c.style.transform = `translateY(${-q * 14}px)`;
      }
    },
  };
};
// annotated card: login page + drawable annotations + note strip (560x500 page, strip hangs below)
Z.annotatedCard = (parent) => {
  const wrap = Z.el(parent, 'div', { width: '560px', height: '500px' });
  const strip = Z.el(wrap, 'div', { top: '500px', width: '560px', height: '0px', background: '#1c1f21', overflow: 'hidden', borderRadius: '0 0 14px 14px', padding: '14px 22px 0', font: '600 21px/30px system-ui', color: '#f2f4f5' });
  const pageBox = Z.el(wrap, 'div', { width: '560px', height: '500px', borderRadius: '14px', overflow: 'hidden', boxShadow: '0 30px 80px rgba(0,0,0,.45)' });
  Z.loginPage(pageBox).page.style.background = '#e8ecf2';
  const ann = Z.svg(wrap, 560, 500, `
    <g fill="none" stroke="${Z.C.red}" stroke-linecap="round" stroke-linejoin="round" stroke-width="6">
      <rect class="rc" x="192" y="340" width="362" height="92" rx="10" pathLength="1"/></g>
    <g class="m1"><circle r="24" fill="none" stroke="${Z.C.red}" stroke-width="5"/><text y="9" text-anchor="middle" font-size="27" font-weight="800" font-family="system-ui" fill="${Z.C.red}">1</text></g>
    <g class="m2"><circle r="24" fill="none" stroke="${Z.C.red}" stroke-width="5"/><text y="9" text-anchor="middle" font-size="27" font-weight="800" font-family="system-ui" fill="${Z.C.red}">2</text></g>`);
  const rc = ann.querySelector('.rc'), m1 = ann.querySelector('.m1'), m2 = ann.querySelector('.m2');
  return {
    wrap, strip, pageBox,
    set({ rect = 1, mk1 = 1, mk2 = 1, note = 1, chars = 1e9 } = {}) {
      rc.style.strokeDasharray = `${rect} 1`; rc.style.opacity = rect > 0 ? 1 : 0;
      m1.setAttribute('transform', `translate(556 340) scale(${mk1})`);
      m2.setAttribute('transform', `translate(186 440) scale(${mk2})`);
      strip.style.height = note * 84 + 'px'; strip.style.display = note > 0 ? 'block' : 'none';
      pageBox.style.borderRadius = note > 0 ? '14px 14px 0 0' : '14px';
      const n = Math.min(Z.L.NOTE.length, Math.floor(chars));
      strip.textContent = Z.L.NOTE.slice(0, n);
    },
  };
};

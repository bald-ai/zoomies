// v3 F5 — beats 27.5-36: ⌘V the copied image (note burned in) into a coding agent (29.5 → lands 30), send (31.5),
// agent replies (33). No prompt typing: the note travels inside the image.
const F5S = Z.CFG.agentShift || 0;
Z.scene({
  name: 'agent', from: 27.5 + F5S, to: 36 + F5S,
  build(root) {
    this.g = Z.el(root, 'div', { width: '1920px', height: '1080px' });
    this.bg = Z.bg(this.g, { glowA: 'rgba(27,134,134,.22)', glowB: 'rgba(247,160,67,.10)' });
    this.chat = Z.el(this.g, 'div', { width: '1080px', height: '700px', borderRadius: '26px', background: 'linear-gradient(180deg,#1a1e20,#141718)', boxShadow: '0 0 0 1px rgba(255,255,255,.09), 0 50px 120px rgba(0,0,0,.5)', overflow: 'hidden' });
    const hdr = Z.el(this.chat, 'div', { width: '100%', height: '74px', borderBottom: '1px solid rgba(255,255,255,.06)', display: 'flex', alignItems: 'center', gap: '14px', padding: '0 30px', font: '700 25px system-ui', color: '#fff' });
    Z.symbol(hdr, 'sparkles', 28, Z.C.orange, { position: 'relative' }); hdr.appendChild(document.createTextNode('Coding agent'));
    this.input = Z.el(this.chat, 'div', { left: '30px', top: '566px', width: '1020px', height: '106px', borderRadius: '20px', background: '#22272a', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.09)' });
    this.ph = Z.el(this.input, 'div', { left: '28px', top: '35px', font: '500 27px system-ui', color: 'rgba(255,255,255,.35)' }, 'Message your agent…');
    this.send = Z.el(this.input, 'div', { left: '946px', top: '25px', width: '56px', height: '56px', borderRadius: '50%', background: Z.C.orange, display: 'flex', alignItems: 'center', justifyContent: 'center' });
    Z.symbol(this.send, 'arrow.right', 26, '#2a1405', { position: 'relative', transform: 'rotate(-90deg)' });
    this.dots = [0, 1, 2].map(() => Z.el(this.chat, 'div', { width: '16px', height: '16px', borderRadius: '50%', background: 'rgba(255,255,255,.55)' }));
    this.reply = Z.el(this.chat, 'div', { left: '30px', top: '400px', width: '640px', borderRadius: '22px 22px 22px 6px', background: '#262b2e', padding: '22px 26px', font: '500 26px/37px system-ui', color: '#e8eef0' }, '<b style="color:#45d0c4">Got it.</b> The Sign in button is wider than the card, so its label is cut off. Fixing <span style="font-family:ui-monospace,monospace;color:#f7a043">login.tsx</span>.');
    this.res = Z.R.resultImage(this.g, Z.CFG.ann === 'R4' ? Z.R4.annotations : undefined);
    this.sub = Z.R.subtitle(this.g);
  },
  render(t) {
    t -= Z.b(F5S);
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT, K = Z.R.key, P = Z.R.RESULT_POSE;
    const gIn = Z.soft(t - B(27.5), 0.6), out = e.inOutCubic(Z.prog(t, B(35.4), B(35.95)));
    this.g.style.opacity = gIn * (1 - out);
    this.bg.render(t, 0, { do: 0.5 });
    const cIn = Z.soft(t - B(28), 0.9), cx = 960, cy = 520 + (1 - cIn) * 30;
    Z.set(this.chat, { x: cx, y: cy, o: cIn });
    const L = cx - 540, T0 = cy - 350;
    // image: hero pose → input attachment on ⌘V → user message bubble on send
    const h = this.res.el.offsetHeight;
    const toSlot = e.inOutCubic(Z.prog(t, B(29.5), B(30))), toMsg = e.inOutCubic(Z.prog(t, B(31.5), B(32.2)));
    const sSlot = 0.13, sMsg = 0.4;
    const slot = [L + 30 + 70, T0 + 566 + 53], msg = [L + 1050 - (616 * sMsg) / 2, T0 + 100 + (h * sMsg) / 2];
    const hover = Z.lerp(0, 1, Z.soft(t - B(28), 0.8)) * (1 - toSlot);
    let x = Z.lerp(P.x, slot[0], toSlot), y = Z.lerp(P.y - hover * 0, slot[1], toSlot), s = Z.lerp(P.s, sSlot, toSlot);
    x = Z.lerp(x, msg[0], toMsg); y = Z.lerp(y, msg[1], toMsg); s = Z.lerp(s, sMsg, toMsg);
    Z.set(this.res.el, { x, y, s: s * (1 + Z.pulse(t - B(30), 10) * 0.08 * (bt >= 30)) });
    this.res.el.style.borderRadius = toMsg > 0 ? '14px' : '0'; this.res.el.style.overflow = 'hidden';
    this.ph.style.opacity = bt < 29.5 ? 1 : bt < 31.5 ? 0 : Z.soft(t - B(31.6), 0.4);
    this.ph.style.left = bt >= 29.8 && bt < 31.5 ? '130px' : '28px';
    this.send.style.transform = `scale(${1 + Z.pulse(t - B(31.5), 10) * 0.18})`;
    this.dots.forEach((d, i) => Z.set(d, { x: 60 + i * 28, y: 430 - Math.abs(Math.sin((t - B(32.2)) * 6 - i * 0.7)) * 10, o: bt > 32.2 && bt < 33 ? 0.9 : 0 }));
    const rP = Z.soft(t - B(33), 0.7);
    Z.setInline(this.reply, { y: (1 - rP) * 20, o: rP });
    this.sub.render(t, [
      [28.3, () => `${K('⌘', bt >= 29.5 && bt < 30)}${K('V', bt >= 29.5 && bt < 30)}<span>Paste into your agent</span>`],
      [30.4, '<span>The note travels <span style="color:#f7a043">inside</span> the image</span>'],
      [33.4, '<span>Your agent sees <span style="color:#f7a043">exactly</span> what you mean.</span>'],
    ], 1010, B(35.3));
  },
});

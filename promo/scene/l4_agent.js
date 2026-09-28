// L4 — beats 27.5-36: "03 Paste to your agent". Card glides from the editor into the chat input (paste 30),
// prompt typed, sent (32) as a message with the image, agent replies (34). Caption becomes the value line.
Z.scene({
  name: 'agent', from: 27.5, to: 36,
  build(root) {
    this.bg = Z.bg(root, { glowA: 'rgba(27,134,134,.22)', glowB: 'rgba(247,160,67,.10)' });
    this.cap = Z.caption(root);
    this.chat = Z.el(root, 'div', { width: '1080px', height: '700px', borderRadius: '26px', background: 'linear-gradient(180deg,#1a1e20,#141718)', border: '1px solid rgba(255,255,255,.09)', boxShadow: '0 50px 120px rgba(0,0,0,.5)', overflow: 'hidden' });
    const hdr = Z.el(this.chat, 'div', { width: '100%', height: '74px', borderBottom: '1px solid rgba(255,255,255,.06)', display: 'flex', alignItems: 'center', gap: '14px', padding: '0 30px', font: '700 25px system-ui', color: '#fff' });
    Z.symbol(hdr, 'sparkles', 28, Z.C.orange, { position: 'relative' }); hdr.appendChild(document.createTextNode('Coding agent'));
    this.input = Z.el(this.chat, 'div', { left: '30px', top: '566px', width: '1020px', height: '106px', borderRadius: '20px', background: '#22272a', border: '1px solid rgba(255,255,255,.09)' });
    this.ph = Z.el(this.input, 'div', { left: '28px', top: '36px', font: '500 27px system-ui', color: 'rgba(255,255,255,.35)' }, 'Message your agent…');
    this.inputText = Z.el(this.input, 'div', { left: '160px', top: '36px', font: '500 27px system-ui', color: '#fff', whiteSpace: 'pre' });
    this.send = Z.el(this.input, 'div', { left: '946px', top: '25px', width: '56px', height: '56px', borderRadius: '50%', background: Z.C.orange, display: 'flex', alignItems: 'center', justifyContent: 'center' });
    Z.symbol(this.send, 'arrow.right', 26, '#2a1405', { position: 'relative', transform: 'rotate(-90deg)' });
    this.bubble = Z.el(this.chat, 'div', { left: '470px', top: '110px', width: '580px', height: '150px', borderRadius: '22px 22px 6px 22px', background: '#2d5f63', padding: '24px 26px 24px 160px', font: '600 25px/35px system-ui', color: '#fff' }, 'fix 1 &amp; 2 — button overflows the card, label is clipped');
    this.dots = [0, 1, 2].map(() => Z.el(this.chat, 'div', { width: '16px', height: '16px', borderRadius: '50%', background: 'rgba(255,255,255,.55)' }));
    this.reply = Z.el(this.chat, 'div', { left: '30px', top: '300px', width: '660px', borderRadius: '22px 22px 22px 6px', background: '#262b2e', padding: '22px 26px', font: '500 26px/37px system-ui', color: '#e8eef0' }, '<b style="color:#45d0c4">Got it.</b> The button is wider than the card, so its label gets clipped. Fixing <span style="font-family:ui-monospace,monospace;color:#f7a043">login.tsx</span> now.');
    this.card = Z.annotatedCard(root);
    this.card.pageBox.style.boxShadow = '0 20px 50px rgba(0,0,0,.35)';
  },
  render(t) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT, E = Z.L.EDIT_CARD;
    this.bg.render(t, 0, { do: 0.5 });
    this.cap.render(t, [[28.2, '03', 'Paste to your agent'], [33.4, '', 'Your agent sees <span style="color:#f7a043">exactly</span> what you mean.']], B(35.4));
    const out = e.inOutCubic(Z.prog(t, B(35.4), B(35.95)));
    const cIn = Z.soft(t - B(28.2), 1);
    const cx = 960, cy = 600 + (1 - cIn) * 40;
    Z.set(this.chat, { x: cx, y: cy, o: cIn * (1 - out) });
    const chatL = cx - 540, chatT = cy - 350;
    // card: editor position → input attachment (30) → message bubble (32)
    const toSlot = e.inOutCubic(Z.prog(t, B(28.4), B(30))), toBub = e.inOutCubic(Z.prog(t, B(32), B(32.8)));
    const slot = [chatL + 30 + 76, chatT + 566 + 53], bub = [chatL + 470 + 80, chatT + 110 + 75];
    const s0 = E.s, sSlot = 0.16, sBub = 0.2;
    // card centre (incl. note strip) at the editor matches L3's wrap: wrap centre is page centre
    let x = Z.lerp(E.x, slot[0], toSlot), y = Z.lerp(E.y, slot[1] - 42 * sSlot, toSlot), s = Z.lerp(s0, sSlot, toSlot);
    x = Z.lerp(x, bub[0], toBub); y = Z.lerp(y, bub[1] - 42 * sBub, toBub); s = Z.lerp(s, sBub, toBub);
    Z.set(this.card.wrap, { x, y, s: s * (1 + Z.pulse(t - B(30), 10) * 0.08 * (bt > 30)), o: 1 - out });
    this.card.set({});
    // input: placeholder → typed prompt → cleared on send
    const typedN = Math.floor(Z.clamp((t - B(30.2)) / (B(31.3) - B(30.2))) * 34);
    const prompt = 'fix 1 & 2 — button overflows card';
    this.ph.style.opacity = bt < 30 ? 1 : 0;
    this.inputText.textContent = bt >= 30.2 && bt < 32 ? prompt.slice(0, typedN) + (Math.floor(t * 3) % 2 ? '|' : '') : '';
    this.send.style.transform = `scale(${1 + Z.pulse(t - B(32), 10) * 0.18})`;
    const bP = Z.soft(t - B(32.1), 0.6);
    Z.setInline(this.bubble, { y: (1 - bP) * 20, o: bP });
    this.dots.forEach((d, i) => {
      const on = bt > 32.5 && bt < 33.2;
      Z.set(d, { x: 60 + i * 28, y: 330 - Math.abs(Math.sin((t - B(32.5)) * 6 - i * 0.7)) * 10, o: on ? 0.9 : 0 });
    });
    const rP = Z.soft(t - B(33.2), 0.7);
    Z.setInline(this.reply, { y: (1 - rP) * 20, o: rP });
  },
});

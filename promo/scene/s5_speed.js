// S5 — beats 40-56: "2s → 3s → 5s" rolling-digit stopwatch (hits 40/44/48) with orbiting real SF Symbols and
// accumulating step chips; then the annotated capture flies into an agent chat (51), pastes (52), sends, agent
// replies, riser push-in and white-out into the finale at 56.
Z.scene({
  name: 'speed', from: 40, to: 56,
  build(root) {
    this.bg = Z.bg(root, { glowB: 'rgba(247,160,67,.3)' });
    this.wash = Z.el(root, 'div', { width: '1920px', height: '1080px' });
    this.g = Z.el(root, 'div', { width: '1920px', height: '1080px', transformOrigin: '960px 500px' });
    // stopwatch ring + ticks
    const ticks = Array.from({ length: 60 }, (_, i) => { const a = (i / 60) * Math.PI * 2, r0 = i % 5 ? 372 : 360; return `<line x1="${Math.cos(a) * r0}" y1="${Math.sin(a) * r0}" x2="${Math.cos(a) * 385}" y2="${Math.sin(a) * 385}" stroke="rgba(255,255,255,${i % 5 ? 0.18 : 0.45})" stroke-width="${i % 5 ? 3 : 5}"/>`; }).join('');
    this.ticks = Z.svg(this.g, 800, 800, `<g transform="translate(400 400)">${ticks}</g>`);
    this.ring = Z.svg(this.g, 800, 800, `<g transform="translate(400 400) rotate(-90)"><circle r="330" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="22"/><circle class="arc" r="330" fill="none" stroke="${Z.C.orange}" stroke-width="22" stroke-linecap="round" pathLength="1" stroke-dasharray="0 1"/></g>`);
    this.arc = this.ring.querySelector('.arc');
    // rolling digits
    this.mask = Z.el(this.g, 'div', { width: '300px', height: '400px', overflow: 'hidden' });
    this.col = Z.el(this.mask, 'div', { width: '300px', font: '900 400px/400px ui-rounded, system-ui', color: '#fff', textAlign: 'center' }, ['2', '3', '4', '5'].map((d) => `<div style="height:400px">${d}</div>`).join(''));
    this.col.className = 'rounded';
    this.sfx = Z.el(this.g, 'div', { font: '900 200px ui-rounded, system-ui', color: Z.C.orange }, 's');
    this.cap = Z.el(this.g, 'div', { font: '700 38px system-ui', letterSpacing: '.3em', color: 'rgba(230,248,245,.85)', whiteSpace: 'nowrap' }, 'SCREEN → AGENT IN');
    this.orbit = ['camera', 'pencil.tip', 'arrow.right', '1.circle', 'textformat', 'doc.on.clipboard', 'rectangle.dashed', 'keyboard'].map((n, i) => {
      const c = Z.el(this.g, 'div', { width: '96px', height: '96px', borderRadius: '28px', background: i % 2 ? 'rgba(27,134,134,.9)' : 'rgba(43,46,46,.95)', border: '1.5px solid rgba(255,255,255,.14)', boxShadow: '0 16px 40px rgba(0,0,0,.45)', display: 'flex', alignItems: 'center', justifyContent: 'center' });
      Z.symbol(c, n, 50, i % 2 ? '#fff' : Z.C.orange, { position: 'relative' });
      return c;
    });
    this.chips = [['doc.on.clipboard', 'Capture + copy'], ['pencil.tip', '+ Rename'], ['textformat', '+ Annotate & prompt']].map(([n, txt], i) => {
      const c = Z.el(this.g, 'div', { display: 'flex', alignItems: 'center', gap: '14px', padding: '14px 26px 14px 20px', borderRadius: '999px', background: i === 2 ? Z.C.orange : 'rgba(255,255,255,.1)', border: '1.5px solid rgba(255,255,255,.15)', font: '700 34px system-ui', color: i === 2 ? '#2a1405' : '#fff', whiteSpace: 'nowrap' });
      Z.symbol(c, n, 34, i === 2 ? '#2a1405' : Z.C.dash, { position: 'relative' });
      c.appendChild(document.createTextNode(txt));
      return c;
    });
    // agent chat
    this.chat = Z.el(root, 'div', { width: '1120px', height: '700px', borderRadius: '28px', background: 'linear-gradient(180deg,#1a1e20,#131617)', border: '1.5px solid rgba(255,255,255,.1)', boxShadow: '0 60px 140px rgba(0,0,0,.6)', overflow: 'hidden' });
    const hdr = Z.el(this.chat, 'div', { width: '100%', height: '76px', borderBottom: '1px solid rgba(255,255,255,.07)', display: 'flex', alignItems: 'center', gap: '14px', padding: '0 30px', font: '700 26px system-ui', color: '#fff' });
    Z.symbol(hdr, 'sparkles', 30, Z.C.orange, { position: 'relative' }); hdr.appendChild(document.createTextNode('Coding agent'));
    this.input = Z.el(this.chat, 'div', { left: '30px', top: '560px', width: '1060px', height: '110px', borderRadius: '22px', background: '#22272a', border: '1.5px solid rgba(255,255,255,.1)' });
    this.inputText = Z.el(this.input, 'div', { left: '150px', top: '36px', font: '500 28px system-ui', color: '#fff', whiteSpace: 'pre' });
    this.send = Z.el(this.input, 'div', { left: '980px', top: '27px', width: '56px', height: '56px', borderRadius: '50%', background: Z.C.orange, display: 'flex', alignItems: 'center', justifyContent: 'center' });
    Z.symbol(this.send, 'arrow.right', 28, '#2a1405', { position: 'relative', transform: 'rotate(-90deg)' });
    this.bubble = Z.el(this.chat, 'div', { width: '560px', height: '150px', borderRadius: '22px 22px 6px 22px', background: '#2d5f63', padding: '22px 26px 22px 150px', font: '600 26px/36px system-ui', color: '#fff' }, 'fix 1 &amp; 2 — button overflows the card, label is clipped');
    this.dots = [0, 1, 2].map(() => Z.el(this.chat, 'div', { width: '18px', height: '18px', borderRadius: '50%', background: 'rgba(255,255,255,.6)' }));
    this.reply = Z.el(this.chat, 'div', { width: '640px', borderRadius: '22px 22px 22px 6px', background: '#262b2e', padding: '22px 26px', font: '500 26px/36px system-ui', color: '#e8eef0' }, '<b style="color:#45d0c4">On it.</b> Button width overflows the card and truncates the label. Fixing <span style="font-family:ui-monospace,monospace;color:#f7a043">login.tsx</span>…');
    // annotated thumbnail (same components as the editor result)
    this.thumb = Z.el(root, 'div', { width: '560px', height: '584px', borderRadius: '16px', overflow: 'hidden', boxShadow: '0 30px 70px rgba(0,0,0,.55), 0 0 0 2px rgba(255,255,255,.2)' });
    Z.loginPage(this.thumb);
    Z.svg(this.thumb, 560, 500, `<g fill="none" stroke="${Z.C.red}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"><rect x="192" y="340" width="362" height="92" rx="10"/><path d="M 505 150 Q 470 250 470 330"/><path d="M 450 305 L 470 334 L 492 306"/></g><g fill="none" stroke="${Z.C.red}" stroke-width="5"><circle cx="556" cy="340" r="24"/><circle cx="186" cy="440" r="24"/></g><g fill="${Z.C.red}" font-size="27" font-weight="800" font-family="system-ui" text-anchor="middle"><text x="556" y="349">1</text><text x="186" y="449">2</text></g>`);
    Z.el(this.thumb, 'div', { top: '500px', width: '560px', height: '84px', background: '#1c1f21', padding: '12px 20px', font: '600 21px/30px system-ui', color: '#f2f4f5' }, 'fix 1 &amp; 2 — button overflows the card, label is clipped');
    this.headline = Z.letters(root, 'Context travels with the image.', { font: '800 70px system-ui', color: '#fff', textShadow: '0 10px 40px rgba(0,0,0,.6)' });
    [40, 44, 48].forEach((b) => Z.shake(b, 30, 6)); Z.shake(52, 20, 7); Z.shake(53.5, 8);
  },
  render(t, root, { fx }) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT;
    const kick = Z.beatPulse(t, 40, 56);
    this.bg.render(t, kick);
    const hits = [40, 44, 48], cols = ['rgba(247,160,67,', 'rgba(27,134,134,', 'rgba(255,243,220,'];
    let hi = 0; hits.forEach((b, i) => { if (bt >= b) hi = i; });
    const hd = t - B(hits[hi]);
    this.wash.style.background = cols[hi] + (Z.pulse(hd, 5) * 0.75) + ')';
    Z.flash(Z.pulse(t - B(40), 10) * 0.6 + Z.pulse(t - B(52), 12) * 0.35 + e.inExpo(Z.prog(t, B(55), B(56))));
    // group in (whip from right) / out (up) + riser push
    const inP = e.outExpo(Z.prog(t, B(40), B(40.5))), out = e.inBack(Z.prog(t, B(50.25), B(51)), 1.4);
    Z.set(this.g, { x: 960 + (1 - inP) * 1400, y: 540 - out * 1100, sx: 1 + (1 - inP) * 0.5, blur: (1 - inP) * 40 + out * 10, s: 1 + kick * 0.02 });
    const slam = Z.pulse(hd, 7);
    // stopwatch
    const val = [2, 3, 5][hi], prevVal = [0, 2, 3][hi], sp = Z.spring(hd, 2.2, 0.35);
    this.arc.setAttribute('stroke-dasharray', `${Z.lerp(prevVal, val, sp) / 6} 1`);
    this.arc.setAttribute('stroke', hi === 1 ? Z.C.dash : Z.C.orange);
    Z.set(this.ring, { x: 960, y: 480, s: 1 + slam * 0.08, r: 0 });
    Z.set(this.ticks, { x: 960, y: 480, r: t * 20 + Z.spring(hd, 2, 0.3) * 30 * hi, s: 1 + slam * 0.05 });
    // digit roller
    const idx = [0, 1, 3][hi], prevIdx = [0, 0, 1][hi], rs = Z.spring(hd, 2.6, 0.3);
    this.col.style.transform = `translateY(${-Z.lerp(prevIdx, idx, rs) * 400}px)`;
    const numIn = e.outExpo(Z.prog(t, B(40), B(40.35)));
    Z.set(this.mask, { x: 910, y: 480, s: (3 - 2 * numIn) * (1 + slam * 0.1), blur: (1 - numIn) * 20, r: Z.wobble(hd, 3, 6) * 4 });
    Z.set(this.sfx, { x: 1100, y: 540, s: Z.spring(t - B(40.25), 3, 0.3) * (1 + slam * 0.15), r: Z.wobble(hd - 0.05, 3, 6) * -10 });
    const capP = Z.spring(t - B(40.5), 2.6, 0.4);
    Z.set(this.cap, { x: 960, y: 120 + (1 - capP) * -40, o: Z.clamp(capP) });
    // orbiting icons (depth-sorted ellipse), react to kicks
    const spin = t * 0.9 + e.outExpo(Z.prog(t, B(44), B(44.6))) * 1.2 + e.outExpo(Z.prog(t, B(48), B(48.6))) * 1.2;
    this.orbit.forEach((c, i) => {
      const a = spin + (i / this.orbit.length) * Math.PI * 2, depth = Math.sin(a);
      const pop = Z.spring(t - B(40.5 + i * 0.125), 3, 0.35);
      Z.set(c, { x: 960 + Math.cos(a) * 560, y: 480 + depth * 250, s: pop * (0.75 + 0.3 * (depth + 1) / 2) * (1 + kick * 0.12), r: Math.cos(a) * 10, o: 0.55 + 0.45 * (depth + 1) / 2 });
      c.style.zIndex = depth > 0 ? 5 : 0;
    });
    this.mask.style.zIndex = 3; this.sfx.style.zIndex = 3;
    // step chips accumulate
    let cx = 0; const widths = this.chips.map((c) => c.offsetWidth), total = widths.reduce((a, b) => a + b, 0) + 64;
    this.chips.forEach((c, i) => {
      const dt = t - B(hits[i]), p = Z.spring(dt, 3, 0.35);
      Z.set(c, { x: 960 - total / 2 + cx + widths[i] / 2, y: 930 + (1 - p) * 80, s: Z.clamp(p * 1.3, 0, 1.1) * (1 + Z.pulse(dt, 9) * 0.06), o: dt > 0 ? 1 : 0 });
      cx += widths[i] + 32;
    });
    Z.fx.speedLines(fx, hd, 960, 480, { n: 40, r0: 420, r1: 1300, life: 0.45, width: 7, color: hi === 1 ? '#45d0c4' : '#fff3dc' });
    Z.fx.burst(fx, hd, 960, 480, { n: 60, seed: 40 + hi, speed: 1800, size: 14, life: 1.1, gravity: 1300 });
    // chat
    const chatP = Z.spring(t - B(50.5), 1.8, 0.45);
    const push = e.inCubic(Z.prog(t, B(52), B(56)));
    Z.camera.s = 1 + push * 0.22; Z.camera.r = push * -2;
    Z.set(this.chat, { x: 960, y: 590 + (1 - chatP) * 900, r: (1 - chatP) * 8, o: bt > 50.4 ? 1 : 0 });
    // thumbnail flight: arc from left into input attachment slot, then up into the bubble on send
    const fl = e.inOutCubic(Z.prog(t, B(51), B(52))), sendP = e.outExpo(Z.prog(t, B(53.5), B(54.1)));
    const chatX = 960 - 560, chatY = 590 + (1 - chatP) * 900 - 350;   // chat top-left on screen
    const slot = [chatX + 30 + 75, chatY + 560 + 55], bub = [chatX + 1090 - 560 + 70, chatY + 290];
    const land = Z.wobble(t - B(52), 3, 7) * (bt > 52 ? 1 : 0);
    let tx = Z.lerp(-300, slot[0], fl), ty = Z.lerp(700, slot[1], fl) - Math.sin(fl * Math.PI) * 380;
    let ts = Z.lerp(0.9, 0.19, e.inCubic(fl));
    tx = Z.lerp(tx, bub[0], sendP); ty = Z.lerp(ty, bub[1], sendP); ts = Z.lerp(ts, 0.22, sendP);
    Z.set(this.thumb, { x: tx, y: ty, s: ts, sx: 1 + land * 0.2, sy: 1 - land * 0.2, r: (1 - fl) * -25 + Math.sin(fl * Math.PI) * 10, o: bt > 51 ? 1 : 0 });
    Z.fx.ring(fx, t - B(52), slot[0], slot[1], { r0: 30, r1: 220, width: 10, color: Z.C.orange, life: 0.5 });
    Z.fx.burst(fx, t - B(52), slot[0], slot[1], { n: 30, seed: 52, speed: 900, size: 10, life: 0.8 });
    const typed = 'fix 1 & 2 — button overflows the card…';
    const nChars = Math.max(0, Math.min(typed.length, Math.floor((bt - 52.25) * 26)));
    this.inputText.textContent = bt < 53.5 ? typed.slice(0, nChars) + (Math.floor(t * 4) % 2 ? '|' : ' ') : '';
    this.send.style.transform = `scale(${1 + Z.pulse(t - B(53.5), 10) * 0.4 + kick * 0.06})`;
    const bP = Z.spring(t - B(53.5), 2.8, 0.4);
    Z.set(this.bubble, { x: 1090 - 280, y: 290, s: Z.clamp(bP * 1.2, 0, 1.1), o: bt > 53.5 ? 1 : 0 });
    this.bubble.style.transformOrigin = '100% 100%';
    this.dots.forEach((d, i) => {
      const on = bt > 54 && bt < 55;
      Z.set(d, { x: 70 + i * 30, y: 440 - Math.abs(Math.sin((t - B(54)) * 9 - i * 0.7)) * 14, o: on ? 1 : 0 });
    });
    const rP = Z.spring(t - B(55), 2.8, 0.4);
    Z.set(this.reply, { x: 30 + 320, y: 470, s: Z.clamp(rP * 1.2, 0, 1.1), o: bt > 55 ? 1 : 0 });
    // headline at 52 (cascade)
    const hp = t - B(52.25);
    Z.set(this.headline.line, { x: 960, y: 115, o: 1 });
    this.headline.spans.forEach((s, k) => {
      const p = Z.spring(hp - k * 0.015, 3, 0.4);
      Z.setInline(s, { y: (1 - p) * 60, o: hp - k * 0.015 > 0 ? 1 : 0, s: Z.clamp(p * 1.2, 0, 1.1), blur: (1 - Z.clamp(p)) * 8 });
      s.style.color = k >= 21 ? Z.C.orange : '#fff';
    });
  },
});

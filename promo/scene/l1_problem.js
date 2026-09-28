// L1 — beats 0-8: the problem. Describing a UI bug in words is slow and vague → "Show it instead." (b6).
Z.scene({
  name: 'problem', from: 0, to: 8,
  build(root) {
    this.bg = Z.bg(root, { glowA: 'rgba(27,134,134,.22)', glowB: 'rgba(247,160,67,.10)' });
    this.group = Z.el(root, 'div', { width: '1920px', height: '1080px' });
    this.q = Z.words(this.group, 'Explaining a UI bug to your agent?', { font: '700 72px system-ui', color: '#fff', letterSpacing: '-0.01em' });
    this.who = Z.el(this.group, 'div', { left: '510px', top: '410px', font: '600 24px system-ui', color: 'rgba(230,240,242,.5)' }, 'You');
    this.bubble = Z.el(this.group, 'div', { left: '510px', top: '450px', width: '900px', borderRadius: '28px 28px 28px 8px', background: '#22282b', border: '1px solid rgba(255,255,255,.07)', padding: '28px 34px', font: '500 32px/46px system-ui', color: '#dfe6e8', whiteSpace: 'pre-wrap' });
    this.msg = 'so the sign in button on the login page is kind of pushed off to the right? and the text is cut off, it says "Sign i" and it sticks out of the white card thing, and it\'s tilted a bit…';
    this.show = Z.words(root, 'Show it instead.', { font: '800 120px system-ui', color: '#fff', letterSpacing: '-0.02em' });
    this.show.spans[2].style.color = Z.C.orange;
  },
  render(t) {
    const B = Z.b;
    this.bg.render(t, 0, { do: 0.5 });
    Z.set(this.q.line, { x: 960, y: 300 });
    Z.revealWords(this.q, t, B(0.3), 0.09);
    const bubO = Z.soft(t - B(3), 0.6);
    Z.setInline(this.bubble, { y: (1 - bubO) * 24, o: bubO });
    Z.setInline(this.who, { o: bubO });
    const n = Math.floor(Z.clamp((t - B(3.2)) / (B(5.6) - B(3.2))) * this.msg.length);
    this.bubble.textContent = this.msg.slice(0, n) + (t < B(6) && Math.floor(t * 3) % 2 ? '|' : '');
    // dim the problem when the answer lands
    const dim = Z.ease.inOutCubic(Z.prog(t, B(5.8), B(6.4)));
    Z.set(this.group, { x: 960, y: 540 - dim * 40, o: 1 - dim * 0.9, blur: dim * 8 });
    Z.set(this.show.line, { x: 960, y: 540, o: 1 - Z.ease.inOutCubic(Z.prog(t, B(7.2), B(7.9))), s: 1 - Z.prog(t, B(7.2), B(7.9)) * 0.04 });
    Z.revealWords(this.show, t, B(6), 0.12, 30);
  },
});

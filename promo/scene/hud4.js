// v4 HUD (last layer, screen space): flow indicator, transition recaps, rename option cards, left-hand keyboard,
// key callouts and subtitles for beats 8-54.
Z.scene({
  name: 'hud4', from: 8, to: 54,
  build(root) {
    this.root = root; root.style.transformOrigin = '960px 540px';
    this.cards = Z.R4.optionCards(root);
    this.kb = Z.R4.keyboard(root);
    this.callout = Z.el(root, 'div', { display: 'flex', alignItems: 'center', gap: '14px', font: '800 44px system-ui', color: '#fff', whiteSpace: 'nowrap' });
    this.flow = Z.R4.flow(root);
    this.recap = Z.R4.recap(root);
    this.sub = Z.R.subtitle(root);
  },
  render(t) {
    const c = Z.camera, B = Z.b, bt = t / Z.BEAT, K = Z.R.key, T = Z.R4.txt;
    this.root.style.transform = `scale(${1 / c.s}) rotate(${-c.r}deg) translate(${-c.x}px,${-c.y}px)`;
    const hot = (b, len = 0.45) => bt >= b && bt < b + len;
    // rename option cards
    this.cards.render(t, [13, 14, 15, 16, 17], B(17.9));
    // flow indicator
    const fv = Z.soft(t - B(12.4), 0.5) * (1 - Z.ease.inOutCubic(Z.prog(t, B(52.2), B(52.7))));
    this.flow.render(t, [[12.3, 0, ''], [20.75, 1, K('Tab')], [25, 0, K('⇧') + K('Tab')], [26.5, 1, K('Tab')], [28, 2, K('Tab')], [48.5, 1, K('⇧') + K('Tab')], [50.5, 2, K('Tab')]], fv, 66);
    // what was pressed, on every window transition
    this.recap.render(t, [
      { b: 12.1, title: 'Capture', keys: ['⌥', '⇧', '4', T('drag')] },
      { b: 20.8, title: 'Rename', keys: [T('typed a name'), 'Tab'] },
      { b: 25.05, title: 'Note', keys: [T('typed a note'), K('⇧') + K('Tab')], len: 1.4 },
      { b: 26.55, title: 'Rename', keys: [T('name kept'), 'Tab'], len: 1.4 },
      { b: 28.05, title: 'Note', keys: [T('note kept'), 'Tab'], len: 2.2 },
      { b: 48.55, title: 'Editor', keys: [K('⇧') + K('Tab'), T('annotations kept')], len: 1.9 },
      { b: 50.55, title: 'Note', keys: ['Tab'], len: 1.4 },
      { b: 52.1, title: 'Editor', keys: [K('⌘') + T(' hold'), 'W', 'D', 'A', 'R', 'Q', 'E', 'T', '1', 'F', 'S', K('⌘') + K('Z'), K('⌘') + K('⇧') + K('Z'), K('⌘') + K('↩')], len: 2.4, s: 0.92 },
    ], 158);
    // left-hand keyboard (editor phase)
    const kv = Z.soft(t - B(28.6), 0.6) * (1 - Z.ease.inOutCubic(Z.prog(t, B(52.1), B(52.5))));
    const noteUp = Z.ease.inOutCubic(Z.prog(t, B(48.5), B(48.8))) * (1 - Z.ease.inOutCubic(Z.prog(t, B(50.5), B(50.8))));
    const kvk = kv * (1 - noteUp);
    Z.set(this.kb.el, { x: 380 - (1 - kvk) * 40, y: 590, o: kvk });
    const lit = {};
    const press = (k, b, hold = 0.3) => { const dt = t - B(b); if (dt < 0) return; lit[k] = Math.max(lit[k] || 0, dt < hold ? 1 : Z.pulse(dt - hold, 5)); };
    if (bt >= 30 && bt < 32) lit['⌘'] = 1; else press('⌘', 32, 0);
    let cur = null;
    for (const s of Z.G4.SEQ) { s[1].forEach((k) => press(k, s[0])); if (bt >= s[0]) cur = s; }
    if (bt >= 30 && bt < 32.5) cur = [30, ['⌘'], -1, 'Hold: see every shortcut'];
    this.kb.render(lit);
    const cp = cur ? Z.soft(t - B(cur[0]), 0.35) : 0;
    if (cur && this.callout._c !== cur) { this.callout.innerHTML = cur[1].map((k) => K(k, true)).join('') + (cur[0] === 52 ? K('↩', true) : '') + `<span>${cur[3]}</span>`; this.callout._c = cur; }
    Z.set(this.callout, { x: 380, y: 895 + (1 - cp) * 12, o: cp * kvk });
    // subtitles
    this.sub.render(t, [
      [8.4, () => `${K('⌥', hot(9))}${K('⇧', hot(9.25))}${K('4', hot(9.5))}<span>Capture an area</span>`],
      [12.4, '<span style="color:#f7a043">Rename</span><span>Finish from here, or keep going</span>'],
      [18.1, () => `<span style="color:#f7a043">Rename</span><span>Type a name</span>${K('Tab', hot(20.75))}`],
      [21.25, '<span style="color:#f7a043">Note</span><span>Say what\'s wrong</span>'],
      [24.6, () => `${K('⇧', hot(25))}${K('Tab', hot(25))}<span>Back</span><span style="opacity:.5">·</span>${K('Tab', hot(26.5) || hot(28))}<span>Forward. Nothing is lost.</span>`],
      [28.6, () => `<span style="color:#f7a043">Editor</span>${K('⌘', bt >= 30 && bt < 32)}<span>Hold ⌘ to see every shortcut</span>`],
      [32.3, '<span style="color:#f7a043">Editor</span><span>One key per tool, all under your left hand</span>'],
      [45.8, () => `${K('⌘')}${K('Z', hot(46))}<span>Undo</span>${K('⌘')}${K('⇧')}${K('Z', hot(47))}<span>Redo</span>`],
      [48.3, () => `${K('⇧', hot(48.5))}${K('Tab', hot(48.5))}<span>Back to the note</span>${K('Tab', hot(50.5))}<span>Return</span>`],
      [51.8, () => `${K('⌘', hot(52, 0.8))}${K('↩', hot(52, 0.8))}<span>Copy + save</span>`],
    ], 1010, B(53.1));
  },
});

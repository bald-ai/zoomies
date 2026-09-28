// v3 F3 — beats 12-20: the real Rename panel (12.3; auto name selected, "login-button-bug" typed 13-15, Tab 15.5)
// then the real Note panel (16; note typed 16.5-19, Tab 19.5 → editor).
Z.scene({
  name: 'panels', from: 12, to: 20.2,
  build(root) {
    this.rename = Z.R.renamePanel(root);
    this.note = Z.R.notePanel(root);
  },
  render(t) {
    const B = Z.b, bt = t / Z.BEAT, R = Z.R;
    const blink = Math.floor(t * 2.4) % 2 === 0;
    // rename
    const rIn = Z.soft(t - B(12.3), 0.45), rOut = Z.ease.inOutCubic(Z.prog(t, B(15.6), B(15.95)));
    Z.set(this.rename.el, { x: 960, y: 500 + (1 - rIn) * 16, s: 0.98 + 0.02 * rIn, o: rIn * (1 - rOut) });
    const n = Math.max(0, Math.min(R.NAME.length, Math.floor((bt - 13) / 0.125) + 1));
    this.rename.set(t, { selected: bt < 13 ? R.NAME0 : null, typed: R.NAME.slice(0, n), caretOn: bt < 15 || blink, tabGlow: Z.pulse(t - B(15.5), 5) * (bt >= 15.5) });
    // note
    const nIn = Z.soft(t - B(16), 0.45), nOut = Z.ease.inOutCubic(Z.prog(t, B(19.6), B(19.95)));
    Z.set(this.note.el, { x: 960, y: 500 + (1 - nIn) * 16, s: 0.98 + 0.02 * nIn, o: nIn * (1 - nOut) });
    const m = Math.floor(Z.clamp((t - B(16.5)) / (B(19) - B(16.5))) * R.NOTE.length);
    this.note.set(t, { typed: R.NOTE.slice(0, m), caretOn: (bt > 16.5 && bt < 19) || blink, tabGlow: Z.pulse(t - B(19.5), 5) * (bt >= 19.5) });
  },
});

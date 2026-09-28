// v4 G3 — the real Rename and Note panels with Tab / Shift+Tab movement:
// Rename 12.3 (options spotlight 13-17, type 18.25-20.25, Tab 20.75) → Note 21.25 (type 21.75-24.25, ⇧Tab 25)
// → Rename 25.3 (Tab 26.5) → Note 26.6 (Tab 28) → [editor] → ⇧Tab 48.5 → Note 48.6 (Tab 50.5) → [editor].
Z.scene({
  name: 'panels4', from: 12, to: 51,
  build(root) {
    this.rename = Z.R.renamePanel(root);
    this.note = Z.R.notePanel(root);
  },
  render(t) {
    const B = Z.b, bt = t / Z.BEAT, R = Z.R;
    const blink = Math.floor(t * 2.4) % 2 === 0;
    const win = (a, b) => Z.soft(t - B(a), 0.4) * (1 - Z.ease.inOutCubic(Z.prog(t, B(b), B(b) + 0.25)));
    const glow = (e, on, b) => { if (on) e.style.color = `rgba(255,255,255,${0.55 + 0.45 * Z.clamp(Z.pulse(t - B(b), 3) * 1.5)})`; };
    // Rename
    const r1 = win(12.3, 20.85), r2 = win(25.3, 26.55), rO = Math.max(r1, r2);
    const ry = bt < 18 ? 440 : Z.lerp(440, 500, Z.ease.inOutCubic(Z.prog(t, B(18), B(18.5))));
    Z.set(this.rename.el, { x: 960, y: (bt < 25 ? ry : 500) + (1 - rO) * 14, s: 0.98 + 0.02 * rO, o: rO });
    const n = Math.max(0, Math.min(R.NAME.length, Math.floor((bt - 18.25) / 0.125) + 1));
    this.rename.set(t, { selected: bt < 18.25 ? R.NAME0 : null, typed: R.NAME.slice(0, n), caretOn: (bt > 18.25 && bt < 20.3) || blink });
    const opt = [13, 14, 15, 16, 17].reduce((a, b, i) => (bt >= b && bt < 18 ? i : a), -1);
    this.rename.hints.forEach((h, i) => (h.style.color = ''));
    if (opt >= 0) glow(this.rename.hints[opt], true, 13 + opt);
    glow(this.rename.hints[4], bt >= 20.75 && bt < 21.1, 20.75);
    glow(this.rename.hints[4], bt >= 26.5 && bt < 26.9, 26.5);
    // Note
    const n1 = win(21.25, 25.05), n2 = win(26.6, 28.05), n3 = win(48.6, 50.55), nO = Math.max(n1, n2, n3);
    Z.set(this.note.el, { x: 960, y: 500 + (1 - nO) * 14, s: 0.98 + 0.02 * nO, o: nO });
    const m = Math.floor(Z.clamp((t - B(21.75)) / (B(24.25) - B(21.75))) * R.NOTE.length);
    this.note.set(t, { typed: R.NOTE.slice(0, m), caretOn: (bt > 21.75 && bt < 24.3) || blink });
    this.note.hints.forEach((h) => (h.style.color = ''));
    glow(this.note.hints[4], bt >= 25 && bt < 25.4, 25);
    glow(this.note.hints[5], bt >= 28 && bt < 28.4, 28);
    glow(this.note.hints[5], bt >= 50.5 && bt < 50.9, 50.5);
  },
});

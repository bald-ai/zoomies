// v4 G4 — the real Editor (28.4-52): ⌘ hold badges 30-32, then every left-hand tool key in turn, undo/redo,
// ⇧Tab to the note and back (48.5 / 50.5), ⌘↩ at 52 → saved image with the note burned in → RESULT_POSE.
Z.R.RESULT_POSE = { x: 960, y: 520, s: 0.82 };
Z.G4 = { X: 1250, Y: 560, S: 0.9 };
Z.G4.SEQ = [ // [beat, key(s) for the keyboard, toolbar button index (-1 = no tool change), callout]
  [32.5, ['W'], 0, 'Pen'], [33.75, ['D'], 1, 'Line'], [35, ['A'], 2, 'Arrow'], [36.25, ['R'], 3, 'Rectangle'],
  [37.5, ['Q'], -1, 'Next colour'], [38.5, ['E'], 4, 'Ellipse'], [39.75, ['T'], 5, 'Text'], [41.25, ['1'], -1, 'Colour 1'],
  [42.25, ['F'], 6, 'Numbered marker'], [44.25, ['S'], 7, 'Select + move'], [46, ['⌘', 'Z'], -1, 'Undo'],
  [47, ['⌘', '⇧', 'Z'], -1, 'Redo'], [48.5, ['⇧', 'Tab'], -1, 'Back to note'], [50.5, ['Tab'], -1, 'Forward to editor'],
  [52, ['⌘'], -1, 'Copy + save'],
];
Z.scene({
  name: 'editor4', from: 28, to: 54,
  build(root) {
    this.ed = Z.R.editor(root, Z.R4.annotations);
    this.badges = Z.R4.badges(this.ed);
    this.res = Z.R.resultImage(root, Z.R4.annotations);
  },
  render(t) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT, ed = this.ed, G = Z.G4;
    ed.layout();
    const vis = Z.soft(t - B(28.4), 0.45) * (1 - e.inOutCubic(Z.prog(t, B(48.55), B(48.8))))
      + Z.soft(t - B(50.6), 0.4) * (1 - e.inOutCubic(Z.prog(t, B(52.1), B(52.45))));
    Z.set(ed.el, { x: G.X, y: G.Y + (1 - Z.clamp(vis)) * 14, s: G.S * (0.98 + 0.02 * Z.clamp(vis)), o: vis });
    this.badges(Z.soft(t - B(30), 0.3) * (1 - Z.ease.inOutCubic(Z.prog(t, B(32), B(32.3)))), t);
    let tool = 0; for (const [b, , idx] of G.SEQ) if (bt >= b && idx >= 0) tool = idx;
    ed.setActive(tool);
    ed.tb.swatch.style.background = bt >= 37.5 && bt < 41.25 ? Z.R4.blue : Z.R.red;
    ed.tb.swatch.style.transform = `scale(${1 + (Z.pulse(t - B(37.5), 8) * (bt >= 37.5) + Z.pulse(t - B(41.25), 8) * (bt >= 41.25)) * 0.35})`;
    const P = (a, d) => Z.clamp((t - B(a)) / d);
    const moved = bt >= 44.6 && !(bt >= 46 && bt < 47);
    const mv = bt < 46 ? e.inOutCubic(P(44.6, 0.45)) : moved ? 1 : 0;
    ed.ann.set({
      pen: e.inOutCubic(P(32.65, 0.5)), line: e.outCubic(P(33.9, 0.3)), arrow: e.outCubic(P(35.15, 0.3)), head: Z.calm(t - B(35.15) - 0.3),
      rect: e.inOutCubic(P(36.4, 0.4)), ellipse: e.inOutCubic(P(38.65, 0.4)), text: P(39.9, 0.55),
      mk1: Z.calm(t - B(42.6)), mk2: Z.calm(t - B(43.2)),
      sel: bt >= 44.45 && bt < 45.6 ? 1 : 0, tx: 150 * mv, ty: -50 * mv,
    });
    // ⌘↩: saved image appears over the canvas, note burns in, floats to the hero pose
    const cl = G.X + (-578 + 270) * G.S, ct = G.Y + (-406 + 205) * G.S;
    const burn = e.outCubic(Z.prog(t, B(52.1), B(52.1) + 0.4));
    this.res.note.style.clipPath = `inset(0 0 ${(1 - burn) * 100}% 0)`;
    const h = this.res.el.offsetHeight, R = Z.R.RESULT_POSE, m = e.inOutCubic(Z.prog(t, B(52.4), B(53.1)));
    Z.set(this.res.el, { x: Z.lerp(cl + 308 * G.S, R.x, m), y: Z.lerp(ct + (h * G.S) / 2, R.y, m), s: Z.lerp(G.S, R.s, m), o: bt >= 52.1 ? 1 : 0 });
  },
});

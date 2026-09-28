// v3 F4 — beats 19.5-28: the real Editor window (pen active by default). A → arrow (21), R → rectangle (22.5),
// F → markers 1 & 2 (24, 25). ⌘↩ (26.5): window closes, the saved image appears with the note burned in below
// and floats to Z.R.RESULT_POSE for F5.
Z.R.RESULT_POSE = { x: 960, y: 520, s: 0.82 };
Z.scene({
  name: 'editor', from: 19.5, to: 28,
  build(root) {
    this.ed = Z.R.editor(root);
    this.res = Z.R.resultImage(root);
  },
  render(t) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT, ed = this.ed;
    ed.layout();
    const inP = Z.soft(t - B(19.8), 0.5), out = e.inOutCubic(Z.prog(t, B(26.6), B(27)));
    const wx = 960, wy = 520;
    Z.set(ed.el, { x: wx, y: wy + (1 - inP) * 16, s: (0.97 + 0.03 * inP) * (1 - out * 0.03), o: inP * (1 - out) });
    ed.setActive(bt >= 24 ? 6 : bt >= 22.5 ? 3 : bt >= 21 ? 2 : 0);
    ed.ann.set({
      arrow: e.outCubic(Z.prog(t, B(21.15), B(21.15) + 0.35)),
      head: Z.calm(t - B(21.15) - 0.35),
      rect: e.inOutCubic(Z.prog(t, B(22.65), B(22.65) + 0.5)),
      mk1: Z.calm(t - B(24)),
      mk2: Z.calm(t - B(25)),
    });
    // saved image: starts exactly over the canvas (image top at window top + 205), note strip burns in, floats up
    const imgTop = wy - 406 + 205, strip = this.res.note;
    const burn = e.outCubic(Z.prog(t, B(26.6), B(26.6) + 0.4));
    strip.style.clipPath = `inset(0 0 ${(1 - burn) * 100}% 0)`;
    const h = this.res.el.offsetHeight, P = Z.R.RESULT_POSE, mv = e.inOutCubic(Z.prog(t, B(26.9), B(27.5)));
    Z.set(this.res.el, { x: Z.lerp(wx, P.x, mv), y: Z.lerp(imgTop + h / 2, P.y, mv), s: Z.lerp(1, P.s, mv), o: bt >= 26.6 ? 1 : 0 });
  },
});

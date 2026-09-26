// Composes scenes, global camera shake, grain + vignette. Exposes window.renderFrame(t).
(() => {
  const stage = document.getElementById('stage');
  const cam = Z.el(stage, 'div', { width: Z.W + 'px', height: Z.H + 'px', transformOrigin: '960px 540px' });
  const layers = Z.scenes.map((sc) => {
    const root = Z.el(cam, 'div', { width: Z.W + 'px', height: Z.H + 'px', overflow: 'hidden' });
    const fxc = document.createElement('canvas'); fxc.width = Z.W; fxc.height = Z.H;
    const api = { fx: fxc.getContext('2d') };
    sc.build(root, api);
    Object.assign(fxc.style, { position: 'absolute', left: 0, top: 0, pointerEvents: 'none' });
    root.appendChild(fxc);
    return { sc, root, api };
  });
  const flash = Z.el(stage, 'div', { width: Z.W + 'px', height: Z.H + 'px', background: '#fff', opacity: 0 });
  Z.el(stage, 'div', { width: Z.W + 'px', height: Z.H + 'px', background: 'radial-gradient(ellipse at center, rgba(0,0,0,0) 55%, rgba(0,0,0,.55) 100%)' });
  const grainC = document.createElement('canvas'); grainC.width = Z.W / 2; grainC.height = Z.H / 2;
  Object.assign(grainC.style, { position: 'absolute', left: 0, top: 0, width: Z.W + 'px', height: Z.H + 'px', mixBlendMode: 'overlay', opacity: 0.22 });
  stage.appendChild(grainC);
  const gctx = grainC.getContext('2d');
  const tiles = [0, 1, 2, 3].map((k) => {
    const d = gctx.createImageData(grainC.width, grainC.height), R = Z.rng(99 + k);
    for (let i = 0; i < d.data.length; i += 4) { const v = 128 + (R() - 0.5) * 120; d.data[i] = d.data[i + 1] = d.data[i + 2] = v; d.data[i + 3] = 255; }
    return d;
  });
  Z.flash = (a) => { Z._flash = Math.max(Z._flash || 0, a); };

  window.renderFrame = (t) => {
    const bt = t / Z.BEAT;
    Z._flash = 0; Z.camera = { x: 0, y: 0, s: 1, r: 0 };
    for (const L of layers) {
      const on = bt >= L.sc.from && bt < L.sc.to;
      L.root.style.display = on ? 'block' : 'none';
      if (!on) continue;
      L.api.fx.clearRect(0, 0, Z.W, Z.H);
      L.sc.render(t, L.root, L.api);
    }
    let sx = 0, sy = 0, sr = 0;
    for (const [b, amp, dec] of Z.shakes) {
      const dt = t - Z.b(b); if (dt < 0 || dt > 1) continue;
      const a = amp * Math.exp(-dec * dt);
      sx += a * Math.sin(dt * 91 + b * 7); sy += a * Math.sin(dt * 77 + b * 3 + 1); sr += a * 0.04 * Math.sin(dt * 63 + b);
    }
    const c = Z.camera;
    cam.style.transform = `translate(${c.x + sx}px,${c.y + sy}px) rotate(${c.r + sr}deg) scale(${c.s})`;
    flash.style.opacity = Z.clamp(Z._flash);
    gctx.putImageData(tiles[Math.floor(t * 30) % 4], 0, 0);
  };
  window.sceneReady = Promise.all([...document.images].map((i) => i.decode().catch(() => {}))).then(() => document.fonts.ready);
})();

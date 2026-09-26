// Deterministic motion engine: everything is a pure function of time t (seconds).
const Z = (window.Z = {});
Z.W = 1920; Z.H = 1080; Z.BEAT = 60 / 128;
Z.b = (beats) => beats * Z.BEAT;
Z.clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
Z.lerp = (a, b, p) => a + (b - a) * p;
Z.prog = (t, t0, t1) => Z.clamp((t - t0) / (t1 - t0));
Z.mix = (a, b, p) => a.map((v, i) => Z.lerp(v, b[i], p));
Z.ease = {
  outExpo: (p) => (p >= 1 ? 1 : 1 - Math.pow(2, -10 * p)),
  inExpo: (p) => (p <= 0 ? 0 : Math.pow(2, 10 * p - 10)),
  inOutExpo: (p) => (p <= 0 ? 0 : p >= 1 ? 1 : p < 0.5 ? Math.pow(2, 20 * p - 10) / 2 : (2 - Math.pow(2, -20 * p + 10)) / 2),
  outCubic: (p) => 1 - Math.pow(1 - p, 3),
  inCubic: (p) => p * p * p,
  inOutCubic: (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2),
  outQuint: (p) => 1 - Math.pow(1 - p, 5),
  inQuart: (p) => p * p * p * p,
  outBack: (p, s = 1.9) => 1 + (s + 1) * Math.pow(p - 1, 3) + s * Math.pow(p - 1, 2),
  inBack: (p, s = 1.7) => (s + 1) * p * p * p - s * p * p,
};
// eased tween between t0..t1
Z.tw = (t, t0, t1, from, to, e = Z.ease.outExpo) => Z.lerp(from, to, e(Z.prog(t, t0, t1)));
// damped spring 0 -> 1 (overshoots). dt = time since trigger.
Z.spring = (dt, freq = 3.2, damp = 0.32) => {
  if (dt <= 0) return 0;
  const w = 2 * Math.PI * freq;
  return 1 - Math.exp(-damp * w * dt) * Math.cos(w * Math.sqrt(1 - damp * damp) * dt);
};
// decaying wobble (for squash/stretch & jiggle), starts at amplitude 1
Z.wobble = (dt, freq = 4, decay = 6) => (dt < 0 ? 0 : Math.exp(-decay * dt) * Math.cos(2 * Math.PI * freq * dt));
Z.pulse = (dt, decay = 8) => (dt < 0 ? 0 : Math.exp(-decay * dt));
// kick pulse: decays from each beat in [from,to)
Z.beatPulse = (t, fromBeat, toBeat, decay = 9, step = 1) => {
  const bt = t / Z.BEAT;
  if (bt < fromBeat || bt >= toBeat + 1) return 0;
  const last = fromBeat + Math.floor((Math.min(bt, toBeat) - fromBeat) / step) * step;
  return Z.pulse((bt - last) * Z.BEAT, decay);
};
Z.rng = (seed) => () => {
  seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
  let r = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
  return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
};

// ---- DOM helpers ----
Z.el = (parent, tag = 'div', css = {}, html) => {
  const e = document.createElement(tag);
  Object.assign(e.style, { position: 'absolute', left: '0px', top: '0px' }, css);
  if (html !== undefined) e.innerHTML = html;
  parent.appendChild(e);
  return e;
};
Z.svg = (parent, w, h, inner, css = {}) => {
  const d = Z.el(parent, 'div', { width: w + 'px', height: h + 'px', ...css });
  d.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" style="overflow:visible">${inner}</svg>`;
  return d;
};
// centre-anchored transform. o: opacity; blur px; sx/sy extra scale; r degrees
Z.set = (e, { x = 0, y = 0, s = 1, sx = 1, sy = 1, r = 0, o = 1, blur = 0, skx = 0 } = {}) => {
  e.style.transform = `translate(${x}px,${y}px) translate(-50%,-50%) rotate(${r}deg) skewX(${skx}deg) scale(${s * sx},${s * sy})`;
  e.style.opacity = Z.clamp(o);
  e.style.filter = blur > 0.05 ? `blur(${blur}px)` : '';
  e.style.visibility = o <= 0.001 || s * sx * sy === 0 ? 'hidden' : 'visible';
};
// SF Symbol (real asset) tinted by CSS mask
Z.symbol = (parent, name, size, color = '#dedfe0', css = {}) =>
  Z.el(parent, 'div', {
    width: size + 'px', height: size + 'px', background: color,
    webkitMaskImage: `url(../assets/symbols/${name}.png)`, webkitMaskSize: 'contain',
    webkitMaskRepeat: 'no-repeat', webkitMaskPosition: 'center', ...css,
  });
// keycap component
Z.keycap = (parent, label, size = 150, css = {}) => {
  const k = Z.el(parent, 'div', { width: size + 'px', height: size + 'px', ...css });
  Z.el(k, 'div', { width: '100%', height: '100%', top: size * 0.07 + 'px', borderRadius: size * 0.2 + 'px', background: '#06090b' });
  const face = Z.el(k, 'div', {
    width: '100%', height: '100%', borderRadius: size * 0.2 + 'px',
    background: 'linear-gradient(180deg,#2c3236 0%,#1c2124 100%)',
    boxShadow: 'inset 0 2px 0 rgba(255,255,255,.14), inset 0 -3px 0 rgba(0,0,0,.35)',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    color: '#f2f4f5', font: `600 ${size * 0.42}px system-ui`,
  }, label);
  k.face = face;
  return k;
};

// ---- analytic particle / shape FX on canvas ----
Z.fx = {
  burst(ctx, dt, x, y, { n = 40, seed = 1, speed = 900, colors = ['#f7a043', '#45d0c4', '#fff3dc'], life = 1.1, size = 10, gravity = 900, drag = 2.6, spread = Math.PI * 2, dir = -Math.PI / 2, shapes = true } = {}) {
    if (dt < 0 || dt > life) return;
    const R = Z.rng(seed);
    for (let i = 0; i < n; i++) {
      const a = dir + (R() - 0.5) * spread, v = speed * (0.35 + R() * 0.8);
      const k = (1 - Math.exp(-drag * dt)) / drag;
      const px = x + Math.cos(a) * v * k, py = y + Math.sin(a) * v * k + 0.5 * gravity * dt * dt * 0.6;
      const lifeP = dt / (life * (0.6 + R() * 0.4));
      if (lifeP >= 1) continue;
      const sz = size * (0.5 + R()) * (1 - lifeP * lifeP);
      ctx.save(); ctx.translate(px, py); ctx.rotate(R() * 6 + dt * (R() - 0.5) * 20);
      ctx.fillStyle = colors[Math.floor(R() * colors.length)];
      const shape = shapes ? Math.floor(R() * 3) : 0;
      if (shape === 0) { ctx.beginPath(); ctx.arc(0, 0, sz / 2, 0, 7); ctx.fill(); }
      else if (shape === 1) ctx.fillRect(-sz / 2, -sz / 4, sz, sz / 2);
      else { ctx.strokeStyle = ctx.fillStyle; ctx.lineWidth = sz / 4; ctx.beginPath(); ctx.arc(0, 0, sz / 2, 0, 3.5); ctx.stroke(); }
      ctx.restore();
    }
  },
  ring(ctx, dt, x, y, { r0 = 20, r1 = 400, life = 0.6, width = 10, color = '#ffffff' } = {}) {
    if (dt < 0 || dt > life) return;
    const p = dt / life, e = Z.ease.outExpo(p);
    ctx.strokeStyle = color; ctx.globalAlpha = 1 - p; ctx.lineWidth = width * (1 - p) + 0.5;
    ctx.beginPath(); ctx.arc(x, y, Z.lerp(r0, r1, e), 0, 7); ctx.stroke(); ctx.globalAlpha = 1;
  },
  speedLines(ctx, dt, x, y, { n = 36, seed = 7, life = 0.5, r0 = 120, r1 = 1300, color = '#ffffff', width = 6 } = {}) {
    if (dt < 0 || dt > life) return;
    const R = Z.rng(seed), p = dt / life;
    ctx.strokeStyle = color; ctx.lineCap = 'round';
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + R() * 0.15, len = 0.25 + R() * 0.35;
      const head = Z.ease.outExpo(Z.clamp(p * (1.2 + R() * 0.5))), tail = Z.ease.outCubic(Z.clamp(p * 1.1 - 0.05));
      const ra = Z.lerp(r0, r1, Math.min(head, tail + len)), rb = Z.lerp(r0, r1, tail);
      if (ra - rb < 1) continue;
      ctx.globalAlpha = (1 - p) * (0.5 + R() * 0.5); ctx.lineWidth = width * (0.5 + R());
      ctx.beginPath(); ctx.moveTo(x + Math.cos(a) * rb, y + Math.sin(a) * rb); ctx.lineTo(x + Math.cos(a) * ra, y + Math.sin(a) * ra); ctx.stroke();
    }
    ctx.globalAlpha = 1;
  },
};

// ---- scene registry + global camera ----
Z.scenes = [];
Z.scene = (def) => Z.scenes.push(def); // { name, from, to (beats), build(root, api), render(t, root, api) }
Z.shakes = []; // [beat, amplitude, decay]
Z.shake = (beat, amp = 14, decay = 9) => Z.shakes.push([beat, amp, decay]);
Z.camera = { x: 0, y: 0, s: 1, r: 0 };

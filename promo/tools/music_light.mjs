// Calm light-cut soundtrack: 96 BPM, Ab major, exactly 30s. Warm e-piano + pad, soft drums from bar 3,
// gentle UI sfx (real Zoomies shutter). Writes audio/music-light.wav + audio/cues-light.json.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const MODE = process.argv[2] || 'v2', V4 = MODE === 'v4';
const SR = 48000, BPM = 96, BEAT = 60 / BPM, DUR = V4 ? 47.5 : 30, N = SR * DUR;
const T = (b) => b * BEAT, mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const L = new Float32Array(N), R = new Float32Array(N), sL = new Float32Array(N), sR = new Float32Array(N);
const duckable = [new Float32Array(N), new Float32Array(N)];
let seed = 777; const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;
const add = (i, v, pan = 0, send = 0, duck = false) => {
  if (i < 0 || i >= N) return;
  const l = v * Math.cos((pan + 1) * Math.PI / 4), r = v * Math.sin((pan + 1) * Math.PI / 4);
  if (duck) { duckable[0][i] += l; duckable[1][i] += r; } else { L[i] += l; R[i] += r; }
  sL[i] += l * send; sR[i] += r * send;
};
class LP { constructor() { this.y = 0; } run(x, f) { const a = 1 - Math.exp(-2 * Math.PI * f / SR); this.y += a * (x - this.y); return this.y; } }
class HP { constructor() { this.lp = new LP(); } run(x, f) { return x - this.lp.run(x, f); } }

// FM e-piano (Rhodes-ish): sine carrier + decaying modulator + soft tine
function keys(t0, m, len, g = 1, pan = 0) {
  const s = Math.floor(t0 * SR), n = Math.floor((len + 1.2) * SR), f = mtof(m); let pc = 0, pm = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR; pm += 2 * Math.PI * f / SR; pc += 2 * Math.PI * f / SR;
    const idx = 1.6 * Math.exp(-t * 5);
    const env = Math.min(1, t / 0.004) * Math.exp(-t * 1.1) * (t > len ? Math.exp(-(t - len) * 5) : 1);
    const v = Math.sin(pc + idx * Math.sin(pm)) + 0.25 * Math.sin(4 * pc) * Math.exp(-t * 14);
    add(s + i, v * env * 0.22 * g, pan, 0.5);
  }
}
function pad(t0, notes, len, g = 1) {
  const s = Math.floor(t0 * SR), n = Math.floor((len + 1) * SR);
  const vs = []; notes.forEach((m) => [-0.07, 0, 0.07].forEach((d, k) => vs.push({ f: mtof(m + d), ph: Math.abs(rnd()), p: k - 1 })));
  const lpL = new LP(), lpR = new LP(), lp2L = new LP(), lp2R = new LP();
  for (let i = 0; i < n; i++) {
    const t = i / SR; let l = 0, r = 0;
    for (const v of vs) { v.ph = (v.ph + v.f / SR) % 1; const x = 2 * v.ph - 1; l += x * (1 - v.p * 0.6); r += x * (1 + v.p * 0.6); }
    const env = Math.min(1, t / 0.6) * (t > len ? Math.exp(-(t - len) * 3) : 1);
    const cf = 900 + 300 * Math.sin(t * 1.3);
    const k = env * 0.085 * g / Math.sqrt(vs.length);
    const ii = s + i; if (ii >= N) break;
    const a = lp2L.run(lpL.run(l, cf), cf) * k, b = lp2R.run(lpR.run(r, cf), cf) * k;
    duckable[0][ii] += a; duckable[1][ii] += b; sL[ii] += a * 0.6; sR[ii] += b * 0.6;
  }
}
function bass(t0, m, len, g = 1) {
  const s = Math.floor(t0 * SR), n = Math.floor(len * SR), f = mtof(m), lp = new LP(); let ph = 0, sp = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR; ph = (ph + f / SR) % 1; sp += 2 * Math.PI * f / SR;
    const env = Math.min(1, t / 0.01) * Math.min(1, (len - t) / 0.05) * (0.8 + 0.2 * Math.exp(-t * 4));
    add(s + i, (Math.sin(sp) * 0.8 + lp.run(2 * ph - 1, 400) * 0.35) * env * 0.32 * g, 0, 0, true);
  }
}
const kicks = [];
function kick(t0, g = 1) {
  kicks.push(t0); const s = Math.floor(t0 * SR); let ph = 0;
  for (let i = 0; i < SR * 0.4; i++) { const t = i / SR; ph += 2 * Math.PI * (48 + 70 * Math.exp(-t * 28)) / SR; add(s + i, Math.sin(ph) * Math.exp(-t * 7) * 0.3 * g); }
}
function rim(t0, g = 1) {
  const s = Math.floor(t0 * SR), hp = new HP(); let ph = 0;
  for (let i = 0; i < SR * 0.12; i++) { const t = i / SR; ph += 2 * Math.PI * 820 / SR; add(s + i, (Math.sin(ph) * 0.5 + hp.run(rnd(), 2500) * 0.5) * Math.exp(-t * 45) * 0.16 * g, -0.15, 0.4); }
}
function shaker(t0, g = 1, pan = 0.25) {
  const s = Math.floor(t0 * SR), hp = new HP();
  for (let i = 0; i < SR * 0.08; i++) { const t = i / SR; add(s + i, hp.run(rnd(), 6000) * Math.min(1, t / 0.01) * Math.exp(-t * 50) * 0.12 * g, pan); }
}
function blip(t0, m, g = 1, pan = 0) {
  const s = Math.floor(t0 * SR); let ph = 0;
  for (let i = 0; i < SR * 0.4; i++) { const t = i / SR; ph += 2 * Math.PI * mtof(m) / SR; add(s + i, (Math.sin(ph) + 0.15 * Math.sin(3 * ph)) * Math.exp(-t * 12) * 0.12 * g, pan, 0.6); }
}
function tick(t0, g = 1) { const s = Math.floor(t0 * SR), hp = new HP(); for (let i = 0; i < SR * 0.025; i++) add(s + i, hp.run(rnd(), 4000) * Math.exp(-i / SR * 200) * 0.18 * g, rnd() * 0.3); }
function whoosh(t0, len, g = 1) {
  const s = Math.floor(t0 * SR), n = Math.floor(len * SR), lp = new LP(), hp = new HP();
  for (let i = 0; i < n; i++) { const p = i / n; add(s + i, hp.run(lp.run(rnd(), 400 + 3000 * p), 200) * Math.sin(p * Math.PI) ** 2 * 0.16 * g, Math.sin(p * 4) * 0.4, 0.4); }
}
const raw = path.join(root, 'audio/shutter.raw');
execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', path.join(root, 'assets/screenshot-sound.mp3'), '-f', 'f32le', '-ac', '2', '-ar', String(SR), raw]);
const sh = new Float32Array(fs.readFileSync(raw).buffer.slice(0));
const shutter = (b, g = 0.8) => { const s = Math.floor(T(b) * SR); for (let i = 0; i < sh.length / 2; i++) { add(s + i, sh[2 * i] * g, -0.2, 0.25); add(s + i, sh[2 * i + 1] * g, 0.2, 0.25); } };

// ---- arrangement ----
const CH = { Ab: [56, 60, 63, 67, 70], Fm: [53, 56, 60, 63, 67], Db: [53, 56, 60, 63, 65], Eb: [55, 58, 63, 65, 70] };
const ROOT = { Ab: 44, Fm: 41, Db: 37, Eb: 39 };
const NB = Math.round(DUR / BEAT / 4), CYC = ['Ab', 'Fm', 'Db', 'Eb'];
const bars = Array.from({ length: NB }, (_, i) => (i === NB - 1 ? 'Ab' : i === NB - 2 ? 'Db|Eb' : CYC[i % 4]));
const cues = []; const cue = (b, name) => cues.push({ beat: b, time: +T(b).toFixed(4), name });
bars.forEach((name, bar) => {
  const b0 = bar * 4;
  const parts = name.split('|'), plen = 4 / parts.length;
  parts.forEach((c, k) => {
    const cb = b0 + k * plen, last = bar === NB - 1;
    pad(T(cb), CH[c].slice(0, 4).map((m) => m - 12 + 12), T(last ? 5.5 : plen), bar < 2 ? 0.8 : 1);
    // e-piano: chord on 1, gentle 8th arpeggio
    const voic = CH[c];
    if (last) { voic.forEach((m, j) => keys(T(cb) + j * 0.03, m, T(4), 0.9)); return; }
    keys(T(cb), voic[0], T(1.5), 0.8, -0.2); keys(T(cb), voic[2], T(1.5), 0.7, 0.2);
    for (let e = 1; e < plen * 2; e++) keys(T(cb + e * 0.5), voic[[1, 3, 2, 4, 3, 1, 2][e % 7]] + (e === 5 ? 12 : 0), T(0.5), 0.45 + (bar >= 4 ? 0.1 : 0), e % 2 ? 0.35 : -0.35);
    if (bar >= 2) { bass(T(cb), ROOT[c], T(plen * 0.95), 1); }
  });
  // drums bars 3-11 (b8-44): kick 1 & 3 (+ "and of 3" pickup), rim 2 & 4, shaker 8ths
  if (bar >= 2 && bar <= NB - 2) {
    for (let q = 0; q < 4; q++) {
      const b = b0 + q;
      if (q === 0 || q === 2) kick(T(b), bar === 2 && q === 0 ? 1.1 : 0.9);
      if (q === 2 && bar % 2) kick(T(b + 1.5), 0.55);
      if (q === 1 || q === 3) rim(T(b), 0.9);
      shaker(T(b), 0.7, -0.2); shaker(T(b + 0.5), 1, 0.25);
      if (bar >= 4) shaker(T(b + 0.75), 0.5, 0.3);
    }
  }
});
// top-line motif (bars 5-10), sparse & singable
const mel = [[16, 75, 1], [17, 72, .5], [17.5, 70, .5], [18, 72, 1.5], [20, 68, 1], [21, 67, .5], [21.5, 68, 2],
  [24, 72, 1], [25, 70, .5], [25.5, 72, .5], [26, 75, 1.5], [28, 77, 1], [29, 75, .5], [29.5, 72, 2],
  [32, 75, 1], [33, 72, .5], [33.5, 70, .5], [34, 72, 1.5], [36, 80, 1], [37, 79, .5], [37.5, 77, 2]];
(V4 ? mel.concat(mel.map(([b, m, l]) => [b + 24, m, l]), mel.slice(0, 7).map(([b, m, l]) => [b + 48, m, l])) : mel).forEach(([b, m, l]) => keys(T(b), m, T(l), 0.75, 0.05));
// sfx cues (visuals key off these)
const V3 = MODE === 'v3';
if (V4) {
  V4CUES();
} else if (!V3) {
cue(0, 'problemIn'); cue(3, 'bubble'); cue(6, 'showIt');
whoosh(T(7), T(1.2), 0.8); cue(8, 'captureScene');
cue(10, 'marqueeStart'); shutter(12); cue(12, 'shutter');
whoosh(T(15), T(1.2), 0.7); cue(16, 'editorScene');
[[18, 'rect', 79], [20, 'marker1', 82], [21, 'marker2', 84]].forEach(([b, n, m]) => { blip(T(b), m, 1); cue(b, n); });
for (let k = 0; k < 12; k++) tick(T(22 + k / 6), 0.8); cue(22, 'noteType'); cue(24, 'noteDone');
whoosh(T(27), T(1.2), 0.7); cue(28, 'chatScene');
blip(T(30), 87, 1.1); cue(30, 'paste'); blip(T(32), 91, 0.8); cue(32, 'send'); cue(34, 'reply');
whoosh(T(35), T(1.2), 0.6); cue(36, 'stat1'); blip(T(36), 84, 0.9); cue(38, 'stat2'); blip(T(38), 87, 0.9);
whoosh(T(39.2), T(1), 0.6); cue(40, 'lockup'); blip(T(40), 92, 0.8); blip(T(40.25), 96, 0.6); cue(42, 'tagline'); cue(44, 'url'); cue(48, 'end');
} else {
// v3: real Zoomies flow — capture → rename panel → note panel → editor → ⌘↩ → paste into agent
cue(0, 'problemIn'); cue(3, 'bubble'); cue(6, 'showIt');
whoosh(T(7), T(1.2), 0.8); cue(8, 'captureScene');
[9, 9.25, 9.5].forEach((b, k) => { tick(T(b), 1.6); cue(b, `key${k}`); });
cue(9.8, 'marqueeStart'); shutter(12); cue(12, 'shutter');
blip(T(12.3), 79, 0.6); cue(12.3, 'renamePanel');
for (let k = 0; k < 16; k++) tick(T(13 + k * 0.125), 0.8); cue(13, 'renameType');
tick(T(15.5), 1.4); blip(T(15.5), 84, 0.5); cue(15.5, 'tabNote'); cue(16, 'notePanel');
for (let k = 0; k < 24; k++) tick(T(16.5 + k * 0.105), 0.8); cue(16.5, 'noteType');
tick(T(19.5), 1.4); blip(T(19.5), 87, 0.5); cue(19.5, 'tabEditor'); cue(20, 'editor');
[[21, 'arrow', 79], [22.5, 'rect', 82], [24, 'marker1', 84], [25, 'marker2', 86]].forEach(([b, n, m]) => { blip(T(b), m, 0.9); cue(b, n); });
blip(T(26.5), 91, 1); blip(T(26.75), 96, 0.6); cue(26.5, 'copySave');
whoosh(T(27), T(1.2), 0.7); cue(28.2, 'chatScene');
tick(T(29.5), 1.4); cue(29.5, 'cmdV'); blip(T(30), 87, 1.1); cue(30, 'paste'); blip(T(31.5), 91, 0.8); cue(31.5, 'send');
blip(T(33), 84, 0.6); cue(33, 'reply');
whoosh(T(35), T(1.2), 0.6); cue(36, 'stat1'); blip(T(36), 84, 0.9); cue(38, 'stat2'); blip(T(38), 87, 0.9);
whoosh(T(39.2), T(1), 0.6); cue(40, 'lockup'); blip(T(40), 92, 0.8); blip(T(40.25), 96, 0.6); cue(42, 'tagline'); cue(44, 'url'); cue(48, 'end');
}

// ---- mix: gentle sidechain, reverb, master ----
kicks.sort((a, b) => a - b);
function reverb(inp, sp) {
  const combs = [1687, 1601, 1491, 1422, 1277, 1356].map((d) => ({ b: new Float32Array(Math.round((d + sp) * 1.3)), i: 0, lp: 0 }));
  const aps = [556, 441, 341].map((d) => ({ b: new Float32Array(Math.round((d + sp) * 1.1)), i: 0 }));
  const out = new Float32Array(N);
  for (let n = 0; n < N; n++) {
    let s = 0; const x = inp[n] * 0.08;
    for (const c of combs) { const y = c.b[c.i]; c.lp = y * 0.55 + c.lp * 0.45; c.b[c.i] = x + c.lp * 0.89; c.i = (c.i + 1) % c.b.length; s += y; }
    for (const a of aps) { const y = a.b[a.i]; const v = -s + y; a.b[a.i] = s + y * 0.5; a.i = (a.i + 1) % a.b.length; s = v; }
    out[n] = s;
  }
  return out;
}
const rvL = reverb(sL, 0), rvR = reverb(sR, 23);
let k = 0, peak = 0;
const mixL = new Float32Array(N), mixR = new Float32Array(N);
for (let i = 0; i < N; i++) {
  const t = i / SR; while (k + 1 < kicks.length && kicks[k + 1] <= t) k++;
  const dt = kicks.length && kicks[k] <= t ? t - kicks[k] : 9;
  const d = 1 - 0.35 * Math.exp(-dt / 0.12);
  mixL[i] = L[i] + duckable[0][i] * d + rvL[i]; mixR[i] = R[i] + duckable[1][i] * d + rvR[i];
  peak = Math.max(peak, Math.abs(mixL[i]), Math.abs(mixR[i]));
}
const pre = 1.25 / peak, pcm = Buffer.alloc(N * 4);
for (let i = 0; i < N; i++) {
  const t = i / SR, fade = Math.min(1, t / 0.05) * (t > DUR - 0.6 ? (DUR - t) / 0.6 : 1);
  pcm.writeInt16LE(Math.round(Math.tanh(mixL[i] * pre) * 0.9 * fade * 32767), i * 4);
  pcm.writeInt16LE(Math.round(Math.tanh(mixR[i] * pre) * 0.9 * fade * 32767), i * 4 + 2);
}
const h = Buffer.alloc(44);
h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8); h.write('fmt ', 12); h.writeUInt32LE(16, 16);
h.writeUInt16LE(1, 20); h.writeUInt16LE(2, 22); h.writeUInt32LE(SR, 24); h.writeUInt32LE(SR * 4, 28); h.writeUInt16LE(4, 32);
h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
fs.writeFileSync(path.join(root, V4 ? 'audio/music-light-v4.wav' : V3 ? 'audio/music-light-v3.wav' : 'audio/music-light.wav'), Buffer.concat([h, pcm]));
cues.sort((a, b) => a.beat - b.beat);
fs.writeFileSync(path.join(root, V4 ? 'audio/cues-light-v4.json' : V3 ? 'audio/cues-light-v3.json' : 'audio/cues-light.json'), JSON.stringify({ bpm: BPM, beat: BEAT, duration: DUR, cues }, null, 1));
console.log('wrote', MODE, '; cues', cues.length);

// v4: long keybind story (47.5s). Visual beat map in HANDOFF.md.
function V4CUES() {
  const key = (b, n, m = null, g = 1.4) => { tick(T(b), g); if (m) blip(T(b), m, 0.7); cue(b, n); };
  cue(0, 'problemIn'); cue(3, 'bubble'); cue(6, 'showIt');
  whoosh(T(7), T(1.2), 0.8); cue(8, 'captureScene');
  [9, 9.25, 9.5].forEach((b, k) => key(b, `key${k}`));
  cue(9.8, 'marqueeStart'); shutter(12); cue(12, 'shutter');
  blip(T(12.3), 79, 0.6); cue(12.3, 'renamePanel');
  [[13, 'optEnter', 79], [14, 'optCmdEnter', 82], [15, 'optCmdDel', 84], [16, 'optEsc', 86], [17, 'optTab', 89]].forEach(([b, n, m]) => key(b, n, m, 0.9));
  for (let k = 0; k < 16; k++) tick(T(18.25 + k * 0.125), 0.8); cue(18.25, 'renameType');
  key(20.75, 'tabNote', 84); cue(21.25, 'notePanel');
  for (let k = 0; k < 24; k++) tick(T(21.75 + k * 0.104), 0.8); cue(21.75, 'noteType');
  key(25, 'shiftTabRename', 77); key(26.5, 'tabNote2', 84); key(28, 'tabEditor', 87);
  blip(T(28.5), 89, 0.5); cue(28.5, 'editor');
  key(30, 'cmdHold'); blip(T(30.1), 91, 0.5);
  [[32.5, 'W', 76], [33.75, 'D', 77], [35, 'A', 79], [36.25, 'R', 80], [37.5, 'Q', 82], [38.5, 'E', 84], [39.75, 'T', 85],
    [41.25, 'one', 87], [42.25, 'F', 88], [44.25, 'S', 89], [46, 'cmdZ', 84], [47, 'cmdShiftZ', 87], [48.5, 'shiftTabNote', 77], [50.5, 'tabEditor2', 87]]
    .forEach(([b, n, m]) => key(b, n, m));
  for (let k = 0; k < 8; k++) tick(T(39.9 + k * 0.11), 0.7);
  [42.6, 43.2].forEach((b) => { tick(T(b), 1); blip(T(b), 91, 0.4); });
  blip(T(52), 91, 1); blip(T(52.25), 96, 0.6); cue(52, 'copySave');
  const S = 26; // agent/value/lockup shifted from the v3 layout
  whoosh(T(27 + S), T(1.2), 0.7); tick(T(29.5 + S), 1.4); blip(T(30 + S), 87, 1.1); blip(T(31.5 + S), 91, 0.8); blip(T(33 + S), 84, 0.6);
  cue(29.5 + S, 'cmdV'); cue(30 + S, 'paste'); cue(31.5 + S, 'send'); cue(33 + S, 'reply');
  const V = 26.2;
  whoosh(T(35 + V), T(1.2), 0.6); blip(T(36.4 + V), 84, 0.9); blip(T(38 + V), 87, 0.9); cue(36.4 + V, 'stat1'); cue(38 + V, 'stat2');
  whoosh(T(39.2 + V), T(1), 0.6); blip(T(40 + V), 92, 0.8); blip(T(40.25 + V), 96, 0.6); cue(40 + V, 'lockup'); cue(76, 'end');
}

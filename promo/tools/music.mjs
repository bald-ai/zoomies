// Pure-node synth: 128 BPM F-minor track, exactly 30s, with SFX cues shared with the visuals.
// Writes audio/music.wav (48k stereo 16-bit) and audio/cues.json.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const SR = 48000, BPM = 128, BEAT = 60 / BPM, DUR = 30;
const N = SR * DUR;
const T = (b) => b * BEAT;
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);

// ---------- buses ----------
const bus = () => [new Float32Array(N), new Float32Array(N)];
const drums = bus(), bass = bus(), synth = bus(), fx = bus(), send = bus();
const add = (b, i, v, pan = 0, sendAmt = 0) => {
  if (i < 0 || i >= N) return;
  const l = v * Math.cos((pan + 1) * Math.PI / 4), r = v * Math.sin((pan + 1) * Math.PI / 4);
  b[0][i] += l; b[1][i] += r;
  if (sendAmt) { send[0][i] += l * sendAmt; send[1][i] += r * sendAmt; }
};
let seed = 1234567;
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;

// biquad lowpass/highpass/bandpass with per-sample coefficient refresh every 16 samples
class Biquad {
  constructor(type) { this.type = type; this.x1 = this.x2 = this.y1 = this.y2 = 0; this.n = 0; }
  set(f, q) {
    f = Math.min(Math.max(f, 20), SR * 0.45);
    const w = 2 * Math.PI * f / SR, c = Math.cos(w), s = Math.sin(w), a = s / (2 * q);
    let b0, b1, b2;
    if (this.type === 'lp') { b0 = (1 - c) / 2; b1 = 1 - c; b2 = b0; }
    else if (this.type === 'hp') { b0 = (1 + c) / 2; b1 = -(1 + c); b2 = b0; }
    else { b0 = a; b1 = 0; b2 = -a; }
    const a0 = 1 + a;
    this.b0 = b0 / a0; this.b1 = b1 / a0; this.b2 = b2 / a0; this.a1 = -2 * c / a0; this.a2 = (1 - a) / a0;
  }
  run(x, f, q = 0.707) {
    if ((this.n++ & 15) === 0) this.set(f, q);
    const y = this.b0 * x + this.b1 * this.x1 + this.b2 * this.x2 - this.a1 * this.y1 - this.a2 * this.y2;
    this.x2 = this.x1; this.x1 = x; this.y2 = this.y1; this.y1 = y; return y;
  }
}
const polyblep = (t, dt) => {
  if (t < dt) { t /= dt; return t + t - t * t - 1; }
  if (t > 1 - dt) { t = (t - 1) / dt; return t * t + t + t + 1; }
  return 0;
};

// ---------- instruments ----------
function kick(t0, g = 1) {
  const s = Math.floor(t0 * SR); let ph = 0;
  for (let i = 0; i < SR * 0.45; i++) {
    const t = i / SR, f = 45 + 120 * Math.exp(-t * 32);
    ph += 2 * Math.PI * f / SR;
    const v = Math.tanh(1.6 * Math.sin(ph) * Math.exp(-t * 6.5)) * 0.9 + rnd() * Math.exp(-t * 400) * 0.25;
    add(drums, s + i, v * g);
  }
}
function clap(t0, g = 1) {
  const s = Math.floor(t0 * SR), bp = new Biquad('bp'), hp = new Biquad('hp');
  for (let i = 0; i < SR * 0.35; i++) {
    const t = i / SR;
    const env = (t < 0.03 ? (Math.exp(-((t % 0.01) * 300))) : Math.exp(-(t - 0.03) * 16));
    const v = hp.run(bp.run(rnd(), 1500, 0.9), 400) * env;
    add(drums, s + i, v * 0.9 * g, 0, 0.35);
  }
}
function snare(t0, g = 1) {
  const s = Math.floor(t0 * SR), hp = new Biquad('hp'); let ph = 0;
  for (let i = 0; i < SR * 0.18; i++) {
    const t = i / SR; ph += 2 * Math.PI * (190 + 60 * Math.exp(-t * 40)) / SR;
    const v = hp.run(rnd(), 1800) * Math.exp(-t * 26) * 0.7 + Math.sin(ph) * Math.exp(-t * 30) * 0.4;
    add(drums, s + i, v * g, 0, 0.2);
  }
}
function hat(t0, open = false, g = 1, pan = 0.15) {
  const s = Math.floor(t0 * SR), hp = new Biquad('hp'), dec = open ? 14 : 70;
  for (let i = 0; i < SR * (open ? 0.25 : 0.06); i++) {
    const t = i / SR;
    add(drums, s + i, hp.run(rnd(), 8000) * Math.exp(-t * dec) * 0.35 * g, pan);
  }
}
function crash(t0, g = 1) {
  const s = Math.floor(t0 * SR), hp = new Biquad('hp'), hp2 = new Biquad('hp');
  for (let i = 0; i < SR * 2.2; i++) {
    const t = i / SR, n = hp2.run(hp.run(rnd(), 5000), 5000);
    add(fx, s + i, n * Math.exp(-t * 2.2) * 0.35 * g, (i % 2 ? 0.4 : -0.4), 0.3);
  }
}
function impact(t0, g = 1) {
  const s = Math.floor(t0 * SR), lp = new Biquad('lp'); let ph = 0;
  for (let i = 0; i < SR * 2.0; i++) {
    const t = i / SR; ph += 2 * Math.PI * (32 + 90 * Math.exp(-t * 9)) / SR;
    const v = Math.tanh(2.2 * Math.sin(ph)) * Math.exp(-t * 2.4) * 0.8 + lp.run(rnd(), 900) * Math.exp(-t * 5) * 0.6;
    add(fx, s + i, v * g, 0, 0.4);
  }
}
function thock(t0, pitch = 1, g = 1) { // keycap slam: woody click + low thump
  const s = Math.floor(t0 * SR), bp = new Biquad('bp'); let ph = 0;
  for (let i = 0; i < SR * 0.3; i++) {
    const t = i / SR; ph += 2 * Math.PI * (110 * pitch + 200 * Math.exp(-t * 60)) / SR;
    const v = Math.sin(ph) * Math.exp(-t * 18) * 0.8 + bp.run(rnd(), 2600 * pitch, 2) * Math.exp(-t * 90) * 1.2;
    add(fx, s + i, v * g, 0, 0.25);
  }
}
function blip(t0, m, g = 1, pan = 0) { // UI pop
  const s = Math.floor(t0 * SR); let ph = 0;
  for (let i = 0; i < SR * 0.16; i++) {
    const t = i / SR; ph += 2 * Math.PI * mtof(m) * (1 + 0.5 * Math.exp(-t * 80)) / SR;
    add(fx, s + i, (Math.sin(ph) + 0.3 * Math.sin(2 * ph)) * Math.exp(-t * 28) * 0.28 * g, pan, 0.3);
  }
}
function tick(t0, g = 1) { // typing
  const s = Math.floor(t0 * SR), hp = new Biquad('hp');
  for (let i = 0; i < SR * 0.03; i++) add(fx, s + i, hp.run(rnd(), 3500) * Math.exp(-i / SR * 180) * 0.5 * g, rnd() * 0.3);
}
function whoosh(t0, len, g = 1, rev = true) {
  const s = Math.floor(t0 * SR), bp = new Biquad('bp'), n = Math.floor(len * SR);
  for (let i = 0; i < n; i++) {
    const p = i / n, e = rev ? Math.pow(p, 2.2) : Math.pow(1 - p, 2);
    const f = rev ? 300 + 5000 * p * p : 5000 - 4500 * p;
    add(fx, s + i, bp.run(rnd(), f, 1.2) * e * 0.9 * g, Math.sin(p * 6) * 0.5, 0.3);
  }
}
function riser(t0, len, g = 1) {
  const s = Math.floor(t0 * SR), bp = new Biquad('bp'), n = Math.floor(len * SR); let ph = 0;
  for (let i = 0; i < n; i++) {
    const p = i / n; ph += 2 * Math.PI * (200 * Math.pow(8, p)) / SR;
    const v = bp.run(rnd(), 400 + 7000 * p * p, 2) * 0.8 + Math.sin(ph) * 0.12 + Math.sin(ph * 1.01) * 0.12;
    add(fx, s + i, v * p * p * g, 0, 0.3);
  }
}
function supersaw(t0, len, notes, g, cutoff0, cutoff1, target = synth, rel = 0.12, pan = 0, sendAmt = 0.3) {
  const s = Math.floor(t0 * SR), n = Math.floor((len + rel) * SR);
  const det = [-0.11, -0.06, -0.02, 0, 0.02, 0.06, 0.11];
  const voices = [];
  for (const m of notes) det.forEach((d, k) => voices.push({ f: mtof(m + d), ph: rnd() * 0.5 + 0.5, p: (k / 3 - 1) * 0.7 }));
  const lpL = new Biquad('lp'), lpR = new Biquad('lp');
  for (let i = 0; i < n; i++) {
    const t = i / SR; let l = 0, r = 0;
    for (const v of voices) {
      const dt = v.f / SR; v.ph += dt; if (v.ph >= 1) v.ph -= 1;
      const x = 2 * v.ph - 1 - polyblep(v.ph, dt);
      l += x * (1 - v.p) * 0.5; r += x * (1 + v.p) * 0.5;
    }
    const env = Math.min(1, t / 0.006) * (t > len ? Math.exp(-(t - len) / rel * 3) : 1);
    const cf = cutoff1 + (cutoff0 - cutoff1) * Math.exp(-t * 7);
    const sc = g * env / Math.sqrt(voices.length);
    const L = lpL.run(l, cf, 0.9) * sc, R = lpR.run(r, cf, 0.9) * sc;
    const ii = s + i; if (ii >= N) break;
    target[0][ii] += L * (1 - pan * 0.5); target[1][ii] += R * (1 + pan * 0.5);
    send[0][ii] += L * sendAmt; send[1][ii] += R * sendAmt;
  }
}
function pluck(t0, m, g = 1, pan = 0, bright = 1) {
  const s = Math.floor(t0 * SR), lp = new Biquad('lp'); let ph = 0; const f = mtof(m);
  for (let i = 0; i < SR * 0.35; i++) {
    const t = i / SR, dt = f / SR; ph += dt; if (ph >= 1) ph -= 1;
    const x = (ph < 0.5 ? 1 : -1) * 0.6 + (2 * ph - 1) * 0.4;
    add(synth, s + i, lp.run(x, 300 + 5000 * bright * Math.exp(-t * 18), 1.4) * Math.exp(-t * 9) * 0.22 * g, pan, 0.35);
  }
}
function lead(t0, len, m, g = 1) {
  const s = Math.floor(t0 * SR), n = Math.floor((len + 0.1) * SR), lp = new Biquad('lp');
  let p1 = 0, p2 = 0.3; const f = mtof(m);
  for (let i = 0; i < n; i++) {
    const t = i / SR, vib = 1 + 0.004 * Math.sin(2 * Math.PI * 5.5 * t) * Math.min(1, t / 0.2);
    const d1 = f * vib / SR, d2 = f * 1.005 * vib / SR;
    p1 += d1; if (p1 >= 1) p1 -= 1; p2 += d2; if (p2 >= 1) p2 -= 1;
    const x = (2 * p1 - 1 - polyblep(p1, d1)) + (2 * p2 - 1 - polyblep(p2, d2));
    const env = Math.min(1, t / 0.005) * (t > len ? Math.exp(-(t - len) * 40) : 0.85 + 0.15 * Math.exp(-t * 8));
    add(synth, s + i, lp.run(x, 1200 + 3500 * Math.exp(-t * 6), 1.1) * env * 0.16 * g, 0, 0.45);
  }
}
function bassNote(t0, len, m, g = 1) {
  const s = Math.floor(t0 * SR), n = Math.floor(len * SR), lp = new Biquad('lp');
  let ph = 0, sub = 0; const f = mtof(m);
  for (let i = 0; i < n; i++) {
    const t = i / SR, dt = f / SR; ph += dt; if (ph >= 1) ph -= 1; sub += 2 * Math.PI * f / SR;
    const x = 2 * ph - 1 - polyblep(ph, dt);
    const env = Math.min(1, t / 0.004) * Math.min(1, (len - t) / 0.01);
    const v = lp.run(x, 180 + 900 * Math.exp(-t * 14), 1.2) * 0.45 + Math.sin(sub) * 0.55;
    add(bass, s + i, Math.tanh(v * 1.4) * env * 0.55 * g);
  }
}

// ---------- arrangement ----------
const CH = [[53, 56, 60, 65], [53, 56, 61, 65], [51, 56, 60, 63], [51, 55, 58, 63]]; // Fm Db Ab Eb
const ROOT = [41, 37, 44, 39];
const chordAt = (bar) => bar % 4; // bar is 0-based
const cues = [];
const cue = (b, name) => cues.push({ beat: b, time: +T(b).toFixed(4), name });
const kicks = [];
const K = (b, g = 1) => { kick(T(b), g); kicks.push(T(b)); };

// A: intro bars 0-1 (beats 0-7)
[[0, 1], [1, 1.12], [2, 1.35]].forEach(([b, p], k) => { thock(T(b), p, 1.1); cue(b, `key${k}`); });
impact(T(2), 0.35);
supersaw(0, T(7.5), CH[0].map((m) => m - 12), 0.35, 200, 1400, synth, 0.05, 0, 0.5);
for (let s16 = 12; s16 < 30; s16++) pluck(T(s16 / 4), CH[s16 < 16 ? 0 : 1][s16 % 4] + 12, 0.5 + s16 / 40, (s16 % 2 ? 0.3 : -0.3), 0.2 + s16 / 30);
for (let b = 4; b < 7.5; b += 0.5) hat(T(b), false, 0.7);
// snare roll accelerating into drop
for (let b = 4; b < 5.5; b += 0.5) snare(T(b), 0.4 + (b - 4) * 0.1);
for (let b = 5.5; b < 6.5; b += 0.25) snare(T(b), 0.55 + (b - 5.5) * 0.2);
for (let b = 6.5; b < 7.5; b += 0.125) snare(T(b), 0.75 + (b - 6.5) * 0.3);
riser(T(3), T(4.5), 0.8);
cue(3, 'marqueeStart'); cue(7.5, 'shutter1');

// shutter SFX from the real app sound
const raw = path.join(root, 'audio/shutter.raw');
execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', path.join(root, 'assets/screenshot-sound.mp3'), '-f', 'f32le', '-ac', '2', '-ar', String(SR), raw]);
const sh = new Float32Array(fs.readFileSync(raw).buffer.slice(0));
const shutter = (b, g = 1) => { const s = Math.floor(T(b) * SR); for (let i = 0; i < sh.length / 2; i++) { add(fx, s + i, sh[2 * i] * g, -0.2, 0.2); add(fx, s + i, sh[2 * i + 1] * g, 0.2); } };
shutter(7.5, 1.3);

// groove helper
function groove(b0, b1, { hats16 = false, arp = true, leadOn = false, clapOn = true, bassOn = true, stabs = true } = {}) {
  for (let b = b0; b < b1; b++) {
    const bar = Math.floor(b / 4), ch = chordAt(bar), inBar = b % 4;
    K(b);
    if (clapOn && (inBar === 1 || inBar === 3)) clap(T(b));
    hat(T(b + 0.5), true, 0.8);
    if (hats16) { hat(T(b + 0.25), false, 0.5, -0.2); hat(T(b + 0.75), false, 0.6, 0.2); }
    if (bassOn) { bassNote(T(b + 0.5), T(0.42), ROOT[ch]); bassNote(T(b + 0.75), T(0.2), ROOT[ch] + (inBar === 3 ? 12 : 0), 0.8); }
    if (arp) for (let k = 0; k < 4; k++) pluck(T(b + k / 4), CH[ch][(inBar * 4 + k) % 4] + 12 + (k === 3 ? 12 : 0), 0.7, (k % 2 ? 0.35 : -0.35), 0.8);
    if (inBar === 0 && stabs) {
      supersaw(T(b), T(0.4), CH[ch], 0.55, 6000, 1500);
      supersaw(T(b + 1.5), T(0.3), CH[ch], 0.4, 5000, 1200);
      supersaw(T(b + 2.5), T(0.3), CH[ch], 0.45, 5000, 1200);
    }
  }
}
const HOOK = [
  [[0, 72, .45], [0.75, 75, .2], [1, 72, .45], [1.5, 68, .45], [2.5, 67, .2], [2.75, 68, .45], [3.5, 70, .45]],
  [[0, 72, .45], [0.75, 73, .2], [1, 72, .45], [1.5, 68, .45], [2.5, 65, .45], [3, 68, .45], [3.5, 65, .45]],
  [[0, 75, .45], [0.75, 72, .2], [1, 75, .45], [1.5, 77, .45], [2.5, 75, .2], [2.75, 72, .45], [3.5, 70, .45]],
  [[0, 70, .7], [1, 67, .45], [1.5, 70, .45], [2, 72, 1.3], [3.5, 79, .4]],
];
const hook = (bar, g = 1) => HOOK[bar % 4].forEach(([o, m, l]) => lead(T(bar * 4 + o), T(l), m, g));

// DROP bar 2 (beat 8)
impact(T(8), 1); crash(T(8), 1); cue(8, 'drop');
supersaw(T(8), T(1.5), CH[2].concat([72]), 0.7, 9000, 2500, synth, 0.3);
// B: bars 2-5 (beats 8-23)
groove(8, 24);
[0, 1, 2, 3, 4, 5, 6].forEach((k) => { blip(T(10 + k * 0.25), [77, 80, 84, 87, 89, 92, 96][k], 0.8, (k - 3) * 0.2); cue(10 + k * 0.25, `letter${k}`); });
for (let k = 0; k < 4; k++) cue(12 + k, `tagWord${k}`);
whoosh(T(14.5), T(1.5), 0.9); cue(16, 'toDesktop');
[[16.5, 1], [17, 1.12], [17.5, 1.35]].forEach(([b, p], k) => { thock(T(b), p, 0.8); cue(b, `miniKey${k}`); });
cue(18, 'marquee2Start'); shutter(20, 1.2); cue(20, 'shutter2'); crash(T(20), 0.5);
whoosh(T(22.5), T(1.5), 0.9);
// C: bars 6-9 (beats 24-39)
groove(24, 40, { hats16: true });
for (let bar = 6; bar < 10; bar++) hook(bar, 0.9);
cue(24, 'renamePanel');
for (let k = 0; k < 9; k++) { tick(T(24.5 + k * 0.25), 1); cue(24.5 + k * 0.25, `type${k}`); }
thock(T(27), 1.3, 0.8); cue(27, 'enter');
for (let k = 0; k < 9; k++) { blip(T(28 + k * 0.5), 65 + [0, 3, 5, 7, 10, 12, 15, 17, 19][k], 0.7, (k - 4) * 0.15); cue(28 + k * 0.5, `tool${k}`); }
['rect', 'arrow', 'marker1', 'marker2'].forEach((n, k) => cue(32.5 + k, n));
cue(36.5, 'noteText');
[0, 1, 2, 3].forEach((k) => { blip(T(37.5 + k * 0.5), 84 + k * 2, 0.6); cue(37.5 + k * 0.5, `color${k}`); });
for (let b = 38.5; b < 40; b += 0.25) snare(T(b), 0.5 + (b - 38.5) * 0.3);
whoosh(T(38.5), T(1.5), 1);
// D: bars 10-13 (beats 40-55)
impact(T(40), 0.7); crash(T(40), 0.8); shutter(40, 1);
groove(40, 54, { hats16: true });
for (let bar = 10; bar < 13; bar++) hook(bar, 1);
HOOK[3].slice(0, 3).forEach(([o, m, l]) => lead(T(52 + o), T(l), m));
[[40, '2s'], [44, '3s'], [48, '5s']].forEach(([b, n]) => { supersaw(T(b), T(0.9), CH[chordAt(b / 4)].concat([77]), 0.5, 10000, 3000); cue(b, `speed_${n}`); });
cue(51, 'toAgent'); cue(52, 'paste');
riser(T(52), T(4), 0.9);
for (let b = 54; b < 56; b += 0.125) snare(T(b), 0.4 + (b - 54) * 0.35);
// E: bars 14-15 (beats 56-63)
impact(T(56), 1.1); crash(T(56), 1); cue(56, 'finale');
supersaw(T(56), T(3.5), CH[0].concat([72, 77]), 0.55, 9000, 2000, synth, 0.6);
for (let b = 56; b < 60; b++) { K(b); hat(T(b + 0.5), true, 0.7); bassNote(T(b + 0.5), T(0.42), ROOT[0]); }
clap(T(57)); clap(T(59));
impact(T(60), 1.2); crash(T(60), 1.1); K(60, 1.1); cue(60, 'stamp');
supersaw(T(60), T(3.2), CH[0].map((m) => m - 12).concat([60, 65, 72]), 0.6, 7000, 900, synth, 0.9, 0, 0.8);
bassNote(T(60), T(3), ROOT[0] - 12, 1);
blip(T(60), 89, 0.7); blip(T(60.25), 96, 0.5);
cue(64, 'end');

// ---------- sidechain + reverb + master ----------
kicks.sort((a, b) => a - b);
const duck = new Float32Array(N); { let k = 0;
  for (let i = 0; i < N; i++) {
    const t = i / SR; while (k + 1 < kicks.length && kicks[k + 1] <= t) k++;
    const dtk = kicks.length && kicks[k] <= t ? t - kicks[k] : 9;
    duck[i] = 1 - 0.75 * Math.exp(-dtk / 0.07) * (dtk < 0.35 ? 1 : 0);
  } }
function reverb(inL, inR) {
  const combs = [1557, 1617, 1491, 1422, 1277, 1356], aps = [556, 441, 341];
  const out = [new Float32Array(N), new Float32Array(N)];
  [inL, inR].forEach((inp, ch) => {
    const sp = ch * 23, cb = combs.map((d) => ({ buf: new Float32Array(Math.round((d + sp) * SR / 44100)), i: 0, lp: 0 }));
    const ab = aps.map((d) => ({ buf: new Float32Array(Math.round((d + sp) * SR / 44100)), i: 0 }));
    for (let n = 0; n < N; n++) {
      let s = 0; const x = inp[n] * 0.1;
      for (const c of cb) { const y = c.buf[c.i]; c.lp = y * 0.7 + c.lp * 0.3; c.buf[c.i] = x + c.lp * 0.86; c.i = (c.i + 1) % c.buf.length; s += y; }
      for (const a of ab) { const y = a.buf[a.i]; const v = -s + y; a.buf[a.i] = s + y * 0.5; a.i = (a.i + 1) % a.buf.length; s = v; }
      out[ch][n] = s;
    }
  });
  return out;
}
const rv = reverb(send[0], send[1]);
const L = new Float32Array(N), R = new Float32Array(N);
for (let i = 0; i < N; i++) {
  const d = duck[i];
  const l = drums[0][i] * 0.9 + bass[0][i] * d + synth[0][i] * (0.35 + 0.65 * d) + fx[0][i] * 0.8 + rv[0][i] * 0.9 * (0.5 + 0.5 * d);
  const r = drums[1][i] * 0.9 + bass[1][i] * d + synth[1][i] * (0.35 + 0.65 * d) + fx[1][i] * 0.8 + rv[1][i] * 0.9 * (0.5 + 0.5 * d);
  L[i] = l; R[i] = r;
}
// master: gain normalise to peak ~ then soft clip, fade last 0.4s
let peak = 0; for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
const pre = 1.9 / peak;
const pcm = Buffer.alloc(N * 4);
for (let i = 0; i < N; i++) {
  const t = i / SR, fade = t > DUR - 0.5 ? (DUR - t) / 0.5 : 1;
  const l = Math.tanh(L[i] * pre) * 0.94 * fade, r = Math.tanh(R[i] * pre) * 0.94 * fade;
  pcm.writeInt16LE(Math.round(l * 32767), i * 4); pcm.writeInt16LE(Math.round(r * 32767), i * 4 + 2);
}
const hdr = Buffer.alloc(44);
hdr.write('RIFF', 0); hdr.writeUInt32LE(36 + pcm.length, 4); hdr.write('WAVE', 8); hdr.write('fmt ', 12);
hdr.writeUInt32LE(16, 16); hdr.writeUInt16LE(1, 20); hdr.writeUInt16LE(2, 22); hdr.writeUInt32LE(SR, 24);
hdr.writeUInt32LE(SR * 4, 28); hdr.writeUInt16LE(4, 32); hdr.writeUInt16LE(16, 34); hdr.write('data', 36); hdr.writeUInt32LE(pcm.length, 40);
fs.writeFileSync(path.join(root, 'audio/music.wav'), Buffer.concat([hdr, pcm]));
cues.sort((a, b) => a.beat - b.beat);
fs.writeFileSync(path.join(root, 'audio/cues.json'), JSON.stringify({ bpm: BPM, beat: BEAT, duration: DUR, cues }, null, 1));
console.log('wrote music.wav, cues:', cues.length, 'peak pre-gain', peak.toFixed(2));

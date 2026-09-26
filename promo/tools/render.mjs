// Usage:
//   node tools/render.mjs --preview 0.5,1.2,3.9 [--sheet /tmp/sheet.png] [--cols 4]   contact sheet of times (s)
//   node tools/render.mjs --full [--fps 60] [--from 0 --to 30]                         -> out/zoomies-promo.mp4
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import path from 'node:path';
import { spawn, execFileSync } from 'node:child_process';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const browser = await puppeteer.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  args: ['--allow-file-access-from-files', '--force-color-profile=srgb', '--hide-scrollbars'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
page.on('pageerror', (e) => console.error('PAGE ERROR', e.message));
page.on('console', (m) => m.type() === 'error' && console.error('console:', m.text()));
await page.goto('file://' + path.join(root, 'scene/index.html'));
await page.evaluate(() => window.sceneReady);
const shot = async (t, type = 'jpeg') => {
  await page.evaluate((tt) => window.renderFrame(tt), t);
  return page.screenshot({ type, quality: type === 'jpeg' ? 94 : undefined, optimizeForSpeed: true });
};

if (args.includes('--preview')) {
  const times = opt('--preview').split(',').map(Number);
  const dir = fs.mkdtempSync('/tmp/zprev-');
  for (const [i, t] of times.entries()) fs.writeFileSync(path.join(dir, `${String(i).padStart(3, '0')}.jpg`), await shot(t));
  const cols = +opt('--cols', 4), rows = Math.ceil(times.length / cols);
  const sheet = opt('--sheet', '/tmp/sheet.jpg');
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', '1', '-i', path.join(dir, '%03d.jpg'),
    '-vf', `scale=640:360,tile=${cols}x${rows}:padding=4`,
    '-frames:v', '1', '-q:v', '3', sheet]);
  console.log('sheet', sheet, times.map((t, i) => `${i}=${t}s`).join(' '));
} else {
  const fps = +opt('--fps', 60), from = +opt('--from', 0), to = +opt('--to', 30);
  fs.mkdirSync(path.join(root, 'out'), { recursive: true });
  const out = path.join(root, 'out', opt('--out', 'zoomies-promo.mp4'));
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
    '-ss', String(from), '-t', String(to - from), '-i', path.join(root, 'audio/music.wav'),
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-profile:v', 'high',
    '-c:a', 'aac', '-b:a', '320k', '-shortest', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const n = Math.round((to - from) * fps), t0 = Date.now();
  for (let f = 0; f < n; f++) {
    const buf = await shot(from + f / fps);
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
    if (f % 120 === 0) console.log(`frame ${f}/${n} ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on('close', r));
  console.log('wrote', out);
}
await browser.close();

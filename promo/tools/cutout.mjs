// Splits the real Zoomies app icon into animatable layers (cat head, loose paw) using
// a warm-hue mask + hole filling, executed in headless Chrome's canvas (no extra deps).
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const iconB64 = fs.readFileSync(path.join(root, 'assets/icon.png')).toString('base64');
const browser = await puppeteer.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
const page = await browser.newPage();
const result = await page.evaluate(async (b64) => {
  const img = new Image();
  img.src = 'data:image/png;base64,' + b64;
  await img.decode();
  const W = img.width, H = img.height;
  const c = new OffscreenCanvas(W, H);
  const ctx = c.getContext('2d');
  ctx.drawImage(img, 0, 0);
  const src = ctx.getImageData(0, 0, W, H);
  const d = src.data;
  const mask = new Uint8Array(W * H);
  for (let i = 0; i < W * H; i++) {
    const r = d[i * 4], g = d[i * 4 + 1], b = d[i * 4 + 2];
    mask[i] = (r - b > 38 && r > 70) ? 1 : 0;
  }
  // connected components (4-neighbour)
  const label = new Int32Array(W * H).fill(-1);
  const sizes = [];
  const stack = new Int32Array(W * H);
  for (let i = 0; i < W * H; i++) {
    if (!mask[i] || label[i] >= 0) continue;
    const id = sizes.length; let n = 0, sp = 0;
    stack[sp++] = i; label[i] = id;
    while (sp) {
      const p = stack[--sp]; n++;
      const x = p % W, y = (p / W) | 0;
      const nb = [x > 0 ? p - 1 : -1, x < W - 1 ? p + 1 : -1, y > 0 ? p - W : -1, y < H - 1 ? p + W : -1];
      for (const q of nb) if (q >= 0 && mask[q] && label[q] < 0) { label[q] = id; stack[sp++] = q; }
    }
    sizes.push(n);
  }
  const order = sizes.map((s, i) => [s, i]).sort((a, b) => b[0] - a[0]);
  const fillHoles = (keep) => {
    // region = pixels of component; holes = non-region pixels not reachable from border
    const outside = new Uint8Array(W * H); let sp = 0;
    const push = (p) => { if (!keep[p] && !outside[p]) { outside[p] = 1; stack[sp++] = p; } };
    for (let x = 0; x < W; x++) { push(x); push((H - 1) * W + x); }
    for (let y = 0; y < H; y++) { push(y * W); push(y * W + W - 1); }
    while (sp) {
      const p = stack[--sp]; const x = p % W, y = (p / W) | 0;
      if (x > 0) push(p - 1); if (x < W - 1) push(p + 1); if (y > 0) push(p - W); if (y < H - 1) push(p + W);
    }
    const out = new Uint8Array(W * H);
    for (let i = 0; i < W * H; i++) out[i] = outside[i] ? 0 : 1;
    return out;
  };
  const layer = (compIds) => {
    const keep = new Uint8Array(W * H);
    for (let i = 0; i < W * H; i++) if (compIds.includes(label[i])) keep[i] = 1;
    const filled = fillHoles(keep);
    // soft 3x3 alpha for anti-aliased edges
    const oc = new OffscreenCanvas(W, H); const octx = oc.getContext('2d');
    const out = octx.createImageData(W, H); let minX = W, minY = H, maxX = 0, maxY = 0;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      let s = 0, n = 0;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const xx = x + dx, yy = y + dy; if (xx < 0 || yy < 0 || xx >= W || yy >= H) continue;
        s += filled[yy * W + xx]; n++;
      }
      const a = s / n; const i = y * W + x;
      if (a > 0) {
        out.data.set([d[i * 4], d[i * 4 + 1], d[i * 4 + 2], Math.round(a * 255)], i * 4);
        if (filled[i]) { minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y); }
      }
    }
    octx.putImageData(out, 0, 0);
    return { canvas: oc, box: [minX, minY, maxX, maxY] };
  };
  // whiskers are thin separate components: attach all mid-size comps to the head except the paw
  const big = order.filter(([s]) => s > 3000).map(([, i]) => i);
  const compBoxes = big.map((id) => {
    let minX = W, minY = H, maxX = 0, maxY = 0;
    for (let i = 0; i < W * H; i++) if (label[i] === id) { const x = i % W, y = (i / W) | 0; minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y); }
    return { id, size: sizes[id], box: [minX, minY, maxX, maxY] };
  });
  const pawComp = compBoxes.find((c) => c.box[1] > 600);
  const whiskers = order.filter(([s]) => s > 150 && s <= 3000).map(([, i]) => i);
  const headIds = big.filter((i) => !pawComp || i !== pawComp.id).concat(whiskers);
  const toB64 = async (cv) => {
    const blob = await cv.convertToBlob({ type: 'image/png' });
    const buf = new Uint8Array(await blob.arrayBuffer());
    let s = ''; for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode(...buf.subarray(i, i + 0x8000));
    return btoa(s);
  };
  const head = layer(headIds);
  const res = { comps: compBoxes, head: { box: head.box, png: await toB64(head.canvas) } };
  if (pawComp) { const paw = layer([pawComp.id]); res.paw = { box: paw.box, png: await toB64(paw.canvas) }; }
  return res;
}, iconB64);
await browser.close();
fs.writeFileSync(path.join(root, 'assets/cat_head.png'), Buffer.from(result.head.png, 'base64'));
if (result.paw) fs.writeFileSync(path.join(root, 'assets/cat_paw.png'), Buffer.from(result.paw.png, 'base64'));
console.log(JSON.stringify({ comps: result.comps, head: result.head.box, paw: result.paw?.box }));

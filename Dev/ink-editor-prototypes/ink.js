/* Shared ink engine for the five editor prototypes.
   Strokes are plain data: { id, tool: 'pen' | 'hl', color, size, pts: [[x, y, pressure], ...] }.
   pressure < 0 means "no real pressure" (mouse/trackpad) and is simulated from speed. */
(function () {
  const NS = 'http://www.w3.org/2000/svg';
  const COLORS = [
    ['red', '#ff3b30'], ['blue', '#3a8dff'], ['green', '#34c759'], ['yellow', '#ffcc00'], ['white', '#f2f2f5'],
  ];
  const SIZES = { pen: 3.2, hl: 17 };
  let seq = 0;
  const uid = (p = 's') => p + (++seq).toString(36) + Math.random().toString(36).slice(2, 5);
  const f = (n) => Math.round(n * 10) / 10;

  /* ---------- geometry ---------- */

  function streamline(raw) {
    const out = [];
    let x = raw[0][0], y = raw[0][1];
    for (const p of raw) {
      x += (p[0] - x) * 0.6;
      y += (p[1] - y) * 0.6;
      out.push([x, y, p[2]]);
    }
    out.push(raw[raw.length - 1]);
    const P = [out[0]];
    for (let i = 1; i < out.length; i++) {
      const a = P[P.length - 1], b = out[i];
      if (Math.hypot(b[0] - a[0], b[1] - a[1]) >= 0.7) P.push(b);
    }
    return P;
  }

  function circle(x, y, r) {
    return `M${f(x - r)} ${f(y)}a${f(r)} ${f(r)} 0 1 0 ${f(2 * r)} 0a${f(r)} ${f(r)} 0 1 0 ${f(-2 * r)} 0Z`;
  }

  // Variable-width outline, a small cousin of perfect-freehand.
  function outline(raw, size) {
    if (!raw.length) return '';
    const P = streamline(raw);
    if (P.length < 2) return circle(P[0][0], P[0][1], size * 0.55);
    const L = [0];
    for (let i = 1; i < P.length; i++) L.push(L[i - 1] + Math.hypot(P[i][0] - P[i - 1][0], P[i][1] - P[i - 1][1]));
    const total = L[L.length - 1];
    const taper = total > size * 5;
    const ease = (t) => 1 - (1 - t) * (1 - t);
    let sim = 0.75;
    const R = P.map((p, i) => {
      let pr;
      if (p[2] >= 0) pr = p[2];
      else {
        const d = i ? L[i] - L[i - 1] : 0;
        const target = 1 - Math.min(1, d / (size * 6)) * 0.6;
        sim += (target - sim) * 0.2;
        pr = sim;
      }
      let r = (size / 2) * (0.4 + 0.6 * pr);
      if (taper) {
        const t = Math.min(ease(Math.min(1, L[i] / (size * 2.4))), ease(Math.min(1, (total - L[i]) / (size * 3))));
        r *= Math.max(0.18, t);
      }
      return r;
    });
    const left = [], right = [];
    for (let i = 0; i < P.length; i++) {
      const a = P[Math.max(0, i - 1)], b = P[Math.min(P.length - 1, i + 1)];
      const dx = b[0] - a[0], dy = b[1] - a[1];
      const len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len, ny = dx / len;
      left.push([P[i][0] + nx * R[i], P[i][1] + ny * R[i]]);
      right.push([P[i][0] - nx * R[i], P[i][1] - ny * R[i]]);
    }
    const n = P.length - 1;
    const run = (pts) => {
      let d = '';
      for (let i = 1; i < pts.length - 1; i++) {
        const m = [(pts[i][0] + pts[i + 1][0]) / 2, (pts[i][1] + pts[i + 1][1]) / 2];
        d += `Q${f(pts[i][0])} ${f(pts[i][1])} ${f(m[0])} ${f(m[1])}`;
      }
      const e = pts[pts.length - 1];
      return d + `L${f(e[0])} ${f(e[1])}`;
    };
    const rb = right.slice().reverse();
    return `M${f(left[0][0])} ${f(left[0][1])}` + run(left) +
      `A${f(R[n])} ${f(R[n])} 0 0 0 ${f(right[n][0])} ${f(right[n][1])}` + run(rb) +
      `A${f(R[0])} ${f(R[0])} 0 0 0 ${f(left[0][0])} ${f(left[0][1])}Z`;
  }

  function centerline(raw) {
    if (!raw.length) return '';
    const P = streamline(raw);
    if (P.length < 2) return `M${f(P[0][0])} ${f(P[0][1])}l0.1 0`;
    let d = `M${f(P[0][0])} ${f(P[0][1])}`;
    for (let i = 1; i < P.length - 1; i++) {
      const m = [(P[i][0] + P[i + 1][0]) / 2, (P[i][1] + P[i + 1][1]) / 2];
      d += `Q${f(P[i][0])} ${f(P[i][1])} ${f(m[0])} ${f(m[1])}`;
    }
    const e = P[P.length - 1];
    return d + `L${f(e[0])} ${f(e[1])}`;
  }

  const pathData = (s) => (s.tool === 'hl' ? centerline(s.pts) : outline(s.pts, s.size));

  function attrs(s) {
    return s.tool === 'hl'
      ? { fill: 'none', stroke: s.color, 'stroke-width': s.size, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-opacity': 0.36 }
      : { fill: s.color };
  }

  function strokeEl(s) {
    const p = document.createElementNS(NS, 'path');
    for (const [k, v] of Object.entries(attrs(s))) p.setAttribute(k, v);
    p.setAttribute('d', pathData(s));
    p.dataset.id = s.id;
    return p;
  }

  function bbox(pts, pad = 0) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const p of pts) { x0 = Math.min(x0, p[0]); y0 = Math.min(y0, p[1]); x1 = Math.max(x1, p[0]); y1 = Math.max(y1, p[1]); }
    return { x: x0 - pad, y: y0 - pad, w: x1 - x0 + pad * 2, h: y1 - y0 + pad * 2, cx: (x0 + x1) / 2, cy: (y0 + y1) / 2 };
  }

  // Shift a stroke's points so they start at its own origin; returns the old origin.
  function localize(s) {
    const b = bbox(s.pts);
    s.pts = s.pts.map((p) => [p[0] - b.x, p[1] - b.y, p[2]]);
    return { x: b.x, y: b.y };
  }

  function hit(s, x, y, pad = 7) {
    const r = s.size / 2 + pad;
    return s.pts.some((p) => (p[0] - x) ** 2 + (p[1] - y) ** 2 < r * r);
  }

  // Strokes (with optional per-stroke offsets) to a standalone SVG document string.
  function svgDoc(items, { pad = 10, fixed } = {}) {
    const placed = items.map((it) => ({ s: it.s || it, dx: it.dx || 0, dy: it.dy || 0 }));
    let box;
    if (fixed) box = { x: fixed.x || 0, y: fixed.y || 0, w: fixed.w, h: fixed.h };
    else if (!placed.length) box = { x: 0, y: 0, w: 0, h: 0 };
    else {
      const all = placed.flatMap(({ s, dx, dy }) => s.pts.map((p) => [p[0] + dx, p[1] + dy]));
      box = bbox(all, pad);
    }
    const body = placed.map(({ s, dx, dy }) => {
      const a = Object.entries(attrs(s)).map(([k, v]) => `${k}="${v}"`).join(' ');
      const t = dx || dy ? ` transform="translate(${f(dx)} ${f(dy)})"` : '';
      return `  <path ${a}${t} d="${pathData(s)}"/>`;
    }).join('\n');
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${f(box.x)} ${f(box.y)} ${f(box.w)} ${f(box.h)}">\n${body}\n</svg>\n`;
  }

  const ptsString = (pts) => pts.map((p) => `${Math.round(p[0])},${Math.round(p[1])}`).join(' ');

  /* ---------- pointer capture ---------- */
  // o.active(e) -> bool, o.local(e) -> [x, y], o.tool() -> {tool, color, size},
  // o.live -> SVG element for the in-progress stroke, o.commit(stroke), o.erase([x, y])
  function capture(target, o) {
    let cur = null, path = null, pid = null;
    const add = (ev) => {
      const [x, y] = o.local(ev);
      cur.pts.push([x, y, ev.pointerType === 'pen' && ev.pressure > 0 ? ev.pressure : -1]);
    };
    target.addEventListener('pointerdown', (e) => {
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      if (!o.active(e)) return;
      e.preventDefault();
      e.stopPropagation();
      try { target.setPointerCapture(e.pointerId); } catch (_) {}
      pid = e.pointerId;
      const t = o.tool();
      if (t.tool === 'eraser') { cur = { eraser: true }; o.erase(o.local(e)); return; }
      cur = { id: uid(), tool: t.tool, color: t.color, size: t.size, pts: [] };
      add(e);
      path = strokeEl(cur);
      (typeof o.live === 'function' ? o.live() : o.live).appendChild(path);
      o.start && o.start(cur);
    }, true);
    target.addEventListener('pointermove', (e) => {
      if (!cur || e.pointerId !== pid) return;
      e.preventDefault();
      const evs = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
      for (const ev of evs.length ? evs : [e]) {
        if (cur.eraser) o.erase(o.local(ev)); else add(ev);
      }
      if (!cur.eraser) path.setAttribute('d', pathData(cur));
    });
    const end = (e) => {
      if (!cur || e.pointerId !== pid) return;
      const s = cur;
      cur = null;
      if (s.eraser) { o.eraseEnd && o.eraseEnd(); return; }
      path.remove();
      path = null;
      if (s.pts.length) o.commit(s);
    };
    target.addEventListener('pointerup', end);
    target.addEventListener('pointercancel', end);
  }

  function caretAt(x, y) {
    if (document.caretRangeFromPoint) return document.caretRangeFromPoint(x, y);
    const p = document.caretPositionFromPoint && document.caretPositionFromPoint(x, y);
    if (!p) return null;
    const r = document.createRange();
    r.setStart(p.offsetNode, p.offset);
    r.collapse(true);
    return r;
  }

  /* ---------- hand-drawn seed strokes ---------- */
  function rng(seed) {
    let s = seed >>> 0 || 1;
    return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  }
  function wobble(pts, seed, amp = 1.2) {
    const r = rng(seed);
    const ph = r() * 6, k = 0.05 + r() * 0.04;
    return pts.map((p, i) => [p[0] + Math.sin(i * k * 3 + ph) * amp * 0.6, p[1] + Math.cos(i * k * 2 + ph) * amp, 0.55 + 0.35 * Math.sin(i * 0.11 + ph)]);
  }
  const fake = {
    line(x1, y1, x2, y2, seed = 1, bow = 2) {
      const n = Math.max(6, Math.round(Math.hypot(x2 - x1, y2 - y1) / 4));
      const nx = -(y2 - y1), ny = x2 - x1, nl = Math.hypot(nx, ny) || 1;
      const pts = [];
      for (let i = 0; i <= n; i++) {
        const t = i / n, b = Math.sin(t * Math.PI) * bow;
        pts.push([x1 + (x2 - x1) * t + (nx / nl) * b, y1 + (y2 - y1) * t + (ny / nl) * b]);
      }
      return wobble(pts, seed, 0.6);
    },
    ellipse(cx, cy, rx, ry, seed = 1, turn = 1.12) {
      const r = rng(seed);
      const start = -2.4 + r() * 0.6, n = Math.round((rx + ry) * 0.9);
      const pts = [];
      for (let i = 0; i <= n; i++) {
        const t = start + (i / n) * Math.PI * 2 * turn;
        const grow = 1 + (i / n) * 0.06;
        pts.push([cx + Math.cos(t) * rx * grow, cy + Math.sin(t) * ry * grow]);
      }
      return wobble(pts, seed, 1.3);
    },
    rect(x, y, w, h, seed = 1) {
      const c = [[x, y], [x + w, y + 1], [x + w - 1, y + h], [x + 1, y + h - 1], [x + 2, y - 1]];
      let pts = [];
      for (let i = 0; i < 4; i++) pts = pts.concat(fake.line(c[i][0], c[i][1], c[i + 1][0], c[i + 1][1], seed + i, 1.2));
      return pts;
    },
    arrowHead(x1, y1, x2, y2, seed = 1, len = 11) {
      const a = Math.atan2(y2 - y1, x2 - x1);
      const p1 = [x2 - len * Math.cos(a - 0.5), y2 - len * Math.sin(a - 0.5)];
      const p2 = [x2 - len * Math.cos(a + 0.5), y2 - len * Math.sin(a + 0.5)];
      return fake.line(p1[0], p1[1], x2, y2, seed, 0.3).concat(fake.line(x2, y2, p2[0], p2[1], seed + 1, 0.3));
    },
    scribble(x, y, w, h, seed = 1) {
      const corners = [];
      const n = Math.round(w / 6);
      for (let i = 0; i <= n; i++) corners.push([x + (i / n) * w, y + (i % 2 ? h : 0)]);
      let out = [];
      for (let i = 1; i < corners.length; i++) out = out.concat(fake.line(corners[i - 1][0], corners[i - 1][1], corners[i][0], corners[i][1], seed + i, 0));
      return out;
    },
    stroke(pts, color = COLORS[0][1], tool = 'pen', size) {
      return { id: uid(), tool, color, size: size || SIZES[tool], pts };
    },
  };

  /* ---------- toolbar + keys ---------- */
  const icon = {
    type: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M3 3.5h10M8 3.5v9.5M6 13h4"/></svg>',
    pen: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M10.5 2.5l3 3-8 8-3.6.6.6-3.6z"/><path d="M9 4l3 3"/></svg>',
    hl: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M9.5 2.5l4 4-5 5-4-4z"/><path d="M4.5 7.5L2.5 12l1.5 1.5 4.5-2"/></svg>',
    eraser: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M9.5 2.8l3.7 3.7-6.7 6.7H3.6l-1-1a1.4 1.4 0 010-2z"/><path d="M6.5 13.2h7"/></svg>',
    undo: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5.5 3.5L2.5 6.5l3 3"/><path d="M2.5 6.5h7a3.5 3.5 0 010 7H7"/></svg>',
    text: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><rect x="2.5" y="3" width="11" height="10" rx="1.5"/><path d="M5.5 6h5M8 6v4.5" stroke-linecap="round"/></svg>',
    hand: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" stroke-linecap="round"><path d="M5.5 8V3.8a1 1 0 012 0V7.5M7.5 7V2.8a1 1 0 012 0V7.5M9.5 7.2V3.8a1 1 0 012 0v5.4c0 2.6-1.6 4.3-4 4.3-1.6 0-2.6-.8-3.4-2L2.7 9a1 1 0 011.6-1.1l1.2 1.3"/></svg>',
  };

  const isEditable = (el) => el && (el.isContentEditable || /^(INPUT|TEXTAREA)$/.test(el.tagName));

  function toolbar(host, opt = {}) {
    const st = { mode: opt.mode || 'type', temp: false, tool: 'pen', color: COLORS[0][1], subs: [] };
    st.drawing = () => opt.modes === false || st.mode === 'draw' || st.temp;
    st.size = () => SIZES[st.tool] || 3.2;
    st.on = (fn) => st.subs.push(fn);
    const tools = [['pen', 'Pen', 'P'], ['hl', 'Highlighter', 'H'], ['eraser', 'Eraser', 'E']].concat(opt.extraTools || []);
    const box = document.createElement('div');
    box.className = 'inkbar';
    box.innerHTML =
      (opt.modes !== false
        ? `<div class="seg" role="group" aria-label="Mode">
             <button type="button" data-mode="type" title="Type (T or Esc)">${icon.type}<span>Type</span></button>
             <button type="button" data-mode="draw" title="Draw (⌘D, or hold ⌥ to draw for a moment)">${icon.pen}<span>Draw</span><kbd>⌘D</kbd></button>
           </div>` : '') +
      `<div class="seg" role="group" aria-label="Tool">${tools.map(([id, name, key]) =>
        `<button type="button" data-tool="${id}" title="${name} (${key})" aria-label="${name}">${icon[id] || ''}</button>`).join('')}</div>` +
      `<div class="swatches" role="group" aria-label="Ink color">${COLORS.map(([id, hex], i) =>
        `<button type="button" class="swatch" data-color="${hex}" style="--c:${hex}" title="${id} (${i + 1})" aria-label="${id}"></button>`).join('')}</div>` +
      (opt.undo ? `<button type="button" class="btn" data-undo title="Undo ink (⌘Z while drawing)">${icon.undo}<span>Undo</span></button>` : '');
    host.prepend(box);

    const sync = () => {
      box.querySelectorAll('[data-mode]').forEach((b) => b.setAttribute('aria-pressed', String(st.drawing() ? b.dataset.mode === 'draw' : b.dataset.mode === 'type')));
      box.querySelectorAll('[data-tool]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.tool === st.tool)));
      box.querySelectorAll('[data-color]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.color === st.color)));
      if (st.drawing() && !(opt.inkCursor && !opt.inkCursor(st))) document.body.dataset.ink = st.tool;
      else delete document.body.dataset.ink;
    };
    st.set = (k, v) => {
      st[k] = v;
      if (k === 'color' && st.tool === 'eraser') st.tool = 'pen';
      sync();
      st.subs.forEach((fn) => fn(k, v));
    };
    box.addEventListener('mousedown', (e) => { if (e.target.closest('button')) e.preventDefault(); });
    box.addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      if (b.dataset.mode) st.set('mode', b.dataset.mode);
      if (b.dataset.tool) { st.set('tool', b.dataset.tool); if (opt.modes !== false && st.mode !== 'draw' && !(opt.toolOnly || []).includes(b.dataset.tool)) st.set('mode', 'draw'); }
      if (b.dataset.color) { st.set('color', b.dataset.color); if (opt.modes !== false && st.mode !== 'draw') st.set('mode', 'draw'); }
      if (b.hasAttribute('data-undo')) opt.undo();
    });
    document.addEventListener('keydown', (e) => {
      const meta = e.metaKey || e.ctrlKey;
      const k = e.key.toLowerCase();
      if (meta && k === 'd' && opt.modes !== false) { e.preventDefault(); st.set('mode', st.mode === 'draw' ? 'type' : 'draw'); return; }
      if (meta && k === 'z' && opt.undo && (st.mode === 'draw' || !isEditable(document.activeElement))) { e.preventDefault(); opt.undo(e.shiftKey); return; }
      if (e.key === 'Alt' && opt.modes !== false && !st.temp) { st.temp = true; sync(); st.subs.forEach((fn) => fn('temp', true)); return; }
      if (meta || e.altKey) return;
      const keysLive = opt.modes === false ? !isEditable(document.activeElement) : st.mode === 'draw';
      if (!keysLive) return;
      let done = true;
      const extra = (opt.extraTools || []).find((t) => t[2].toLowerCase() === k);
      if (k === 'p') st.set('tool', 'pen');
      else if (k === 'h') st.set('tool', 'hl');
      else if (k === 'e') st.set('tool', 'eraser');
      else if (extra) st.set('tool', extra[0]);
      else if (/^[1-5]$/.test(k)) st.set('color', COLORS[+k - 1][1]);
      else if ((k === 't' || e.key === 'Escape') && opt.modes !== false) st.set('mode', 'type');
      else done = false;
      if (done) e.preventDefault();
    });
    const release = () => { if (st.temp) { st.temp = false; sync(); st.subs.forEach((fn) => fn('temp', false)); } };
    document.addEventListener('keyup', (e) => { if (e.key === 'Alt') release(); });
    window.addEventListener('blur', release);
    sync();
    return st;
  }

  /* ---------- file view ---------- */
  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const RX = /(<!--[\s\S]*?-->)|(\[\^\d+\]:?)|(!\[[^\]\n]*\]\([^)\n]*\))|(~~[^~\n]+~~)|(==[^=\n]+==)|(^#{1,6} .*$)|("[\w:-]+"(?=\s*:))|(<\/?[a-z][^>]*>)/gm;
  const CLS = ['c-com', 'c-mk', 'c-img', 'c-del', 'c-mark', 'c-h', 'c-key', 'c-tag'];
  function highlight(text) {
    let out = '', last = 0, m;
    RX.lastIndex = 0;
    while ((m = RX.exec(text))) {
      out += esc(text.slice(last, m.index));
      const g = m.slice(1).findIndex((x) => x !== undefined);
      out += `<span class="${CLS[g]}">${esc(m[0])}</span>`;
      last = m.index + m[0].length;
      if (!m[0].length) RX.lastIndex++;
    }
    return out + esc(text.slice(last));
  }
  // Long coordinate strings are clipped on screen; Copy still copies the full file.
  const clip = (t) => t.replace(/"([0-9MQLAZa .,\-]{56})[0-9MQLAZa .,\-]{24,}"/g, (_, a) => `"${a}…"`);

  function fileView(host, getFiles) {
    host.innerHTML = '<div class="fv-head"><div class="fv-tabs" role="tablist" aria-label="Saved files"></div><button type="button" class="btn fv-copy">Copy</button></div><pre class="fv-body" tabindex="0"><code></code></pre><div class="fv-foot"></div>';
    const tabs = host.querySelector('.fv-tabs'), code = host.querySelector('code'), foot = host.querySelector('.fv-foot');
    let active = 0, files = [], timer = 0;
    const render = () => {
      files = getFiles();
      if (active >= files.length) active = 0;
      tabs.innerHTML = files.map((fl, i) => `<button type="button" role="tab" aria-selected="${i === active}" data-i="${i}">${esc(fl.name)}</button>`).join('');
      const fl = files[active];
      code.innerHTML = highlight(clip(fl.text));
      const bytes = new Blob([fl.text]).size;
      foot.innerHTML = `<b>${bytes > 1024 ? (bytes / 1024).toFixed(1) + ' KB' : bytes + ' B'}</b>${fl.note ? ' · ' + fl.note : ''}`;
    };
    tabs.addEventListener('click', (e) => { const b = e.target.closest('[data-i]'); if (b) { active = +b.dataset.i; render(); } });
    host.querySelector('.fv-copy').addEventListener('click', (e) => {
      const btn = e.currentTarget;
      const done = (t) => { btn.textContent = t; setTimeout(() => (btn.textContent = 'Copy'), 1200); };
      const fallback = () => { const r = document.createRange(); r.selectNodeContents(code); const s = getSelection(); s.removeAllRanges(); s.addRange(r); done('Selected'); };
      try { navigator.clipboard.writeText(files[active].text).then(() => done('Copied'), fallback); } catch (_) { fallback(); }
    });
    render();
    return { refresh() { clearTimeout(timer); timer = setTimeout(render, 90); }, now: render };
  }

  /* ---------- contenteditable -> Markdown ---------- */
  const BLOCK = /^(P|DIV|H1|H2|H3|LI|UL|OL|FIGURE|BLOCKQUOTE)$/;
  function toMarkdown(root, hook) {
    const inl = (node) => {
      let s = '';
      for (const c of node.childNodes) {
        if (c.nodeType === 3) s += c.data.replace(/​/g, '').replace(/ /g, ' ');
        else if (c.nodeType === 1) {
          const h = hook ? hook(c, false) : null;
          if (h != null) s += h;
          else if (c.tagName === 'BR') s += '\n';
          else s += inl(c);
        }
      }
      return s;
    };
    const blocks = [];
    let loose = '';
    for (const c of root.childNodes) {
      if (c.nodeType === 1 && BLOCK.test(c.tagName)) {
        if (loose.trim()) blocks.push(loose.trim());
        loose = '';
        const h = hook ? hook(c, true) : null;
        if (h != null) { blocks.push(h); continue; }
        if (c.tagName === 'UL' || c.tagName === 'OL') { blocks.push([...c.children].map((li) => '- ' + inl(li).trim()).join('\n')); continue; }
        const prefix = { H1: '# ', H2: '## ', H3: '### ' }[c.tagName] || '';
        blocks.push(prefix + inl(c).replace(/\n+$/, '').trim());
      } else if (c.nodeType === 3) loose += c.data;
      else if (c.nodeType === 1) { const h = hook ? hook(c, false) : null; loose += h != null ? h : inl(c); }
    }
    if (loose.trim()) blocks.push(loose.trim());
    return blocks.filter((b) => b.replace(/^#+ /, '').trim() !== '').join('\n\n') + '\n';
  }

  let toastTimer = 0;
  function toast(msg) {
    let t = document.querySelector('.toast');
    if (!t) { t = document.createElement('div'); t.className = 'toast'; t.setAttribute('role', 'status'); document.body.appendChild(t); }
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), 1600);
  }

  window.Ink = {
    NS, COLORS, SIZES, uid, outline, centerline, pathData, strokeEl, bbox, localize, hit, svgDoc, ptsString,
    capture, caretAt, fake, toolbar, icon, fileView, toMarkdown, toast, isEditable, f,
  };
})();

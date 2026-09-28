// v4 G2 — beats 7.6-54: the user's Mac + capture (same as v3 F2) and the camera for the whole flow.
// Subtitles/recaps/keyboard live in hud4.js (screen space).
Z.scene({
  name: 'desktop4', from: 7.6, to: 54,
  build(root) {
    this.desk = Z.el(root, 'div', { width: '1920px', height: '1080px' });
    Z.el(this.desk, 'div', { width: '1920px', height: '1080px', background: 'radial-gradient(ellipse at 18% 85%, #174f53 0%, rgba(0,0,0,0) 50%), radial-gradient(ellipse at 88% 10%, #5a3a1c 0%, rgba(0,0,0,0) 45%), linear-gradient(160deg,#0e2127,#070f12)' });
    const menu = Z.el(this.desk, 'div', { width: '1920px', height: '40px', background: 'rgba(22,24,26,.75)', borderBottom: '1px solid rgba(255,255,255,.06)', display: 'flex', alignItems: 'center', gap: '28px', padding: '0 26px', font: '600 17px system-ui', color: 'rgba(255,255,255,.92)' });
    ['Safari', 'File', 'Edit', 'View', 'History'].forEach((w, i) => { const s = document.createElement('span'); s.textContent = w; if (i) s.style.fontWeight = 400; menu.appendChild(s); });
    Z.set(Z.symbol(this.desk, 'camera', 24, '#fff'), { x: 1720, y: 20 });
    Z.el(this.desk, 'div', { left: '1780px', top: '10px', font: '500 17px system-ui', color: 'rgba(255,255,255,.9)' }, 'Mon 9:41');
    const C = Z.R.CAP, bw = 1240, bh = 800, bx = 960 - bw / 2, by = 560 - bh / 2 + 10;
    const br = Z.el(this.desk, 'div', { left: bx + 'px', top: by + 'px', width: bw + 'px', height: bh + 'px', borderRadius: '16px', background: '#1d2123', boxShadow: '0 0 0 1px rgba(255,255,255,.1), 0 40px 100px rgba(0,0,0,.5)', overflow: 'hidden' });
    const tb = Z.el(br, 'div', { width: '100%', height: '52px', background: '#23282a' });
    ['#ec6a5e', '#f4bf4f', '#61c554'].forEach((c, i) => Z.el(tb, 'div', { left: 20 + i * 22 + 'px', top: '20px', width: '13px', height: '13px', borderRadius: '50%', background: c }));
    Z.el(tb, 'div', { left: '440px', top: '11px', width: '360px', height: '30px', borderRadius: '8px', background: 'rgba(255,255,255,.07)', font: '500 16px system-ui', color: 'rgba(255,255,255,.7)', textAlign: 'center', paddingTop: '5px' }, 'localhost:3000/login');
    Z.el(br, 'div', { top: '52px', width: '100%', height: bh - 52 + 'px', background: '#e8ecf2' });
    const pg = Z.el(br, 'div', { left: C.x - 280 * C.s - bx + 'px', top: C.y - 250 * C.s - by + 'px', width: '560px', height: '500px', transformOrigin: '0 0', transform: `scale(${C.s})` });
    Z.loginPage(pg).page.style.background = '#e8ecf2';
    this.hole = Z.el(root, 'div', { boxShadow: '0 0 0 3000px rgba(0,0,0,.42)' });
    this.sel = Z.marquee(root);
  },
  render(t) {
    const B = Z.b, e = Z.ease, bt = t / Z.BEAT, C = Z.R.CAP;
    const inP = Z.soft(t - B(7.6), 1.1), dim = e.inOutCubic(Z.prog(t, B(12.1), B(12.6)));
    Z.set(this.desk, { x: 960, y: 540 + (1 - inP) * 30, o: inP });
    this.desk.style.filter = `brightness(${1 - dim * 0.55}) blur(${dim * 4}px)`;
    const x0 = C.x - 280 * C.s - 8, y0 = C.y - 250 * C.s - 8, x1 = C.x + 280 * C.s + 8, y1 = C.y + 250 * C.s + 8;
    const dp = e.inOutCubic(Z.prog(t, B(9.8), B(11.6)));
    const on = bt >= 9.6 && bt < 12 ? Z.soft(t - B(9.6), 0.25) : 0;
    const cx = Z.lerp(x0 + 16, x1, dp), cy = Z.lerp(y0 + 16, y1, dp);
    this.sel.render(t, x0, y0, cx, cy, on);
    Object.assign(this.hole.style, { width: cx - x0 + 'px', height: cy - y0 + 'px' });
    Z.set(this.hole, { x: (x0 + cx) / 2, y: (y0 + cy) / 2, o: on });
    Z.flash(Z.pulse(t - B(12), 12) * (bt >= 12 ? 0.28 : 0));
    // camera: gentle push on the panels while typing / tabbing (18-28); editor is posed big already
    const zp = e.inOutCubic(Z.prog(t, B(18), B(18.6))) * (1 - e.inOutCubic(Z.prog(t, B(28), B(28.5))));
    Z.camera.s = 1 + 0.14 * zp; Z.camera.y = (540 - 500) * 0.14 * zp;
  },
});

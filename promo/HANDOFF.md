# Zoomies promo video — handoff

Goal: 30s professional motion-graphics intro/showreel for Zoomies (macOS screenshot + annotate app for agentic coding).
Music-synced, real product assets broken into animatable components, juicy motion. Output: `promo/out/zoomies-promo.mp4` (1920x1080, 60fps).

## Global sync contract
- 128 BPM, 4/4. beat = 0.46875s, bar = 1.875s. 64 beats = exactly 30.0s. 16 bars.
- Key F minor. Progression per bar: Fm, Db, Ab, Eb (repeats).
- Structure (bar numbers 1-based, time in s):
  - A  bars 1-2   (0.00-3.75)   intro/tension: keycaps ⌥ ⇧ 4 slam, crosshair, marquee drag, riser. Beat 7.5 (3.52s) = shutter.
  - DROP at 3.75s (bar 3): shutter flash + cat bursts out of dashed selection, ZOOMIES wordmark.
  - B  bars 3-6   (3.75-11.25)  logo + tagline.
  - C  bars 7-10  (11.25-18.75) feature montage: capture → rename → annotate toolbar assembling on 8ths, tools draw on beats.
  - D  bars 11-14 (18.75-26.25) "2s / 3s / 5s" speed typography, note travels to agent.
  - E  bars 15-16 (26.25-30.0)  logo lockup, ⌥⇧4, github.com/bald-ai/zoomies, final hit.

## Stages / status
1. [DONE] Assets — `promo/assets/`
   - `icon.png` (1024, from Sources/Resources/Zoomies.icns via sips)
   - `cat_head.png`, `cat_paw.png` — full 1024 canvas layers cut from icon (`tools/cutout.mjs`); head box [94,98,733,669], paw box [350,652,486,813] in icon px. Icon's dashed square ≈ [150,170,875,860], teal fill curve under the cat — rebuild as SVG.
   - `symbols/*.png` — real SF Symbols from the editor toolbar (white, tint via CSS mask) (`tools/export_symbols.swift`).
   - `screenshot-sound.mp3` — the app's real shutter sound.
   - UI facts (from Sources/EditorWindowController.swift): editor bg #131515 border #343737; toolbar group surface #2b2e2e radius 9, border white 8%; icon buttons 26x26 radius 6 tint #dedfe0; active tool bg #253e54 tint #8ac5ff; color swatch 18px radius 9. Groups: [pen W, line D, arrow A, rect R, ellipse E, text T, marker F, select S, color Q] [undo, redo, clear] [zoom-, 100%, zoom+] [cancel xmark, save tray.and.arrow.down]. Palette defaults red #ff3b30, blue #007aff, green #34c759, black, yellow #ffcc00, white. Rename panel: "Filename" label 13pt medium, hints "Enter: Save    ⌘↩: Copy+Save    ⌘⌫: Copy+Delete    Esc: Delete    Tab: Note". Menu bar icon: SF "camera". Brand colors from icon: navy #0b1a20, teal #1c8c8c / dashes #45d0c4, orange #f7a043, outline brown #b8591c.
   - Tooling: `promo/node_modules` has puppeteer-core 25.11.0; Chrome at /Applications/Google Chrome.app. ffmpeg at /opt/homebrew/bin. No numpy/PIL (use node).
2. [DONE] Music — `node tools/music.mjs` (~20s) → `audio/music.wav` (30.0s, TP -0.9dBFS) + `audio/cues.json`
   (every SFX/visual hit with beat+time; visuals MUST key off these). Key cues (beats): key0/1/2 = 0,1,2; marqueeStart 3;
   shutter1 7.5; drop 8; letter0-6 = 10..11.5 (16ths); tagWord0-3 = 12..15; toDesktop 16 (whoosh 14.5-16);
   miniKey 16.5/17/17.5; marquee2Start 18; shutter2 20; (whoosh 22.5-24); renamePanel 24; type0-8 = 24.5..26.5 (16ths);
   enter 27; tool0-8 = 28..32 (8ths, ascending blips); rect 32.5, arrow 33.5, marker1 34.5, marker2 35.5; noteText 36.5;
   color0-3 = 37.5..39; (snare fill+whoosh 38.5-40); speed_2s 40 (shutter), speed_3s 44, speed_5s 48; toAgent 51; paste 52;
   (riser 52-56, roll 54-56); finale 56; stamp 60; end 64. Kick 4-on-floor on every beat 8-55 & 56-60.
3. [IN PROGRESS] Animation — `scene/index.html` with deterministic `window.renderFrame(t)` (no CSS animations/transitions).
   - `engine.js` (Z.* easing/spring/wobble/beatPulse/rng, Z.set centre-anchored transforms, Z.symbol SF-mask, Z.keycap,
     Z.fx analytic burst/ring/speedLines on per-scene canvas, Z.scene registry, Z.shake(beat,amp,decay), Z.camera per-frame).
   - `components.js` (Z.icon layered cat icon w/ ants/blink, Z.bg, Z.loginPage bug page, Z.toolbar real editor toolbar,
     Z.letters/Z.setInline kinetic type, Z.marquee). `main.js` composes scenes by beat window + flash + vignette + grain.
   - Scenes (all DONE, previewed): s1_intro (0-8), s2_logo (8-16), s3_capture (15.5-24), s4_editor (24-40),
     s5_speed (40-56), s6_finale (56-64.5). Preview: `node tools/render.mjs --preview 1.0,2.5 --cols 4` → /tmp/sheet.jpg
     (times in SECONDS; sec = beat*0.46875).
4. [TODO] Render — `tools/render.mjs` (puppeteer frame capture → ffmpeg + music) → `out/zoomies-promo.mp4`; review sampled frames, polish.

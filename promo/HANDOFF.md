# Zoomies promo video — handoff

**Delivery rule (user):** always end each iteration by copying the fresh render to the Desktop as
`~/Desktop/zoomies-promo_vN.mp4` with the next N (never overwrite). Existing: v1 `zoomies-promo.mp4` (full-energy cut),
v2 `zoomies-promo_v2.mp4` (light cut), v3 `zoomies-promo_v3.mp4` (real rename→note→editor flow), v4 `zoomies-promo_v4.mp4` (47.5s keybind story). Next → `_v5`.

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
4. [DONE] Render — `node tools/render.mjs --full --fps 60` (~2 min) → `out/zoomies-promo.mp4`
   (1920x1080 60fps H.264 CRF15 + AAC 320k, 30.000s, -11.8 LUFS). Sync verified by pulling frames at cue times.
   Partial re-render: `--from 10 --to 14 --out test.mp4`.

## User feedback on v1 (2026-09-26) — NEXT TASK, not started
User liked it overall but found v1 **too overwhelming**. Wants a **lighter version focused on the value**.
Keep v1 as-is (`out/zoomies-promo.mp4`); build the light cut alongside it (e.g. separate scene set / `--out zoomies-promo-light.mp4`).
Ideas for the light cut (to confirm with the user before building):
- Less FX: drop most confetti/speed lines/shakes/flashes/grain; keep a hit only on a few key moments.
- Calmer, slower music (fewer layers, lower BPM or half-time feel); fewer, longer shots and more breathing room.
- Lead with the problem → value: capture → annotate/prompt → paste to agent, with one clear message per shot
  (e.g. "Show your agent exactly what you mean." / "Capture. Mark it up. Paste." / "Seconds, not minutes.").
- Fewer on-screen elements at once; larger UI, cleaner type, simple eased moves instead of springs everywhere.

## Light cut (v2) — DONE
Output: `out/zoomies-promo-light.mp4` (+ copy to ~/Desktop). v1 files untouched; v2 reuses `engine.js` + `components.js`.
- Sync contract: **96 BPM**, beat = 0.625s, bar = 2.5s, 48 beats = 30.0s, 12 bars. Key Ab major, bars: Ab Fm Db Eb (x3; bar 11 Db|Eb, bar 12 Ab).
- Principles: one message per shot, value first; no shakes/confetti/speed lines; soft eased moves (outCubic/outQuint,
  damped springs ≥0.6); light grain; lots of negative space; big readable UI.
- Storyboard (beats):
  - A  0-8   Problem: "Explaining a UI bug to your agent?" + a long awkward text description bubble. b6: "Show it instead."
  - B  8-16  Capture: clean browser w/ login bug, small ⌥⇧4 hint, marquee drag, soft shutter b12. Caption "Capture".
  - C  16-28 Mark it up: editor (static toolbar), rect b18, marker1 b20, marker2 b21, note typed b22-24. Caption "Mark it up. Add a prompt."
  - D  28-36 Paste: card → agent chat (paste b30), prompt sent b32, agent reply b34. Caption "Your agent sees exactly what you mean."
  - E  36-40 Value: "Capture in 2s" (b36) / "Annotate + prompt in 5s" (b38).
  - F  40-48 Lockup: icon, blink, "Zoomies", tagline, URL; fade last 0.5s.
- Stages: L1 music [DONE: `node tools/music_light.mjs` → audio/music-light.wav, -11.4 LUFS; cues in audio/cues-light.json] · L2 scenes [DONE: `scene/light.html` (ZCFG bpm 96, grain .07) + `light_common.js`
  (Z.L geometry, Z.soft/Z.calm/Z.env, Z.words/revealWords, Z.caption crossfading step captions, Z.annotatedCard) +
  `l1_problem` (0-8) `l2_capture` (7.6-16) `l3_markup` (15.5-28) `l4_agent` (27.5-36) `l5_value` (35.8-40) `l6_lockup` (40-48.5)]
  · L3 render: `node tools/render.mjs --page light.html --audio audio/music-light.wav --out zoomies-promo-light.mp4 --full`
  (preview: `--page light.html --preview 5,12`). DONE: out/zoomies-promo-light.mp4 (30.0s, 60fps, 18MB), copied to ~/Desktop.
  Note: engine.js/main.js now read `window.ZCFG` (bpm/grain/vignette); v1 defaults unchanged (verified).
- render.mjs gains `--page light.html --audio audio/music-light.wav` flags.

## v3 — real 3-screen flow (DONE)
User feedback on v2: "does not look like the flow my users go through". Real UI reference screenshots (2x retina px) are in
`../zoomies_web/reference/` (1-rename-panel.png, 2-note-panel.png, 3-editor-empty.png, 4-editor-annotated.png, pdf).
Real flow: ⌥⇧4 → **Rename panel** (auto name `Screenshot_2026-09-28_…` selected, type over it) → Tab → **Note panel**
→ Tab → **Editor** (pen active by default; A/R/F tools) → ⌘↩ Copy+Save (note burned in below image on a WHITE strip,
black text, per WorkflowNoteRenderer) → ⌘V into agent (no prompt typing needed: the note travels in the image).
- Build UI at the screenshots' 2x px sizes (1:1 on 1080p): rename panel 884x430 r24; note panel 1116x270; editor window
  1158x815 r20 bg ~#202023, traffic lights 24px @ (28,28) step 40; toolbar tray (#131515, border #343737, r24) holding
  Z.toolbar(scale 2). Panel text: title 26px/500, hints 22px gray joined by wide gaps. Rename field: blue focus ring,
  selection highlight ~#3a5f8a.
- Files: `scene/v3.html`, `scene/real_ui.js` (Z.R.* components), `f2_capture.js` (7.6-28: capture + dimmed browser
  backdrop), `f3_panels.js` (12-20.5 rename→note), `f4_editor.js` (19.5-28), `f5_agent.js` (27.5-36); reuses
  l1_problem, l5_value, l6_lockup, light_common. Music: `node tools/music_light.mjs v3` → audio/music-light-v3.wav.
- v3 beat map (96 BPM): capture 8-12 (keys 9/9.25/9.5, marquee 9.8-11.6, shutter 12) · rename 12.3, typing 13-15,
  Tab 15.5 · note 16, typing 16.5-19, Tab 19.5 · editor 20 (pen), A 21 arrow, R 22.5 rect, F 24 marker1, 25 marker2,
  ⌘↩ 26.5 (note strip burns in) · agent 28.2, ⌘V 29.5→paste 30, send 31.5, reply 33, value line 33.4 · value 36/38 · lockup 40.
- Output: out/zoomies-promo-v3.mp4 → ~/Desktop/zoomies-promo_v3.mp4 (DONE, 30.0s 60fps, cue-synced frames verified).
  Render: `node tools/render.mjs --page v3.html --audio audio/music-light-v3.wav --out zoomies-promo-v3.mp4 --full`.
  Camera push-in (F2 owns it): 1.25 on panels (b12.2-20), 1.1 on editor (b19.6-27); subtitle bar counter-scaled.
  Next render → `_v4`.

## v4 — longer (47.5s), full keybind story (DONE)
Feedback on v3: make it longer; focus on ALL left-hand editor keybinds; show full keybind control/optionality on the
rename screen; show Tab / Shift+Tab movement; on every window transition display what was pressed in that part.
Facts (Swift): Rename Tab→Note (Shift+Tab: nothing); Note Tab→Editor, Shift+Tab→Rename; Editor Shift+Tab→Note
(EditorCanvasView keyCode 48+shift → .backToNote). Delete alert: "Delete this screenshot?" / buttons "Delete (Esc)" "Go Back (R)".
⌘-hold (reference 6): hint bar "Hover over a shortcut to see it spelled out." above toolbar + keycap badge under every control.
- 96 BPM, 76 beats = 47.5s (19 bars). [L1 DONE] `node tools/music_light.mjs v4` → audio/music-light-v4.wav + cues-light-v4.json
  (v2/v3 modes still byte-identical).
- Beat map: problem 0-8 · capture 8-12 (shutter 12; recap "Capture" 12.1) · rename 12.3; option spotlight Enter 13, ⌘↩ 14,
  ⌘⌫ 15, Esc 16, Tab 17 (cards row y≈850); type name 18.25-20.25; Tab 20.75 (recap "Rename") · note 21.25, type 21.75-24.25,
  ⇧Tab 25 → rename 25.3, Tab 26.5 → note, Tab 28 → editor (recap "Note") · editor 28.7 at pose (1250,560,.9) with left-hand
  keyboard at left: ⌘ hold 30-32 (badges), W 32.5, D 33.75, A 35, R 36.25, Q 37.5 (blue), E 38.5, T 39.75 (type 39.9-40.8),
  1 41.25 (red), F 42.25 (+click 43), S 44.25 (move text 44.6-45.2), ⌘Z 46, ⌘⇧Z 47, ⇧Tab 48.5 → note, Tab 50.5 → editor,
  ⌘↩ 52 (recap "Editor") · agent 53.5-62 (f5 shift +26) · value 62-66.2 (l5 shift +26.2) · lockup 66.2-76 (l6 shift +26.2).
- Files: `scene/v4.html`, `real_ui4.js`, `g2_desktop.js`, `g3_panels.js`, `g4_editor.js`, `hud4.js` (last layer; undoes
  camera transform so HUD is screen-space: subtitles, flow indicator, recaps, rename option cards, keyboard).
  l5_value/l6_lockup/f5_agent read Z.CFG.valueAt / lockupAt / agentShift / duration (defaults keep v2/v3 identical).
- Output: out/zoomies-promo-v4.mp4 → ~/Desktop/zoomies-promo_v4.mp4 (DONE, 47.5s 60fps).
  Render: `node tools/render.mjs --page v4.html --audio audio/music-light-v4.wav --out zoomies-promo-v4.mp4 --full --to 47.5`
  (always pass --to = duration for non-30s cuts). Next render → `_v5`.

## Possible next polish (not started)
- Real frame-accumulation motion blur (render 4 subframes/frame and average) for whips/slams.
- Music: currently synthesized; can swap `audio/music.wav` for a licensed track at 128 BPM keeping the cue grid.
- Vertical 1080x1920 cut for socials (scenes assume 1920x1080 coordinates).

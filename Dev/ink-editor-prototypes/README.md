# Ink editor prototypes

Five web prototypes for mixing text and drawing in Zoomies notes, made 2026-10-01 as inspiration for replacing the plain Markdown marker editor. Throwaway code: vanilla HTML/JS, no build step.

Open `index.html` in a browser. Each tab is one prototype, with a live view of the file it would save. Published copy: https://claude.ai/artifact/JRPEN3yTzmS8hqje6uoUcW

| File | Prototype | Idea | Saves as |
|---|---|---|---|
| `glass.html` | Glass Layer | Clear ink sheet over the text; strokes pin to the word under them | `.md` with `<!--ink n-->` anchors + hidden ink comment block |
| `sketch.html` | Sketch Blocks | Drawings are blocks between paragraphs | Markdown image links + `.svg` files |
| `margin.html` | Margin Notes | ⌘F markers with note cards in the margin, cards can hold a sketch | Current `[^n]` footnote format + optional image per note |
| `redpen.html` | Red Pen | Hand gestures become edits: strike, scribble-delete, underline, circle → note, caret → insert | Plain Markdown (`~~`, `==`, `[^n]`, `<ins>`) |
| `canvas.html` | Spatial Canvas | Endless board with text cards and ink anywhere | JSON Canvas `.canvas` + one ink `.svg` |

Shared pieces: `ink.js` (stroke smoothing with simulated pressure, pointer capture, toolbar and keys, file view, contenteditable → Markdown) and `base.css` (dark look matching the app).

Keys in Glass Layer and Red Pen: ⌘D toggles draw/type, hold ⌥ to draw briefly, P/H/E pen/highlighter/eraser, 1–5 colors, T or Esc back to typing.

# Zoomies

_Take and copy paste screen in 2 seconds. Rename? 3 seconds. Rename + annotate with prompt for agent? 5 seconds. Quick edit? 7? maybe 10..._

> **Requires macOS 14 (Sonoma) or later.** If you have an older macOS version, it is probably best to use this as a product spec and build your own. I had enough headaches with older OS versions already.

Mac-only keyboard-first screenshot and scratchpad app for agentic coding.
Good for touchpad users too, especially if your wrist is already cooked from gaming.

Fork it, pork it, change it, rebuild it. Have fun.

## What It Does

- Captures the exact UI state you want a coding agent to understand.
- Adds quick notes/prompts to screenshots so the context travels with the image.
- Saves Zoomies edit data inside PNGs, so future reopens can edit/delete Zoomies-added arrows, text, pen strokes, shapes, pasted selections, and cut regions.
- Creates quick scratchpad notes for errors, issues, and ideas you spot in one project while your head is still in another.
- Lets you rename, annotate, save, copy, or delete without breaking coding flow.
- Reopens a selected Finder image and sends it back through the Zoomies flow.

## Quick Start

```bash
cd zoomies
swift build
swift run Zoomies
```

This repo is source-only. If you want a clickable `.app`, ask any coding agent to package the SwiftPM project into a macOS app bundle for you.

## Default Shortcuts

- `Option+Shift+4` -> area capture
- `Option+Shift+3` -> full-screen capture
- `Option+Shift+2` -> select an image in Finder, press this to edit/rename it with Zoomies
- `Option+Shift+5` -> create a scratchpad note

The defaults intentionally avoid the standard macOS `Cmd+Shift` screenshot shortcuts.

## Workflow Keybinds

| Screen | Key | Action |
| --- | --- | --- |
| Rename / Prompt | `Enter` | Save |
| Rename / Prompt | `Cmd+Enter` | Copy + save |
| Rename / Prompt | `Cmd+Backspace` | Copy + delete |
| Rename / Prompt | `Esc` | Delete / close |
| Flow | `Tab` | Next step |
| Flow | `Shift+Tab` | Previous step |
| Edit | `W` / `A` / `R` / `E` / `T` / `S` | Pen / arrow / rectangle / ellipse / text / select |
| Edit | `K` or `Q` | Open colors |
| Edit | `1-6` | Pick color |
| Edit | `Cmd+Z` | Undo |
| Edit | `Option+Backspace` | Clear |
| Edit | `Cmd+C` / `Cmd+X` / `Cmd+V` | Copy / cut / paste |
| Edit | `Cmd +` / `Cmd -` / `Cmd 0` | Zoom in / out / reset |
| Edit | `Enter` | Save |
| Edit | `Cmd+Enter` | Copy + save |
| Edit | `Esc` | Cancel |

## Editor Select Tool

Press `S` in the editor to use Select.

Select now has two jobs:

- Click a Zoomies-added object, like text, arrow, pen stroke, rectangle, ellipse, pasted image, or cut/erase region, to select it.
- Drag the selected object to move it, or press `Delete` to remove it.
- Drag on empty screenshot space to select a rectangular image region.
- With a region selected, use `Cmd+C` to copy it, `Cmd+X` to cut it, and `Cmd+V` to paste it back into the canvas.

Editable objects are remembered only for PNGs saved by this version of Zoomies or later. Older already-flattened screenshots still open as normal images because their arrows/text are already baked into the pixels.

## Permissions

The app uses `ScreenCaptureKit` (`SCScreenshotManager`) for all screen capture. macOS will prompt once for Screen Recording permission.

- **Screen Recording** (for screenshots via ScreenCaptureKit)
- **Automation / Finder** (for reopening flow on selected Finder image via `Option+Shift+2`)

## TODO

- Make a video demonstration?
- Make a screen demonstration?
- Add a donation option and create a `$1` validation flow?

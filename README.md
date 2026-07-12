# Zoomies

_Take and copy paste screen in 2 seconds. Rename? 3 seconds. Rename + annotate with prompt for agent? 5 seconds. Quick edit? 7? maybe 10..._

> **Requires macOS 14 (Sonoma) or later.** If you have an older macOS version, it is probably best to use this as a product spec and build your own. I had enough headaches with older OS versions already.
>
> Zoomies builds natively on both Apple silicon and Intel Macs. Intel is supported but untested because I do not have an Intel Mac.

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

When you edit and save a non-PNG image such as a JPEG or HEIC, Zoomies saves the
edited result as a PNG and removes the original non-PNG file.

## Quick Start

```bash
cd zoomies
swift build
swift run Zoomies
```

To build a clickable `.app`:

```bash
./scripts/build_app.sh
open dist/Zoomies.app
```

A coding agent can run that build script for you too.

### Building on an Intel Mac

Intel users should build Zoomies from source on their Intel Mac:

```bash
git clone https://github.com/bald-ai/zoomies.git
cd zoomies
./scripts/build_app.sh
open dist/Zoomies.app
```

Swift automatically builds for the Mac it is running on: Apple silicon produces
an `arm64` app, while Intel produces an `x86_64` app. A universal binary is only
needed when distributing one prebuilt `.app` for both architectures; this
repository distributes source instead.

Intel support requires an Intel Mac running macOS 14 or later with Xcode 15 or
later. **I do not own an Intel Mac, so the Intel build has not been personally
tested.**

## Default Shortcuts

- `Option+Shift+4` -> area capture
- `Option+Shift+3` -> full-screen capture
- `Option+Shift+2` -> select an image in Finder, press this to edit/rename it with Zoomies
- `Option+Shift+5` -> create a scratchpad note

The defaults intentionally avoid the standard macOS `Cmd+Shift` screenshot shortcuts.

You can change the main global shortcuts in Zoomies Settings. If you want to
change keybinds that are not exposed in the UI, ask your coding agent to update
the relevant shortcut code and build a new `.app` for you.

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
- Switching to another tool clears the rectangular area selection.

Select does not change the contents or shape of an existing annotation. To edit
existing text, press `T` for the Text tool and double-click the text. Arrows,
pen strokes, rectangles, and ellipses can be moved or deleted, but not reshaped.

Editable objects are remembered only for PNGs saved by this version of Zoomies or later. Older already-flattened screenshots still open as normal images because their arrows/text are already baked into the pixels.

## Temporary Clipboard Files

`Copy + Delete` needs a temporary file so macOS can still paste the screenshot
after Zoomies removes it from the Desktop. Zoomies stores that temporary copy in
`~/Library/Caches/zoomies/clipboard` and clears the folder the next time Zoomies
starts.

## Permissions

The app uses `ScreenCaptureKit` (`SCScreenshotManager`) for all screen capture. macOS will prompt once for Screen Recording permission.

- **Screen Recording** (for screenshots via ScreenCaptureKit)
- **Automation / Finder** (for reopening flow on selected Finder image via `Option+Shift+2`)

### Permission after rebuilding the app

If you edit the code and build a new copy of Zoomies, macOS may ask for
permission again even though Zoomies still appears to be allowed in System
Settings. The listed permission can belong to the previous app build.

Open **System Settings → Privacy & Security**, select the relevant permission,
use the **−** button to remove the old Zoomies entry, then use the **+** button
to add and allow the newly built `Zoomies.app`.

## TODO

- Make a video demonstration?
- Make a screen demonstration?
- Add a donation option and create a `$1` validation flow?

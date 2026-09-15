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
- `Option+Shift+1` -> create a scratchpad note
- `Option+Shift+5` -> start/stop screen recording (requires macOS 15)

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
| Edit | `W` / `D` / `A` / `R` / `E` / `T` / `F` / `S` | Pen / line / arrow / rectangle / ellipse / text / numbered marker / select |
| Edit | `Q` | Next color in your palette |
| Edit | `K` | Open colors |
| Edit | `1-6` | Pick color |
| Edit | `Cmd+Z` / `Cmd+Shift+Z` | Undo / redo |
| Edit | `Option+Backspace` | Clear |
| Edit | `Cmd+C` / `Cmd+X` / `Cmd+V` | Copy / cut / paste |
| Edit | `Cmd +` / `Cmd -` / `Cmd 0` | Zoom in / out / reset |
| Edit | `Enter` | Save |
| Edit | `Cmd+Enter` | Copy + save |
| Edit | `Esc` | Cancel |

### Editor shortcut hints

Hold **⌘ alone for 0.5 seconds** to reveal shortcut badges beside the editor’s toolbar controls. A hint above the toolbar invites you to hover over a badge or control to read its action and shortcut in plain text. Release ⌘ to hide them. Another key or modifier dismisses the badges and lets the shortcut work normally.

## Editor Numbered Markers

Press `F` in the editor to use the numbered marker tool.

New editor text and marker diameters grow with image width on a gentle curve: small captures stay readable, while full-screen captures avoid oversized annotations. Sizing is independent of window fit and zoom. Existing annotations retain their saved sizes.

- Click on the image to stamp a numbered circle labeled `1`, then `2`, `3`, and so on. The outline and numeral use the current annotation color and the interior stays transparent so the image shows through; the circle widens instead of clipping for multi-digit numbers.
- Drag an existing marker to move it or press `Delete` to remove it. Repeated clicks select the marker; number editing is currently disabled. Removing a marker never renumbers the others, and the next number continues past the highest existing marker.
- Reference the numbers in your note text — the note is saved below the image, so prompts like "fix 1 and 3" travel with the screenshot.

## Editor Select Tool

Press `S` in the editor to use Select.

Select now has two jobs:

- Click a Zoomies-added object, like text, numbered marker, arrow, pen stroke, rectangle, ellipse, pasted image, or cut/erase region, to select it.
- Drag the selected object to move it, or press `Delete` to remove it.
- Drag on empty screenshot space to select a rectangular image region.
- With a region selected, use `Cmd+C` to copy it, `Cmd+X` to cut it, and `Cmd+V` to paste it back into the canvas.
- Switching to another tool clears the rectangular area selection.

Select does not change the contents or shape of an existing annotation. To edit
existing text, press `T` for the Text tool and double-click the text. Arrows,
pen strokes, rectangles, and ellipses can be moved or deleted, but not reshaped.

Editable objects are remembered only for PNGs saved by this version of Zoomies or later. Older already-flattened screenshots still open as normal images because their arrows/text are already baked into the pixels.

## Screen Recording

`Option+Shift+5` or the menu-bar icon's Start Recording begins a display
recording. There is no display picker: recording starts on the display under
the pointer and follows the pointer to another monitor after it stays there
for half a second. It keeps recording across app and Space changes, includes
the cursor, excludes Zoomies' own windows, and stops automatically after 60
seconds.

Video is 30, 60, or 120 fps (selectable in Settings, default 30), SDR, H.264 MP4 without audio on a fixed 1920x1080 canvas
(the full display is fitted without cropping or stretching, with black
margins where needed). The menu bar shows only the elapsed seconds, from `0` to `60`, in red. The finished video is saved beside screenshots with a unique
`Recording_...` filename and revealed in Finder.

Only one Zoomies operation runs at a time: recording blocks
screenshots/notes/Finder-reopen, and those workflows block recording startup.
Screen recording requires macOS 15 or later; on macOS 14 the menu command
explains it is unavailable while screenshots and notes keep working.

## Temporary Clipboard Files

`Copy + Delete` needs a temporary file so macOS can still paste the screenshot
after Zoomies removes it from the Desktop. Zoomies stores that temporary copy in
`~/Library/Caches/zoomies/clipboard` and clears the folder the next time Zoomies
starts.

## Permissions

Area capture uses the built-in macOS screenshot selector. Full-screen capture uses `ScreenCaptureKit` (`SCScreenshotManager`). macOS will prompt for Screen Recording permission when needed.

For area capture, drag to select, press Space to switch to window/menu selection, or press Escape to cancel. The captured image then opens in the usual Zoomies workflow.

- **Screen Recording** (for screenshots via ScreenCaptureKit)
- **Automation / Finder** (for reopening flow on selected Finder image via `Option+Shift+2`)

### Permission after rebuilding the app

Ad-hoc signatures identify a particular build, so permission approvals may stop
matching after the app changes. For local development, reuse a code-signing
certificate and the same bundle ID and installed app path across rebuilds.

List available signing identities and save the chosen certificate's SHA-1 in
this checkout's local Git configuration:

```bash
security find-identity -v -p codesigning
git config --local zoomies.signingIdentity YOUR_CERTIFICATE_SHA1
./scripts/build_app.sh
```

The build script also accepts `--signing-identity` or `ZOOMIES_SIGNING_IDENTITY`;
the command-line option takes precedence, followed by the environment variable,
then Git configuration. A configured certificate that cannot sign causes the
build to fail instead of silently falling back to ad-hoc signing. Without a
configured identity, builds retain the ad-hoc default.

Switching from ad-hoc signing to a certificate may require one more approval.
If the old entry remains unusable, remove that Zoomies entry in **System Settings
→ Privacy & Security** and add the installed `/Applications/Zoomies.app` again.
Keep using that installed copy for testing. A local certificate is for development;
it does not make the app notarized for distribution.

## Editor colors

Press **Q** to cycle to the next color. In **Settings → Colors**, choose 1–6 active colors from 15 options and use the up/down arrows to set their order. The last color wraps back to the first. Changes also apply to an already-open editor. Press **K** or click the color swatch to open the visual picker.

Standalone Markdown notes accept up to 100,000 characters. Image notes keep their 1,000-character limit. Input that would exceed the limit is rejected with a visible limit message, so an oversized paste does not silently lose its ending.

After placing or selecting editor text, click outside it to return to the pen. Typed text is kept; empty text boxes are discarded. The dismissing click does not draw a stroke.

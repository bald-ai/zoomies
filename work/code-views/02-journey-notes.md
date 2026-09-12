# Journey concept notes (`02-journey.html`)

Concept id: `journey`  
Title: Follow one screenshot  
Owned files: `work/code-views/02-journey.html`, `work/code-views/02-journey-notes.md`

## What it shows

A seven-phase storyboard of one screenshot from shortcut → capture → Desktop PNG → rename → optional note → optional editor → final keep/copy/delete. Interactive Back/Next and per-phase buttons update the preview, owner/data chips, and plain-language detail. Optional note and editor phases are dashed and labeled so they are clearly forks, not a required tunnel.

## Interactions

- **Back / Next** and clicking a phase on the rail change the selected step.
- Arrow keys (←↑ / →↓) also step when focus is not in an editable field.
- Each step refreshes: SVG preview, caption, owner + data chips, detail copy, and optional-route callout.
- `parent.postMessage({ type: 'zoomies-concept-height', id: 'journey', height })` on load, ResizeObserver, and after step changes.

## Evidence used (manually traced)

| Phase | Plain job | Primary code | Data location |
| --- | --- | --- | --- |
| Press shortcut | Human starts | `AppDelegate` hotkey handlers → `ScreenshotService` | None yet |
| Grab picture | Capture | `ScreenshotService.captureArea` / `captureFullScreen`; area via `NativeAreaCapture` | In-memory `NSImage` / `CGImage` |
| Park PNG | Draft save | `finishCapture` → `prepareCaptureSave` + background write to Desktop; `beginPostCaptureFlow` | Memory + Desktop URL |
| Name it | Rename / finish | `ScreenshotWorkflowController.presentRenamePanel`; Enter can complete without note/editor | File path (rename may move) |
| Add a note? | Optional | Tab → `presentNotePanel`; not on default path | Pending note text in workflow |
| Draw on it? | Optional | Tab from note → `openEditor` / `EditorWindowController` | Edited composite in memory |
| Keep / copy / discard | Persist + handoff | `WorkflowImagePersistenceLogic` write; `ClipboardService` only on copy actions; Copy+Delete uses `~/Library/Caches/zoomies/clipboard` | Disk ± pasteboard |

Counts for listed files match `work/code-views/facts.json` (2026-09-12). Additional supporting files named in Evidence: `RenamePanelController.swift`, `NotePanelController.swift`, `NativeAreaCapture.swift`.

## Limitations (for parent / chooser)

- Manually illustrated from reading code—not a live instrumented trace.
- Does not show Finder-reopen (`Option+Shift+2`) or scratchpad/recording paths; journey is capture → save of a new screenshot.
- Does not claim frequency, timing, or quality of any phase.
- Does not claim every image visits note or editor (those are marked optional).

## Parent checks

- Iframe `id` / postMessage id must be `journey`.
- File is self-contained (inline CSS/JS only); no external fonts or fetches.
- Target ~900px wide; stacks preview above rail under ~640px; no `100vh` outer height.
- Optional phases use dashed markers and purple callouts; finish phase mentions clipboard only when copying.

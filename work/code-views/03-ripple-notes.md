# Ripple concept notes

**Owned files:** `work/code-views/03-ripple.html`, `work/code-views/03-ripple-notes.md`  
**Concept id:** `ripple`  
**Title:** What would a change touch?

## Intent

Compact change-impact map: pick one of three concrete changes, see three bands of consolidated jobs (Directly involved / Check together / Likely unrelated), select one job via native buttons, read a single detail panel. Manually traced places to inspect — not a predictive analyzer. No risk scores or invented totals.

## UX (revised after parent ~900px review)

- **Not** a tall stack of every job card. Only the selected job’s detail is shown.
- Default selection: first Directly involved job for the active scenario.
- Dominant visual: three horizontal band lanes with readable 13px+ job buttons (no dense 12-node SVG network).
- 5 consolidated jobs per scenario (was 12 tiny nodes).
- Swift paths and terms (iTXt, PNG helpers, file names) live only under collapsed Evidence.
- One scope line: “Places to inspect, traced from the code.”
- Desktop target: keep document height under ~850px with Evidence closed.

## Interactions

1. Three scenario choice buttons.
2. Job buttons inside band lanes (`aria-pressed`); keyboard/focus/touch via native `<button>`.
3. One detail aside updates name, band tag, evidence kind, plain-English why.
4. Evidence `<details>` holds source paths and technical notes for the active scenario.
5. Height `postMessage` still present (`id: "ripple"`); parent may replace shared height mechanics later.

## Plain-language job groups (preserve relationships)

### Saved picture format & hidden data
| Band | Job | Maps to |
| --- | --- | --- |
| Direct | Save the picture | `WorkflowImagePersistenceLogic` PNG write + embed call |
| Direct | Hidden editing data | `PNGMetadata` + `EditorCanvasState` |
| Direct | Bring edits back | `WorkflowReopenMetadataLogic` |
| Check | Other PNG paths | `ScreenshotServiceCoreLogic`, `ClipboardService`, `ImageSafety`, `FilenameTemplateEditorView`, workflow caller |
| Far | Shortcuts & other flows | `HotKeyService`, `ScreenRecordingService`, `ScratchpadService` |

### Add a drawing tool
| Band | Job | Maps to |
| --- | --- | --- |
| Direct | Drawing on the canvas | `EditorTool` + draw/commit in `EditorCanvasView` |
| Direct | Toolbar & letter keys | `EditorWindowController` buttons + `toolKeyCodeToTool` |
| Direct | Remembered mark shapes | `EditorCanvasState.Item` (line reuses pen) |
| Check | Save & reopen edits | PNG editor-state embed, persistence, workflow, reopen, README keybinds |
| Far | Global shortcuts & settings | `HotKeyService`, Settings shortcut UI, scratchpad |

### Screenshot shortcut
| Band | Job | Maps to |
| --- | --- | --- |
| Direct | Default chords | `Shortcuts.default` area/full |
| Direct | Register hotkeys | `HotKeyService` screenshotArea/Full |
| Direct | Settings shortcut fields | Settings recorders + `ShortcutRecorderView` |
| Check | Startup wiring & capture | `AppDelegate`, store, duplicates, alerts, `ScreenshotService` |
| Far | Drawing tools & picture data | Editor letters, `PNGMetadata`, tray menu |

## Limitations

- Hand-traced call sites, not a graph tool.
- “Likely unrelated” ≠ no indirect effect.
- One Swift target; job names are inferred roles.
- README cited only in Evidence for tool keybind docs.

## Parent checks

- Iframe concept id: `ripple`.
- Self-contained; no external assets.
- ~900px wide; stacks on narrow widths; no fixed outer height / no `vh`.
- Confirm closed-Evidence height stays near the ~850px desktop target in the comparison iframe.

# Iceberg concept notes (`04-iceberg.html`)

Concept id: `iceberg`. Title: What is hidden beneath the surface?

## Owned files

- `work/code-views/04-iceberg.html`
- `work/code-views/04-iceberg-notes.md`

## Idea

Cutaway iceberg for a noncoder: **above** = “What the rest of the app asks for”; **below** = “The work handled inside.” One geometry note + “Does not tell you” — no repeated depth/quality disclaimers in example copy. Visible language is everyday jobs; filenames and format/storage terms stay in collapsed Evidence.

## Examples (3 selectable)

| Visible name | Subtitle (human) | Source piece |
| --- | --- | --- |
| Preferences keeper | Remembers your choices between launches | `SettingsStore` |
| Secrets in a screenshot | Keeps the clean original and your note inside the picture | `PNGMetadata` |
| After a screenshot | Guides rename, note, edit, then save or delete | `ScreenshotWorkflowController` |

`EditorCanvasView` not used (still noted in Evidence as optional wider tip).

## Copy / accuracy notes

- Settings underwater chips use the requested human tasks (find saved prefs, older version, defaults if unreadable, repair invalid choices, save complete file in one step).
- PNG underwater chips are human translations of packing/clearing/traveling drawings/safety/valid file — no iTXt/CRC/JSON in visible UI.
- Workflow: **`cancel()` does not restore backups.** Verified in `ScreenshotWorkflowController.cancel()` (closes panels/editor, clears pending state only). Restore is `restoreOriginalFromBackupIfAvailable()` on close-after-edit paths (e.g. `closeWorkflowWithoutDeleting`, editor `closeOnly`). Visible tip says “Stop early and close open panels”; leak copy and Evidence state the cancel vs restore distinction.
- Agent questions are high-level architecture asks a noncoder could pose (e.g. settings location blast radius).
- Per-example Swift filename disclosure removed from the detail panel; Evidence holds paths, APIs, callers, persistence.

## Interactions

- Three buttons toggle examples (chips + detail: why / what other parts still notice / ask an agent).
- SVG is static; live content is chip bands + aside.
- Height `postMessage` with `id: 'iceberg'` still present (parent may replace shared height mechanics later).
- Helps you see / Does not tell you; Evidence `<details>`.

## Evidence (preserved)

- SettingsStore 127 / PNGMetadata 337 / ScreenshotWorkflowController 1038 lines (`facts.json` 2026-09-12).
- Call sites and private responsibilities unchanged from prior verification; cancel/restore clarification added.

## Parent checks

1. Visible UI has no Swift class names in the selector; technical terms only under Evidence.
2. Workflow never implies cancel universally restores.
3. One geometry note; depth/quality caveats only in that note + Does not tell you.
4. Click all three examples; narrow width stacks without overflow.
5. Do not rely on this iframe’s height postMessage if parent has replaced shared sizing.

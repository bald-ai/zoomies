# Rooms concept notes

Concept id: `rooms`  
Owned files: `work/code-views/01-rooms.html`, `work/code-views/01-rooms-notes.md`

## What it shows

A calm 2D floorplan of seven functional rooms for Zoomies. Room sizes are equal-ish for readability and labelled as a **conceptual layout** (area does not encode lines). Line counts and shares appear on each room and in the detail panel. A dashed shared spine with doors marks schematic collaboration, not measured call edges.

Default selection: **Editing**.

## Grouping method

Every `Sources/*.swift` file from `work/code-views/facts.json` (snapshot 2026-09-12) is assigned to exactly one inferred role. Totals verified: 44 files, 11,278 lines.

| Room | Files | Lines | Share |
| --- | ---: | ---: | ---: |
| Capture | 6 | 1,280 | 11.3% |
| Editing | 6 | 3,881 | 34.4% |
| Workflow | 8 | 1,557 | 13.8% |
| Notes | 4 | 628 | 5.6% |
| Recording | 2 | 930 | 8.2% |
| Preferences | 6 | 2,028 | 18.0% |
| Shared helpers | 12 | 974 | 8.6% |

Judgment calls (parent may want to revisit):

- `FinderSelectionService` → Capture (entry for “edit Finder selection”).
- `PNGMetadata` / `ImageSafety` → Editing (edit-state embedding and image limits).
- `WorkflowNoteRenderer` → Notes (note burn-in), not Workflow.
- `VideoRenameWorkflowController` → Recording (post-record rename).
- `HotKeyService` → Preferences (shortcut registration next to settings).
- `AppDelegate` / tray / clipboard / backup → Shared helpers.

## Interactions

- Click or Enter/Space on a room updates the detail panel (job, receives, provides, counts, concentration note, file list).
- File list lives in a `<details>` disclosure.
- Height posts to parent: `{type:'zoomies-concept-height', id:'rooms', height}` on load, ResizeObserver, and selection change.

## Limitations

- Roles are inferred, not package boundaries.
- Spine/doors are illustrated collaboration cues only.
- Large editing share is explained with largest-file facts; no quality verdict.
- Does not show runtime dependencies, churn heat, or tests.

## Parent checks

- Iframe `id` must be `rooms` for height messages.
- Confirm no external assets (standalone inline CSS/JS).
- Confirm default room is Editing on load.
- Optionally re-check grouping judgment calls above if another concept uses different buckets.

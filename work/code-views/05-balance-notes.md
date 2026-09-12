# Balance — Where is the work concentrated?

Concept id: `balance`  
Owned files: `work/code-views/05-balance.html`, `work/code-views/05-balance-notes.md`

## Evidence used

- `work/code-views/facts.json` (snapshot 2026-09-12): 44 `Sources/*.swift` files, 11,278 total lines, 19 commits.
- Verified: summed lines = 11,278; `git rev-list --count HEAD -- Sources` = 19.
- Top eight by line count with human roles; remaining 36 as one row. Shares of 11,278 sum to 100.0% at 0.1% rounding.

| Role | Path | Lines | Share | Commits |
| --- | --- | ---: | ---: | ---: |
| Drawing tools | `Sources/EditorCanvasView.swift` | 1,916 | 17.0% | 6 |
| Editor window | `Sources/EditorWindowController.swift` | 1,046 | 9.3% | 8 |
| After-capture flow | `Sources/ScreenshotWorkflowController.swift` | 1,038 | 9.2% | 6 |
| Screen recording | `Sources/ScreenRecordingService.swift` | 682 | 6.0% | 2 |
| Settings window | `Sources/SettingsWindowController.swift` | 512 | 4.5% | 5 |
| Taking screenshots | `Sources/ScreenshotService.swift` | 494 | 4.4% | 3 |
| Preferences data | `Sources/Settings.swift` | 483 | 4.3% | 8 |
| Filename patterns | `Sources/FilenameTemplateEditorView.swift` | 390 | 3.5% | 4 |
| Other 36 files | remaining | 4,717 | 41.8% | not summed |

- `NativeAreaCapture.swift` has 0 commits in history available.

## Interaction (revised)

- Book-like ledger: 9 rows (8 named + Other 36 files).
- Columns: **Share of all code** (mini bar on quiet 100% track + exact %) and **Saved changes** (mini bar scaled to 19 history commits + “N of 19”).
- Other row edit cell: dashed placeholder + plain “not one total” — commit counts are not summed.
- Row label buttons select; one detail panel; default selection = Drawing tools.
- Compare-shape mode removed.
- Paths and method live under Evidence. Footnote: saved change = commit.
- CSS: `min-width: 0` on wrap/panel/grid children; no ellipsis on labels; mobile stacks label above the two metrics; no internal scroll.

## Limitations

- Not health, complexity, or bug scores.
- 19 saved changes = history available, not long-term trend.
- Roles are plain-language labels from current code.

## Parent checks

- iframe → `05-balance.html`; height message `id: 'balance'`.
- Standalone, no external assets.
- Compact desktop height target ~850px with Evidence collapsed.

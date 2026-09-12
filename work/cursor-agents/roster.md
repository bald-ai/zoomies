# Visual concept workers

Five external Cursor workers, configured cursor-grok-4.5-high-fast; cap 16. Current checkout, no branches/worktrees.

- rooms: The app as a set of rooms; owns work/code-views/01-rooms.html and notes; job work/cursor-agents/visual-options/rooms-job; state completed, zero tool failures; integrated and verified.
- journey: Follow one screenshot; owns work/code-views/02-journey.html and notes; job work/cursor-agents/visual-options/journey-job; state completed, zero tool failures; integrated and verified.
- ripple: What would a change touch?; owns work/code-views/03-ripple.html and notes; job work/cursor-agents/visual-options/ripple-job; state completed, zero tool failures; integrated and verified.
- iceberg: What is hidden beneath the surface?; owns work/code-views/04-iceberg.html and notes; job work/cursor-agents/visual-options/iceberg-job; state completed, zero tool failures; integrated and verified.
- balance: Where is the work concentrated?; owns work/code-views/05-balance.html and notes; job work/cursor-agents/visual-options/balance-job; state completed, zero tool failures; integrated and verified.

- review: independent factual audit; job visual-options/review-job; completed. Four factual/clarity findings corrected against sources. Initial missing-file read was followed by successful reads of the brief and all relevant sources.
- ripple, iceberg, balance: related refinement jobs completed with no tool failures. Parent simplified visible language, corrected claims, fixed content height reporting and keyboard modifier handling.
- Final artifact: work/zoomies-code-views.html (single self-contained HTML). Browser verified interactions, all five individual views at 340px with no horizontal overflow, desktop screenshots reviewed.

Depth review: boundaries-job (editor/workflow) and services-job (storage/capture helpers), read-only Cursor workers; parent verifies claims.
Depth review complete: both workers returned valid handoffs with no tool failures. Parent verified storage APIs/callers, workflow start surface, duplicate action enums/mapping, workflow constructing canvas. No source changes or test execution.

Rooms update: parent owns work/zoomies-code-views.html; rooms-update/review-job read-only edge verification, running.
Rooms update complete: review handoff verified. Parent replaced final page with room-only map; retained detailed source evidence on selection. Browser interaction and responsive checks passed.

Ship readiness: files-job reviews screenshot data integrity; recording-release-job reviews recording and packaging. Both read-only; parent owns builds/tests and validation.

Refactor spec: render-review-job read-only extraction design review. Parent owns Dev/editor-workflow-refactor-spec.md and removes generated HTML. No app implementation or tests this turn.
Refactor spec complete: render-review-job returned valid handoff, no tool failures. Parent verified source contracts and incorporated coordinate, native-resolution, text, erase, state/encoding separation constraints. Deleted only code-map HTML and its regeneration scripts; preserved unrelated welcome HTML. No source implementation or tests this turn.

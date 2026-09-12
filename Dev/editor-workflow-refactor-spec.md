# Focused editor and workflow refactor

Status: specification only; implementation has not started. 12 September 2026.

## Outcome

Keep Zoomies behaving exactly as it does now while giving three responsibilities clear owners:

1. One definition of the final screenshot actions.
2. One home for generic image-to-bitmap/PNG conversion.
3. One owner of committed annotation drawing and image compositing, callable without constructing an editor view.

This is a maintenance refactor for the existing small app. It is not a new architecture. The result should make a change easier to locate and reduce the number of places that must agree with one another. File length and number of classes are not success criteria.

## Scope and working rules

Use the existing project directory, current checkout and current branch. Preserve all existing user edits, including ongoing native screenshot and recording work. Do not create a branch/worktree or commit unless separately requested.

Implement each stage below as a separately reviewable change. Do not combine behavioral fixes, formatting sweeps, dependency upgrades or unrelated cleanup with it. The implementation request must be separate from this specification; this document does not claim the refactor has been performed or validated.

Explicitly outside scope:

- Capture implementation, recording, window focus, welcome messages, settings UI and shortcut configuration.
- Reorganizing the entire workflow, creating a new state machine, changing concurrency or persistence order.
- Replacing AppKit, introducing packages/frameworks, generic service layers or a protocol per class.
- Splitting the canvas merely to shorten it, moving its undo history into a new architecture, or redesigning keyboard dispatch.
- Changing saved PNG metadata, file naming, image safety limits, error messages or failure recovery.

## Current evidence

| Responsibility | Current implementation | Specific issue |
| --- | --- | --- |
| Final actions | `ScreenshotWorkflowController.FinalAction`; `EditorCanvasView.FinalActionCommand`; translation in `EditorWindowController.handleKeyCommand` | The same five choices have two definitions. The editor also refers back to the workflow's nested type. |
| Image conversion | `ScreenshotServiceCoreLogic.pngData` and `.bitmapRepresentation` | Editing, workflow saving and reopening call functions named as capture internals. |
| Compositing | `EditorCanvasView.renderCompositeImage`, its item drawing and bounds functions | The workflow constructs `EditorCanvasView` in `annotatedBaseImage` to save a reopened annotated image with a note. |
| Restoring edits | `EditorWindowController.init`, `EditorCanvasView.init`, state conversion and `WorkflowReopenMetadataLogic` | Clean base selection and coordinate restoration must remain consistent; a pending composite can already contain the annotations. |

Starting references: `Sources/ScreenshotWorkflowController.swift` around 14, 332, 839; `Sources/EditorWindowController.swift` around 36, 141, 700; `Sources/EditorCanvasView.swift` around 28, 144, 295, 386, 801, 837, 1834; `Sources/ScreenshotServiceCoreLogic.swift` around 32. Line numbers are navigation aids; locate the symbols in the implementation checkout.

## Behavior contract

These are constraints, not opportunities to improve current behavior in passing.

### Image appearance and editing

- Preserve native image pixel dimensions and logical point size. Use the base image's pixel-to-point ratio, not the current monitor's scale. Preserve output orientation, transparency, interpolation and color handling.
- Preserve item order, pen smoothing, line joins/caps/widths, arrow geometry, text font/measurement/padding, pasted-image drawing and the `destinationOut` erase operation.
- Export the union of the base picture and committed annotation bounds, with the current normalization and rounding. Annotations outside the original picture must not be cropped away.
- Region copying must use the current selection intersection and rounding rules. Selection outlines, edge shadows, cursor/drag previews and toolbar state must not enter the exported image.
- Preserve text commitment before `compositeImage()` and `editableState()`. Do not make the renderer end a text-editing session. Preserve existing differences between full export and selected-region rendering rather than silently changing them.
- Preserve undo/redo, redo invalidation, selection, movement, live previews, keyboard behavior, zoom and canvas recentering.

### Saved edits and reopening

- Preserve `EditorCanvasState`'s JSON fields, item kinds, metadata keys/versions, optional `baseImageOrigin`, safety limits and behavior when an embedded image cannot be decoded.
- Restore the clean base from valid saved state when current code does so. Never draw annotations over a pending image that already contains them. Reopening and repeated note changes must not double-burn annotations or notes.
- Preserve legacy state without `baseImageOrigin` and the current 24-point initial canvas inset. Any coordinate normalization must translate the base and every item consistently; it must not change visible placement or export extent.
- A note-only save of an annotated reopened PNG must preserve both visible annotation pixels and the saved editing information/prompt according to current behavior.
- Preserve the existing fallback to a flattened image for unsafe/unusable metadata. Do not alter PNG embedding policy or the size threshold in `WorkflowImagePersistenceLogic`.

### Final actions and files

- Keep exactly `saveOnly`, `copyAndSave`, `copyAndDelete`, `deleteOnly`, `closeOnly`, with their current meanings.
- Keep context-dependent Escape, toolbar cancellation and red-window-close behavior: fresh captures and Finder-selected originals have different ownership/deletion rules. Keep existing confirmation and cancellation behavior, including not rendering discarded edits.
- Keep file writes, clipboard publication, backup creation/restoration/removal and workflow completion in their current order. Preserve waiting for initial capture persistence, retries and duplicate-action protection.
- Preserve the current unchanged-image save path, collision/case-only rename rules and edited non-PNG conversion behavior. This refactor must not introduce new writes or deletions.
- Preserve current failure behavior, including allocation/encoding fallbacks. If a fallback appears defective, record it separately; do not silently change it during extraction.

## Stage 0 — Establish the implementation baseline

Before editing, inspect `git status` and the current diff. Record which changes predate this work. Read the relevant existing regression cases listed below and establish their baseline results in the current checkout. Existing failures must be reported and kept distinguishable from regressions.

For rendering, capture reference output from the current implementation before replacing it. Use deterministic fixtures and decoded pixel data on the same machine/OS. A comparison of two callers that already use the new renderer is not independent evidence of preserved output.

Do not run the real capture/recording services for automated fixture checks. Use temporary files and isolated/injected clipboard writers. Protect the user's live images, settings and clipboard.

## Stage 1 — One final-action definition

Add `Sources/ScreenshotFinalAction.swift` with one internal enum containing the existing five cases and no new behavior.

Update the workflow's action arguments, editor completion callback, canvas final-action command payload and Escape action storage to use it. Replace the identity-mapping switch in `EditorWindowController.handleKeyCommand` with direct forwarding. Preserve the surrounding keyboard routing and confirmation logic.

The enum belongs to neither the workflow controller nor the canvas. Do not expand it with unrelated tools, zoom or color-picker commands. Temporary aliases may make an intermediate patch compile, but the finished change must not retain duplicate enums or a dependency on the workflow's nested type. Update affected type references in existing tests mechanically; preserve their behavioral assertions.

Acceptance: one five-case definition; no action-to-identical-action translation; all existing action paths retain their behavior. Review every occurrence of `FinalActionCommand`, `ScreenshotWorkflowController.FinalAction` and the final-action cases rather than relying only on inference by the compiler.

## Stage 2 — Give image conversion its own home

Add `Sources/ImageEncoding.swift` with the existing `pngData(from:)` and `bitmapRepresentation(from:)` operations. Move the implementations without changing their algorithms, signatures, optional results, bitmap selection, logical sizing or context management.

Update all production callers and affected tests, including calls inside native-capture tests. Remove the old definitions when migration is complete; do not leave a forwarding layer solely for compatibility inside this app.

Keep capture rectangle math, capture error policy, screenshot naming and `resizedImageIfNeeded` in their current location. Keep metadata packing in `PNGMetadata` and save policy in `WorkflowImagePersistenceLogic`. The encoder must not acquire disk writes, workflow state or screen-capture imports.

Acceptance: generic conversion callers use `ImageEncoding`; no remaining calls to `ScreenshotServiceCoreLogic.pngData` or `.bitmapRepresentation`; output and failure behavior match the baseline.

## Stage 3 — Extract drawing without redesigning interaction

This is the sensitive stage. Move the existing algorithms; do not invent a new rendering engine.

### Ownership and minimal API

Use `Sources/EditorImageRenderer.swift` as the home for committed annotation primitives, their visual bounds and offscreen compositing. AppKit graphics are allowed. The renderer must not create an `NSView`, `NSWindow`, text editor, event monitor or tracking area, and must not own mutable session state, file I/O or clipboard actions.

Use a lightweight internal drawing value containing the base `NSImage`, its canvas origin and the ordered runtime items. Move the existing runtime `Item`/`TextItem` representation as needed into this file (for example, nested under `EditorDrawing`), preserving payloads and semantics. Keep undo stacks and mutations in `EditorCanvasView`.

The intended interface has three jobs:

- Composite a drawing, optionally cropped to an explicit canvas rectangle.
- Draw a committed item using the current graphics context.
- Determine an item's visual bounds using the same geometry as rendering.

A small restore operation converts a validated `EditorCanvasState` into the runtime drawing. It must preserve current clean-base, origin and per-item decoding behavior. The exact Swift spelling may follow repository conventions; these ownership constraints are mandatory.

Do not use `editableState()` as the canvas's rendering input: that would serialize images/colors merely to draw, can discard unencodable items, and would couple normal rendering to persistence limits. Do not introduce a second differently modeled annotation system. State encoding remains a persistence boundary; the current runtime-to-state mapping must keep its format and failure behavior. Decode persisted pasted images once when restoring a drawing, not on every paint or bounds calculation. Do not apply persistence-only safety limits to ordinary live items as a new rendering restriction.

### Migration order within this stage

1. Move the runtime item types and shared drawing/bounds primitives, retaining existing behavior and constants. Have the canvas use them for committed items. Preserve transient preview alpha and selection behavior; reuse the same primitive geometry where the current preview and committed paths share it.
2. Move offscreen compositing and its export-bounds/pixel-scale calculations. Keep `compositeImage()` as a thin canvas entry point that commits text, captures current drawing data and invokes the renderer. Route selected-region rendering through the same compositor, retaining its existing crop calculation.
3. Share saved-state restoration where needed so the view and workflow agree about the clean base, origin offsets and decoded items. Preserve the fallback decisions at existing call sites. Avoid generalizing all editor initialization into a new service.
4. Replace only the direct canvas construction in `ScreenshotWorkflowController.annotatedBaseImage` with drawing restoration and compositing. Its no-state, unsafe-state and empty-items paths must still return the supplied base unchanged. Preserve the existing fallback base if decoding the saved base fails.
5. Delete the superseded compositing/primitive implementations once all callers have migrated. Keep interactive hit-testing policy, canvas sizing, event processing, undo and window coordination where they are.

Bounds used for export and interactive positioning must share the same visual geometry. Do not fork text measurement or arrow bounds. Keep the existing arrow length/angle and text padding/font measurements in one shared location when their drawing code moves; live text-editor sizing and hit-testing must continue to agree with rendering. Preserve floor/ceil crop normalization and the existing single-point/short-arrow rules. The renderer's temporary graphics-context changes must be restored on every exit, and the refactor must retain current threading behavior.

Acceptance: saving a reopened annotated image constructs no editor view; canvas and workflow share the committed renderer; live canvas export does not encode/decode PNGs to obtain its input; there are no duplicate committed drawing algorithms left behind.

## Proportionate regression checks during implementation

These checks protect this particular extraction. They are not a proposal for a new testing framework or a general release audit. Extend existing coverage only for gaps in the changed behavior.

| Change/risk | Evidence required |
| --- | --- |
| Enum consolidation | Existing keyboard/final-action/close cases retain all five actions, context-dependent cancellation and one-confirmation behavior. |
| Bitmap conversion | Existing conversion cases preserve native pixels, logical dimensions, fallback representation selection and nil behavior. |
| Renderer extraction | Compare old and new decoded output for an asymmetric base, all annotation kinds, translucent overlap, erase and pasted imagery. Include annotations outside the base and a selected-region crop. |
| Display scaling | Same base image rendered at 1x/2x logical-to-pixel ratios retains dimensions and orientation; output does not inherit the host screen scale. |
| Text and movement | Existing text commit/color and recentering checks remain valid; include multiline text and saved base-origin offsets. |
| Reopening | Existing no-double-compositing, note-only annotation/prompt preservation, repeated resave, legacy origin and unsafe-state fallback behavior remain valid. |
| File actions | Retain existing delayed-write, retry, duplicate action, clipboard failure, delete failure and non-PNG cases without weakening assertions. |

Use exact decoded pixel comparisons for deterministic geometric fixtures. If text rasterization requires tolerance, document the measured reason and a narrow tolerance; do not accept changed dimensions, missing objects or broad visual differences. Keep durable fixtures small and avoid screen-dependent snapshots.

Relevant existing suites: `EditorCanvasViewTests`, `EditorWindowControllerTests`, `ScreenshotWorkflowControllerTests`, `ScreenshotServiceCoreLogicTests`, `WorkflowImagePersistenceLogicTests`, `PNGMetadataTests`, and `KeyCommandInterpreterTests`.

Particularly relevant cases include `testCompositeImagePreservesNativeResolution`, `testCompositeImagePreservesOrientation`, `testEditableStateKeepsAnnotationsAnchoredToBaseImageAfterRecentering`, `testEditableStateUsesCleanBaseInsteadOfPendingComposite`, `testRedCloseDoesNotCompositeDiscardedEdits`, `testNoteOnlySaveOnReopenedAnnotatedFileKeepsAnnotationPixels`, and `testNoteOnlySaveOnReopenedAnnotatedFileKeepsPrompt`.

Run the affected suites after each stage. At the end, run the full existing suite and a release build once. Before declaring the refactor complete, use disposable images for one short editor exercise: draw/text/erase/paste, undo/redo, copy a region, save/reopen/change the note, and cancel a fresh versus reopened image. Report any unperformed check explicitly; do not turn missing evidence into a claim of completion.

## Stop conditions and completion

Stop the affected stage if output changes, metadata changes, existing interaction behavior changes, or matching behavior requires touching capture/recording/persistence policy. Diagnose the cause before proceeding. Keep a pre-stage diff so only the refactor's changes can be reverted; never reset the entire checkout or discard user changes.

The implementation is complete when:

- The three ownership changes are present and their old duplication is removed.
- The behavior contract is preserved with the targeted evidence above.
- There are no new dependencies, formats, architecture layers or unrelated UI changes.
- The final diff explains moved code separately from any necessary adaptations.
- The handoff lists changed files, completed checks, remaining uncertainty and any separately discovered bugs. It must not describe speculative cleanliness as proof of correctness.

If the renderer extraction proves substantially broader than described, retain the independently completed action/encoding improvements and report the renderer stage as incomplete. Do not replace it with a wrapper that secretly constructs `EditorCanvasView` and claim the boundary has been fixed.

# Pre-release TODO

## 1 — Welcome popup (PARKED, decided: A)
Every launch shows a blocking rude popup ("READ THIS YOU DUMFUS...").

Decision: Show it only once, with polite wording. Info stays in Settings/Help.

Status: TODO

## 2 — Investigate dropdown dismissal immediately after a screenshot

Status: Partially fixed; remaining behavior needs investigation.

Fixed: Area capture now uses the native macOS screenshot selector. Open dropdowns are included in the captured image successfully.

Remaining issue: The original dropdown (for example, “Manage Prompts…” in a menu bar app) disappears from the live screen immediately after capture. The user reports that it stays open when using the native macOS screenshot shortcut. The sudden dismissal makes it look as though the capture failed, even though the saved image contains the menu.

Suspected cause, not yet verified: Zoomies immediately opens its save/edit panel after capture. `RenamePanelController.show()` calls `window.makeKey()` and focuses the filename field. This focus change may dismiss the other app’s dropdown.

Investigation:
- Compare the native screenshot shortcut with Zoomies while the same dropdown is open.
- Confirm whether dismissal happens before or when the save/edit panel takes focus.
- Try showing the save/edit panel without keyboard focus until the user clicks it, and check whether the dropdown stays open.
- Evaluate the usability tradeoff: requiring a click before typing a filename or using panel keyboard shortcuts.

Keep the working native area capture behavior. No change to panel focus has been implemented yet.

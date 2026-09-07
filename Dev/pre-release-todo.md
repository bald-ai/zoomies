# Pre-release TODO

## 1 — Welcome popup (PARKED, decided: A)
Every launch shows a blocking rude popup ("READ THIS YOU DUMFUS...").

Decision: Show it only once, with polite wording. Info stays in Settings/Help.

Status: TODO

## 2 — Investigate dropdown disappearing during screenshot capture
Open dropdowns can disappear when starting an area screenshot in Zoomies, while the native macOS screenshot tool captures them successfully.

Potential cause: The selection overlay requests keyboard focus and receives mouse clicks before the screen is captured, which may dismiss the dropdown. Verify whether dismissal occurs when the overlay opens or when selection starts.

Potential approach: Capture the screen before showing the overlay, let the user select an area on the frozen image, then crop it.

Status: Potential investigation

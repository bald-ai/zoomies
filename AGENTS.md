# Zoomies – agent notes

## Build & verify
- Build: `swift build`
- Tests: `swift test` (XCTest, ~6 s in debug)
- Release-mode tests/benchmarks: `swift test -c release -Xswiftc -enable-testing --filter <Suite>`
- App bundle: `./scripts/build_app.sh` → `dist/Zoomies.app`, signed with `git config zoomies.signingIdentity`.
  Installed copy lives at `/Applications/Zoomies.app`; keep the same signing identity so
  Screen Recording / Automation permissions survive replacement.

## Testing notes
- `EditorCanvasPartialRedrawTests` checks partial-redraw correctness: coverage with
  antialiasing on, exact repaint with antialiasing off (CoreGraphics antialiases
  clipped paths slightly differently, so AA-on repaint cannot be byte-exact).
- `TestSupport.solidImage` renders via `lockFocus` at 2x; use `noiseImagePNGData` when exact
  pixel dimensions matter.
- The terminal has no Screen Recording permission, so `screencapture` cannot run here.

## Verification preferences

- For new features and behavior changes, add or update meaningful tests using the project's existing test framework, fixtures, helpers, and conventions. Inspect nearby tests first. Bug fixes should include a regression test where practical. Do not weaken assertions or disable tests merely to make a run pass.
- After the final code change, run the full ordinary automated test suite before handoff. Project commands: `swift test`. Fix failures caused by the change and rerun after fixes. Clearly report unrelated failures, unavailable toolchains, blockers, and skipped checks; do not claim the suite passed when it did not. Existing lint, typecheck, and build requirements still apply.
- Intermediate focused test runs are optional when useful for implementation or debugging. There is no requirement to run tests after every edit.
- Coverage, code metrics (including complexity and CRAP), and mutation testing are manual-only. Run them only when the user explicitly requests the corresponding check. Never include them in routine coding checks, pre-handoff checks, or automatic CI, including for critical behavior changes. A combined quality command that collects metrics or runs mutations is also manual-only; use the ordinary test commands instead.
- When the user explicitly asks for a cleanup pass (tests, coverage, and CRAP refactoring for code they want to keep), follow `quality/CLEANUP.md`. Never start one on your own.
- Do not generate or retain verification report files, evidence bundles, saved test logs, or source snapshots. Print verification results to the terminal. Disable optional file reporters; if tooling requires temporary internal data, use temporary storage and clean up data created by that run after success or failure. This is not permission to delete unrelated existing files or user-requested deliverables.
- Documentation-only changes do not require app tests unless they affect build/test instructions or an existing project rule explicitly requires documentation consistency tests.
- Ordinary local tests do not authorize device interaction, deployment, paid service calls, or live model benchmarks. Keep those within the user's explicit scope and report excluded checks.

- When changing verification tooling, also run its ordinary regression tests: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p test_verification_session.py`. These tests simulate subprocess outcomes and do not run coverage, code metrics, or mutations.

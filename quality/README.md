# Verification

Before handing off code changes, run the ordinary test suites listed in `AGENTS.md`, fix failures caused by the changes, and report unrelated failures or unavailable checks. Add tests for new behavior using existing project patterns. Intermediate focused tests are optional.

Coverage, complexity/CRAP metrics, and mutations are explicit-request-only. They are never automatic handoff checks. Existing CI uses ordinary tests/build checks; projects without CI do not acquire new scheduled jobs.

Manual commands run through `scripts/verification-session.py`. It gives the existing tools disposable intermediate directories, prints results, and removes the directories after success, failure, or handled interruption. Do not run competing builds, mutations, or edits during a manual check. Existing output at those paths makes the runner fail rather than overwrite another run. No generated report archive is retained.

```sh
python3 scripts/verification-session.py coverage
python3 scripts/verification-session.py metrics
python3 scripts/verification-session.py mutations
```

The coverage command prints an LLVM coverage summary before removing its temporary counters.

Ordinary tests: `swift test`. Manual metrics use the installed Xcode SwiftParser and LLVM coverage tools, retaining the existing 90% line, 85% branch and CRAP <=10 gates. Missing Swift branch counters remain unverified. Manual coverage/metrics retain the existing exclusion of `EditorWindowControllerTests.testApplicationKeyDispatchRoutesUndoToVisibleEditor`, which dispatches to a visible window. Mutation selectors such as `--only NAME` or `--group followup` can follow `mutations`.

Mutation outcomes distinguish surviving changes from assertion detections and infrastructure errors. Low-level measurement scripts are implementation helpers; use the manual runner so fresh inputs and temporary cleanup are managed together.

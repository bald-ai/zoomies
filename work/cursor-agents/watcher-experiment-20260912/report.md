# Local watcher experiment — 12 September 2026

**Result: native completion detection passed. Hour-long automatic Codex wake-up remains unverified.**

Used the existing external-worker controller and Devin SWE-2 Max through ACP. No production skill changes were made. The only assignment was to run a Python command that waited 12 seconds, printed 21199, and then finish the turn. No readiness/status marker was requested or written.

## Observed

- Controller finished successfully in 35.81 seconds.
- Devin returned the native `end_turn` completion result and an `agent_stopped` event with cause `complete`.
- The scratch directory stayed empty. Completion did not rely on the model writing a marker.
- One supervisor wait call collected the result. There were no intervening progress checks or model resumptions inside that wait.
- The controller checks its child process locally; the ACP adapter blocks on the protocol stream. Neither waiting mechanism submits inference requests.
- Devin made two tool calls: execute the delayed command, then collect its output after its tool returned a background handle. Its reported statistics were 11,878 input tokens, 23,197 cached input tokens, and 556 output tokens, across three agent messages. These are provider-reported categories, not independently measured charges. They describe the coding worker, not watcher polling.

## Practical limits

This was a 36-second live experiment using ACP. It did not exercise the existing interactive cmux launch path, an hour-long task, controller crashes, or automatic resumption of a Codex conversation after its turn ends. The current Codex tool interface can yield before a long job completes; repeated waits would still resume the supervising model. Therefore this result supports using native completion events and local waiting, but does not establish zero supervisor overhead for an hour-long loop.

For an hour-long event-driven loop, the remaining integration must keep a completion subscription alive and deliver one completion/failure event back to Codex. A background script or cmux desktop notification alone does not prove that bridge. Until that bridge is tested, do not promise zero polling overhead or replace the existing loop on that basis.

## Evidence

See `evidence.json` for the compact record. Raw worker evidence is under `job/`: `devin-protocol.jsonl`, `events.jsonl`, `job.json`, and `handoff.json`. The controller and adapter used for the experiment are hashed in `job.json`.

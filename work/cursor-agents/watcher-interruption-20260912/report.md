# Wait interruption experiment

Passed with a real Devin SWE-2 Max worker using the installed ACP controller.

- At 30.003 seconds, the bounded wait returned control to Codex while the worker continued.
- Codex processed the return and read a compact status snapshot at 44.56 seconds: the worker was still running and had no completion result.
- Codex returned to waiting without sending a follow-up to Devin or restarting its controller.
- The worker completed at 75.24 seconds, emitting native `end_turn`; the second wait returned the result at 75.364 seconds from launch.
- Controller PID, child PID, and session ID stayed the same across the check-in.
- The delayed command ran exactly once and printed the independently verified result, 29357. There were zero tool failures and the scratch scope stayed empty.

This verifies that returning to Codex mid-wait, checking status, and waiting again preserves the active worker and completion delivery. Model processing/status inspection add time after a wait returns, so deadlines must be measured from the latest supervising model request rather than adding a fresh full interval to every subsequent tool invocation.

The production skill remains at 28 minutes; only this experiment used 30 seconds. This run did not measure actual Codex cache hits or exercise an interactive cmux tab. Raw evidence is in `job/`; compact verification is in `evidence.json`.

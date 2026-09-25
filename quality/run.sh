#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."
if [ -z "${VERIFICATION_SESSION_ROOT:-}" ]; then
    exec python3 scripts/verification-session.py metrics
fi
out="Dev/quality-campaign/evidence/${1:-final}"
mkdir -p "$out"
if [ -e "$out/tests.log" ]; then
    echo "Evidence directory already contains a run; choose a new run name."
    exit 2
fi
python3 quality/freshness.py capture "$out/input-sha256.json" || exit $?
swift --version > "$out/provider.txt" 2>&1
xcrun llvm-cov --version >> "$out/provider.txt" 2>&1
swift build > "$out/build.log" 2>&1
result=$?
printf '%s\n' "$result" > "$out/build.exit"
if [ "$result" -ne 0 ]; then tail -40 "$out/build.log"; exit "$result"; fi
# Preserve the visible-window dispatch test; it is outside authorized automation.
swift test --enable-code-coverage --skip EditorWindowControllerTests.testApplicationKeyDispatchRoutesUndoToVisibleEditor > "$out/tests.log" 2>&1
result=$?
printf '%s\n' "$result" > "$out/tests.exit"
if [ "$result" -ne 0 ]; then tail -40 "$out/tests.log"; exit "$result"; fi
host="$(xcrun --find swiftc)"
host="$(dirname "$host")/../lib/swift/host"
xcrun swiftc -I "$host" -L "$host" -Xlinker -rpath -Xlinker "$host" quality/functions.swift -o "$out/function-parser" > "$out/parser.log" 2>&1
result=$?
printf '%s\n' "$result" > "$out/parser.exit"
if [ "$result" -ne 0 ]; then cat "$out/parser.log"; exit "$result"; fi
python3 quality/verify_tools.py "$out/function-parser" > "$out/tool-tests.log" 2>&1
result=$?
printf '%s\n' "$result" > "$out/tool-tests.exit"
if [ "$result" -ne 0 ]; then cat "$out/tool-tests.log"; exit "$result"; fi
"$out/function-parser" Sources/*.swift > "$out/functions.json"
xcrun swiftc -help-hidden > "$out/compiler-options.txt"
xcrun swiftc -frontend -help-hidden > "$out/frontend-options.txt"
xcrun llvm-cov export .build/debug/ZoomiesTests.xctest/Contents/MacOS/ZoomiesTests -instr-profile=.build/debug/codecov/default.profdata -ignore-filename-regex='\.build|Tests/' > "$out/coverage.json"
result=$?
printf '%s\n' "$result" > "$out/coverage.exit"
if [ "$result" -ne 0 ]; then exit "$result"; fi
python3 quality/metrics.py --coverage "$out/coverage.json" --functions "$out/functions.json" --manifest "$out/input-sha256.json" --output "$out/metrics.json" --gate > "$out/metrics.log" 2>&1
result=$?
printf '%s\n' "$result" > "$out/gate.exit"
cat "$out/metrics.log"
exit "$result"

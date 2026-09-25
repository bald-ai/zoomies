#!/usr/bin/env python3
"""Selected, sequential contract mutations. Never run alongside builds/edits.
Each edit is restored in finally and checked against its original SHA-256.
Assertion failures count as detections; crashes/build failures/timeouts do not.
"""

import os as _session_os, sys as _session_sys, subprocess as _session_subprocess
from pathlib import Path as _SessionPath
if not _session_os.environ.get('VERIFICATION_SESSION_ROOT'):
    raise SystemExit(_session_subprocess.call(['python3', str(_SessionPath(__file__).resolve().parents[1] / 'scripts/verification-session.py'), 'mutations', *_session_sys.argv[1:]]))
import signal as _session_signal
_session_signal.signal(_session_signal.SIGTERM, lambda *_: _session_sys.exit(143))
import os
import signal
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
from freshness import snapshot, mismatches

root = Path(__file__).resolve().parents[1]
out = root / 'Dev/quality-campaign/evidence/mutations'
out.mkdir(parents=True, exist_ok=True)
# name, file, unique original, replacement, XCTest filter
trials = [
('video-copy-failure-deletes', 'VideoRenameWorkflowController.swift',
 'presentError(title: "Copy failed", message: message)\n            return false',
 'presentError(title: "Copy failed", message: message)\n            return true', 'VideoRenameWorkflowControllerTests'),
('video-delete-failure-finishes', 'VideoRenameWorkflowController.swift',
 'message: "The original file is still on disk. You can try again."\n                )\n                return false',
 'message: "The original file is still on disk. You can try again."\n                )\n                return true', 'VideoRenameWorkflowControllerTests'),
('video-bypasses-confirmation', 'VideoRenameWorkflowController.swift',
 'case .deleteOnly: return deleteConfirmer() && deleteRecording()', 'case .deleteOnly: return deleteRecording()', 'VideoRenameWorkflowControllerTests'),
('recording-publishes-timeout', 'ScreenRecordingService.swift',
 'guard session.didFinishRecording else {', 'guard true else {', 'ScreenRecordingServiceTests.testTimeoutNeverPublishesNonemptyUnfinalizedRecording'),
('recording-ignores-stale-session', 'ScreenRecordingService.swift',
 'sessionID != id', 'false', 'ScreenRecordingServiceTests.testUnexpectedStreamStopStillPublishesDelegateFinalizedFileEvenIfStopThrows'),
('recording-opens-workflow-on-quit', 'ScreenRecordingService.swift',
 'let shouldReport = savedURL != nil && !isTerminating', 'let shouldReport = savedURL != nil', 'ScreenRecordingServiceTests.testTerminationSavesWithoutOpeningWorkflowAndCompletesOnce'),
('capture-allows-overlap', 'ScreenshotService.swift',
 'if isCaptureInProgress {\n            return false', 'if isCaptureInProgress {\n            return true', 'CaptureOrchestrationTests.testAreaCaptureGatesRepeatedCommandsPersistsAndHandsOffToWorkflow'),
('capture-loses-sound', 'ScreenshotService.swift',
 '        soundPlayer.playCaptureSound()', '        // mutation: omit sound', 'CaptureOrchestrationTests.testAreaCaptureGatesRepeatedCommandsPersistsAndHandsOffToWorkflow'),
('scratchpad-drops-carried-note', 'ScratchpadService.swift',
 'cachedText = text', 'cachedText = ""', 'ScratchpadWorkflowTests'),
('scratchpad-skips-copy', 'ScratchpadService.swift',
 'if copy {', 'if false {', 'ScratchpadWorkflowTests'),
('annotation-allows-zero-width', 'EditorCanvasState.swift',
 'lineWidth.isFinite && lineWidth > 0', 'lineWidth.isFinite && lineWidth >= 0', 'AnnotationSafetyTests.testStrokeWidthsRejectInvalidValuesForEveryStrokeKind'),
('annotation-allows-long-text', 'EditorCanvasState.swift',
 'text.count <= limits.maxTextLength', 'true', 'AnnotationSafetyTests.testTextAndMarkerLimitsRejectMalformedMetadata'),
('annotation-allows-too-many-points', 'EditorCanvasState.swift',
 'points.count <= limits.maxPenPointCount', 'true', 'AnnotationSafetyTests.testEmbeddedImageAndCountLimitsAreAppliedBeforeRestoration'),
('canvas-removes-preview', 'EditorCanvasView.swift',
 '        drawGesturePreview()', '        // mutation: skip gesture preview', 'EditorCanvasPartialRedrawTests'),
('canvas-redo-becomes-undo', 'EditorCanvasView.swift',
 '"z": flags.contains(.shift) ? .redo : .undo', '"z": flags.contains(.shift) ? .undo : .undo', 'CanvasShortcutContractTests'),
('canvas-picker-no-longer-closes', 'EditorCanvasView.swift',
 'return [.selectColor(index: index), .colorPickerClose]', 'return [.selectColor(index: index)]', 'CanvasShortcutContractTests'),
('screenshot-drops-note-on-return', 'ScreenshotWorkflowController.swift',
 'pendingNoteText = text\n            // Open the destination', 'pendingNoteText = ""\n            // Open the destination', 'ScreenshotNavigationTests.testRenameNoteEditorReturnAndSaveRoundTripWithoutPresentingWindows'),
('screenshot-close-deletes', 'ScreenshotWorkflowController.swift',
 'guard restoreOriginalFromBackupIfAvailable() else {', 'guard deleteSourceFileAndBackup() else {', 'ScreenshotNavigationTests.testEditorCloseAndWorkflowCancellationPreserveOriginalAndIgnoreLateActions'),
]
trials.append(('recording-save-failure-loses-original', 'ScreenRecordingService.swift',
 'private func publishSession(_ session: ScreenRecordingSession) -> URL? {',
 'private func publishSession(_ session: ScreenRecordingSession) -> URL? {\n        defer { try? FileManager.default.removeItem(at: session.tempURL) }',
 'ScreenRecordingServiceTests.testFinalizedMissingEmptyAndUnwritableOutputsAreNotReportedAsSaved'))
trials += [
('finder-accepts-oversized-image', 'FinderReopenLogic.swift',
 'return inspect(url)', 'return .open(url)', 'FinderReopenLogicTests'),
('input-redo-becomes-undo', 'FloatingInputPanel.swift',
 'textView.undoManager?.redo()', 'textView.undoManager?.undo()', 'FloatingInputPanelCommandTests'),
('image-size-uses-stale-url-cache', 'ImageSafety.swift',
 'return (attributes?[.size] as? NSNumber)?.intValue', 'return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize', 'ImageSafetyTests.testReusedURLInspectsCurrentFileSizeAfterReplacement'),
('gesture-accepts-tiny-line', 'EditorCanvasView.swift',
 'guard EditorImageRenderer.distance(from: start, to: point) >= 2 else { return nil }',
 'guard EditorImageRenderer.distance(from: start, to: point) >= 1 else { return nil }', 'CanvasGestureContractTests'),
('gesture-loses-undo', 'EditorCanvasView.swift',
 'if let item = completedShape(from: start, to: point) {\n            pushUndoSnapshot()',
 'if let item = completedShape(from: start, to: point) {\n            // omit undo snapshot', 'CanvasGestureContractTests'),
('settings-drops-recording-rate', 'SettingsWindowController.swift',
 'settings.recordingFrameRate = rate', 'settings.recordingFrameRate = 30', 'SettingsWindowContractTests'),
('settings-drops-shortcut-update', 'SettingsWindowController.swift',
 'settings.shortcuts = shortcuts', 'settings.shortcuts = .default', 'SettingsWindowContractTests'),
]
followup_names = {t[0] for t in trials[-7:]}
trials += [
('rename-save-becomes-copy', 'RenamePanelController.swift',
 '.enter: .save(newName: name)',
 '.enter: .copyAndSave(newName: name)', 'RenameInputContractTests'),
('input-backtab-becomes-tab', 'CommandAwareInputControls.swift',
 'keyCommandHandler?(.shiftTab)', 'keyCommandHandler?(.tab)', 'RenameInputContractTests'),
('tool-switch-discards-text-edit', 'EditorCanvasView.swift',
 'if textEditor != nil, tool != .text {', 'if false {', 'NumberedMarkerTests.testSwitchingFromTextToMarkerCommitsTextEditor'),
('image-fallback-selects-smallest-backing', 'ImageEncoding.swift',
 '.max(by: { lhs, rhs in', '.min(by: { lhs, rhs in', 'ImageEncodingTests'),
('image-size-ignores-symlink-target', 'ImageSafety.swift',
 'url.resolvingSymlinksInPath().path', 'url.path', 'ImageSafetyTests.testFileSizeLimitFollowsSymbolicLinkTarget'),
]
completion_names = {t[0] for t in trials[-5:]}
trials += [
('commands-block-stop-behind-busy-workflows', 'ApplicationCommands.swift',
 'if current.stopAvailable {', 'if false {', 'ApplicationCommandsTests.testRecordingStartGatesAndStopPrecedence'),
('commands-never-release-pending-note', 'ApplicationCommands.swift',
 'defer { self.gate.finishScratchpadOpenRequest() }', '// mutation: keep pending note gate', 'ApplicationCommandsTests.testPendingNoteBlocksCompetingCommandsAndCoalescesDuplicates'),
('capture-suppresses-missing-fullscreen-display-id', 'ScreenshotService.swift',
 'if mode == .fullScreen { throw ScreenResolutionError.missingDisplayID }',
 'if false { throw ScreenResolutionError.missingDisplayID }', 'CaptureOrchestrationTests.testMissingDisplayIDDecisionOnlyThrowsForFullscreen'),
('capture-cache-never-expires', 'CaptureContentCache.swift',
 'clock().timeIntervalSince(date) < lifetime', 'clock().timeIntervalSince(date) >= 0', 'CaptureContentCacheTests'),
('capture-cache-retains-failure', 'CaptureContentCache.swift',
 'if self?.entry?.token == token { self?.entry = nil }', '// mutation: retain failed task', 'CaptureContentCacheTests.testFailedLoadIsSharedThenEvictedForRetry'),
('recording-skips-monitor-dwell', 'ScreenRecordingService.swift',
 'guard now - session.candidateSince >= Self.monitorDwellTime else { return }',
 'guard now - session.candidateSince >= 0 else { return }', 'ScreenRecordingServiceTests.testMonitorDwellCancelsCandidatesRetriesFailureAndIgnoresLateUpdates'),
]
parser = argparse.ArgumentParser()
parser.add_argument('--only')
parser.add_argument('--group', choices=['followup', 'completion'])
parser.add_argument('--validate-only', action='store_true')
args = parser.parse_args()
results = json.loads((out / 'results.json').read_text()) if (out / 'results.json').exists() else []
selected = [t for t in trials if (not args.only or t[0] == args.only) and
            (not args.group or t[0] in (followup_names if args.group == 'followup' else completion_names))]
if not selected:
    raise SystemExit('No mutation matched the requested selection')
for name, file, before, after, suite in selected:
    count = (root / 'Sources' / file).read_text().count(before)
    if count != 1:
        raise RuntimeError(f'{name}: expected one mutation site, found {count}')
if args.validate_only:
    print(f'Validated {len(selected)} unique mutation sites; no source changes or tests run.')
    raise SystemExit(0)
inputs = snapshot()
manifest_digest = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
manifest_path = out / f'inputs-{manifest_digest}.json'
manifest_path.write_text(json.dumps(inputs, indent=2) + '\n')
for name, file, before, after, suite in selected:
    if args.group and name not in (followup_names if args.group == 'followup' else completion_names):
        continue
    if args.only and name != args.only:
        continue
    attempt = 1 + sum(r['name'] == name for r in results)
    log_path = out / (f'{name}.log' if attempt == 1 else f'{name}-attempt{attempt}.log')
    path = root / 'Sources' / file
    original = path.read_bytes()
    source = original.decode()
    if source.count(before) != 1:
        raise RuntimeError(f'{name}: expected one mutation site, found {source.count(before)}')
    digest = hashlib.sha256(original).hexdigest()
    start = time.monotonic()
    command = ['swift', 'test', '--filter', suite]
    result = dict(name=name, attempt=attempt, log=str(log_path.relative_to(root)), file=str(path.relative_to(root)), original=before, mutation=after,
                  command=command, source_sha256_before=digest, input_manifest=str(manifest_path.relative_to(root)))
    proc = None
    try:
        path.write_text(source.replace(before, after, 1))
        with log_path.open('w') as log:
            try:
                proc = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                result['exit_code'] = proc.wait(timeout=90)
            except subprocess.TimeoutExpired:
                # Terminate only this trial's dedicated process group, and wait
                # before restoring source that a compiler could still be reading.
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                result.update(outcome='timed_out', exit_code=None)
        log_text = log_path.read_text()
        if 'outcome' not in result:
            if re.search(r'crashed|signal 11|signal 6|Fatal error|error: Build failed', log_text, re.I):
                result['outcome'] = 'errored'
            elif result['exit_code'] != 0 and re.search(r'error: .* : XCTAssert|error: .* : failed|XCTUnwrap failed', log_text):
                result['outcome'] = 'detected'
            elif result['exit_code'] == 0 and re.search(r'Executed [1-9][0-9]* tests?', log_text):
                result['outcome'] = 'surviving'
            else:
                result['outcome'] = 'errored'
        result['assertion_evidence'] = [l for l in log_text.splitlines() if ': error: -[' in l][:8]
    finally:
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
        path.write_bytes(original)
        result['source_sha256_restored'] = hashlib.sha256(path.read_bytes()).hexdigest()
        assert result['source_sha256_restored'] == digest
        result['changed_inputs_after_restore'] = mismatches(inputs, snapshot())
        assert result['changed_inputs_after_restore'] == []
    result['duration_seconds'] = round(time.monotonic()-start,3)
    results.append(result)
    (out / 'results.json').write_text(json.dumps(results,indent=2)+'\n')
    print(name, result['outcome'], result['exit_code'], flush=True)
print('Restored all mutation sites. Ordinary tests must now be rerun.', flush=True)

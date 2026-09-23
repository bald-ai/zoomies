# Video annotation and action context

Status: parked idea for the future. 15 September 2026.

## Purpose

Make it easier to explain bugs, UI changes and interaction problems to coding agents using a short recording with drawings and useful context about what the user did.

This document captures an idea, not an implementation request or an agreed specification. No implementation is planned for now.

## Small video editor

Extend the familiar screenshot annotation experience to recordings:

- Play, pause and scrub through a recording.
- Pause at a useful moment and draw arrows, boxes, freehand strokes, text or numbered markers.
- Associate annotations with a moment or a time range so they appear when relevant.
- Move between annotated moments quickly.
- Copy or export annotated frames with timestamps, and potentially export a video with the drawings included.
- Consider basic trimming if it helps keep the explanation focused.

Example: record a broken menu, pause just before it closes, circle the clicked control and add “this should stay open.” The agent receives the recording and annotated moments that explain the issue.

## Possible user-action tracking

Explore optionally recording a timeline of user actions alongside the video to provide context that is difficult to infer from frames alone:

- Click locations and mouse buttons.
- Scrolling and dragging.
- Keyboard shortcuts and relevant key actions.
- App or window changes.
- Where available, the name or role of the UI element being used.

Synchronize events with video timestamps. A future handoff could describe “00:04.2 — clicked Save” alongside the corresponding annotated frame.

Keep the event list useful and concise. Decide later which events help agents, how recording is enabled, which macOS permissions are needed and how to exclude passwords or other sensitive typed content. Capturing all typed text is not a requirement.

## Potential agent handoff

- Original or annotated recording.
- Selected annotated frames with timestamps.
- User-written description of expected and actual behavior.
- Optional readable action timeline, with structured event data if useful to the receiving agent.

Check what the intended coding agents can actually consume before choosing the output format. Timestamped images and text could be useful even when direct video input is unavailable.

## Existing foundation

- Zoomies already records MP4 video and provides a post-recording rename/copy/save flow.
- The image editor already provides drawing tools, text, numbered markers and undo/redo.
- `Sources/EditorImageRenderer.swift` contains shared annotation drawing and compositing code.
- The current canvas and saved editing state are built around a still image; video playback, annotation timing, event capture and video export would require additional work.

## Questions for when this is resumed

- Is the first useful version paused-frame annotation, or must drawings remain visible during playback?
- Should annotations apply to one frame, a chosen duration or the rest of the recording?
- Should playback pause automatically when drawing starts?
- Which outputs fit the user's actual agent workflow best?
- Which action events add enough context to justify recording them?
- Should recordings remain editable through a separate project file?
- Is trimming needed initially?

## Possible starting point

Start with playback, scrubbing, drawing on selected paused frames and exporting those frames with timestamps. Evaluate timed overlays, annotated video export and action tracking after trying that workflow.

Automatic tracking of moving objects, complex timelines, transitions and audio editing are beyond this initial idea.

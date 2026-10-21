# Surface learnings

Append-only. Lessons about the window model, SwiftUI hosting in AppKit panels, pointer behaviour and rendering.

### [2026-10-19] A cursor rect under SwiftUI never shows; check pointer behaviour by hand

**Context**: D5.1's pane dividers set their resize cursor with `addCursorRect` on an `NSViewRepresentable` behind a SwiftUI drag strip. Every unit test passed.
**Correction**: Dom's hand check: "the cursor is not changing ... the cursor stays the arrow". The SwiftUI hosting view handles cursor updates over its area and puts the arrow back.
**Rule**: In an AppKit panel hosting SwiftUI, never rely on a cursor rect. Own the cursor with an `NSTrackingArea` (`.cursorUpdate`, `.mouseEnteredAndExited`, `.activeAlways`, `.inVisibleRect`) and set it again on every move with `.onContinuousHover`, holding it through a drag. Treat cursors, gestures and hit areas as unverified until Dom has checked them by hand, and say so in the hand-over.
**Applies to**: Surface, Features (anything drawn in the expanded panel or the Orbit)

### [2026-10-19] A layer view does not repaint itself on resize

**Context**: P1 moved the Pillars field to a layer-backed `NSView` with `layerContentsRedrawPolicy = .onSetNeedsDisplay`, painted on a display link.
**Correction**: The P1 review found a resize leaves the old bitmap stretched, because a size change does not mark that layer for display and the box-unit drawing looks unchanged; with the link paused it stays stretched.
**Rule**: A view that paints only on request repaints itself in `setFrameSize(_:)` and `viewDidChangeBackingProperties()`, and asks for an 8-bit backing store (`.RGBA8Uint`) when it paints every frame. Test both.
**Applies to**: Surface (any `NSView` painted by hand)

### [2026-10-20] A confirmation dialog's dismissal runs before its action's Task

**Context**: D7's Settings asked to confirm "Go live" and the environment switch with `confirmationDialog(isPresented:)`, whose binding setter cleared the pending flag, while the confirm button started a Task that guarded on that flag.
**Correction**: Dom's hand check found Go live did nothing. Pressing the button dismisses the dialog first, the setter clears the flag, and the Task then returns early. The model and integration tests called the confirm step directly, so they never saw the dismissal.
**Rule**: Pass the confirmed value through `confirmationDialog(_:isPresented:presenting:)` into the action, and never guard a confirm step on state the dismissal clears. Test the real order: request, dismissal, then confirm.
**Applies to**: Features and Surface (every dialog, alert or sheet with a confirm action)

### [2026-10-20] The CI runner has Reduce Motion on and a US region

**Context**: D7's Settings snapshots passed on Dom's Mac and failed on the `xcode-27` runner, at 92% of pixels.
**Correction**: Dom's pull request failed CI. The motion row's text follows the system's Reduce Motion, which is on in the runner, and wraps to a second line; the native time pickers follow the region, US English there, and read 7:00 PM. Forcing both locally reproduced CI's numbers exactly.
**Rule**: A snapshot must not depend on the machine's accessibility settings, region or time zone. Pin `en_GB` on any native control that formats a date or number, give any view that reads a system accessibility setting a seam the snapshot holds fixed, and before recording, render once with a US locale and with Reduce Motion forced on to prove the image does not change.
**Applies to**: Features and Surface snapshot tests

### [2026-10-21] A state bug that a relaunch clears needs evidence the system keeps

**Context**: During D9's hand check the Today field stopped animating, and only a relaunch restarted it. Ian logged nothing at a level the unified log keeps, so `log show` held nothing to read, and the first suspect (the system Reduce Motion read) did not reproduce it, nor did "Pause me", the camera, a lock or a screen recording.
**Correction**: Dom reported the stall and that none of the suspected triggers reproduced it.
**Rule**: State that decides whether something moves or shows (the field's clock, the panel's on-screen state, suppression) logs each change at `.notice` with its inputs as public booleans and no item content, so a stall leaves evidence. When a field or the Orbit stops moving, read `log show --predicate 'subsystem == "ai.valliance.ian.desktop" AND category == "motion"'` before guessing at a cause.
**Applies to**: Surface, Features

# Surface learnings

Append-only. Lessons about the window model, SwiftUI hosting in AppKit panels, pointer behaviour and rendering.

### [2026-10-19] A cursor rect under SwiftUI never shows; check pointer behaviour by hand

**Context**: D5.1's pane dividers set their resize cursor with `addCursorRect` on an `NSViewRepresentable` behind a SwiftUI drag strip. Every unit test passed.
**Correction**: Dom's hand check: "the cursor is not changing ... the cursor stays the arrow". The SwiftUI hosting view handles cursor updates over its area and puts the arrow back.
**Rule**: In an AppKit panel hosting SwiftUI, never rely on a cursor rect. Own the cursor with an `NSTrackingArea` (`.cursorUpdate`, `.mouseEnteredAndExited`, `.activeAlways`, `.inVisibleRect`) and set it again on every move with `.onContinuousHover`, holding it through a drag. Treat cursors, gestures and hit areas as unverified until Dom has checked them by hand, and say so in the hand-over.
**Applies to**: Surface, Features (anything drawn in the expanded panel or the Orbit)

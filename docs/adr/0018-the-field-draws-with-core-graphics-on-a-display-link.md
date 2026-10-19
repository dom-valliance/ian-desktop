# 0018. The field draws with Core Graphics on a display link

Date: 2026-10-19
Status: Accepted

## Context

ADR 0004 draws the Pillars field with a SwiftUI `Canvas` inside a `TimelineView`. D5 measured the cost in Release on an Apple M4 Pro: about 14% CPU for the field alone at 60 frames a second, against the 15% budget on an M1 in spec 6.9. D5.1 found that most of it is SwiftUI's per-frame layout, view-graph update and commit; an empty `Canvas` in a 60 frames a second `TimelineView` cost as much as the field.

P1 set the target on the M4 Pro at two thirds of each budget, under 10% with the field animating. To choose the route, a harness window (a 600 by 300 point field, five columns, twelve pillars, one alert pulsing, one selected pillar rippling, working particles, `normal` motion) was built in Release and its process CPU taken from the change in `ps -o time=` over 30 seconds after a 10 second warm-up:

| Field | Before (SwiftUI `Canvas`) | After |
|---|---|---|
| Busy, as above | 8.6, 13.2, 16.9, 16.3, 11.3 (mean 13.3%) | 8.0, 8.1 (mean 8.0%) |
| Calm: no alert, no selection, no particles; only the sway moves | 16.7 | 1.6 and 2.3 |
| Reduce Motion, nothing growing | not measured | 0 |

A first Core Graphics version that repainted every frame measured 13.6 to 17.8% in the busy scene, no better than SwiftUI. A trace showed 8% of one core in `CGContextDrawPath` and a further 2% in commits: the cost is the rasterising, not only the view graph. A half-float backing store, which the system chose on a wide-colour display, made each fill several times dearer than 8 bits a channel.

The work package named three routes: Core Animation layers per pillar, Metal, and SceneKit. None was chosen. Each rebuilds the drawing in a second representation (layer trees or a scene graph) that the snapshot tests and the hit test could not share with the renderer, and each adds work to keep the two in step. A Core Graphics painter reads the existing `PillarsDrawing` directly, keeps one painter for the screen and the tests, and met the target on the measurements below.

## Decision

The field is an AppKit `NSView` (`PillarsFieldNSView`), layer-backed, hosted in SwiftUI through `NSViewRepresentable`. `PillarsFieldView` keeps its public initialiser, and `TodayView` is unchanged.

- **Drawing.** `draw(_:)` paints `PillarsRenderer`'s `PillarsDrawing` with `PillarsPainter` in Core Graphics. The renderer's maths, the hit test and the angle saving (ADR 0016) are unchanged. The snapshot tests paint into a bitmap with the same `PillarsPainter`, so the tests and the screen share one painter. The row titles are laid out once as `CTLine`s.
- **Clock.** A display link made by `NSView.displayLink(target:selector:)`, at 60 frames a second, is unpaused only while `isAnimating` is true, the window is visible and unoccluded, the view is not hidden, and something moves: the sway always moves unless Reduce Motion is on, and under Reduce Motion only a growth or a sink does. Otherwise the link is paused and the view holds its last pose.
- **Repaint only what shows.** Each tick makes the drawing, which is cheap, and repaints only if it differs visibly from the last one painted: a point moved by a device pixel or more, a colour channel by 6 of 255, or the structure changed. The sway moves the nearest corner under a device pixel for most frames, so a calm field repaints about ten times a second where every frame would repaint the same pixels. A busy field with a pulse, ripple and particles repaints about 30 times a second. Motion that shows is still drawn; this is the reason for the calm figure above.
- **Backing store.** The layer asks for 8 bits a channel (`contentsFormat = .RGBA8Uint`).
- **Pointer.** The view takes the mouse itself and feeds `FieldPointer`, which is unchanged: a click selects, a double-click returns to 45 degrees, a drag turns the field.
- **Accessibility.** The view is not an accessibility element. The one labelled SwiftUI overlay stays, with no action, so VoiceOver activation selects nothing (non-negotiable 8).

## Consequences

- ADR 0004's rule that Pillars is drawn with SwiftUI `Canvas` inside `TimelineView` is replaced for the field. The Orbit, the lists, the panes and the dividers stay in SwiftUI. ADR 0004's other rule, that rendering pauses when hidden, occluded or suppressed, still holds and is now tested at the display link.
- The field reaches 60 frames a second in capability, not in repaints: a frame that would repaint identical pixels is skipped. The 6.9 figure is read as smooth motion, which the pixel tolerance keeps; a reviewer who wants every frame painted can set the tolerance to zero and pay the cost in the table.
- The 8.0% figure is for the busiest realistic scene in a harness, not the app with the panel open; `scripts/measure-cpu.sh` measures the app.
- The field now owns its pointer handling in AppKit. A mouse-down on the field cannot move the window (`mouseDownCanMoveWindow` is false) and the first click is accepted.
- The field adds no import: Core Text and Core Animation come with AppKit.
- The `angle` argument of `PillarsFieldView` is where the field starts. The drag state lives in the view, as before.
- The Pillars snapshots were re-recorded because Core Graphics places the row titles about a point lower and rasterises edges differently from SwiftUI. Polygons, colours and positions otherwise match: before re-recording, 99.7% of pixels matched and the differing ones were the labels.

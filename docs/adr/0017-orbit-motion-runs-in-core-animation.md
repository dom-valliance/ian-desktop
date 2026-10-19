# 0017. The Orbit's motion runs in Core Animation

Date: 2026-10-19
Status: Accepted

## Context

ADR 0004 draws the Orbit with a SwiftUI `Canvas` inside a `TimelineView`. Spec 6.9 budgets under 1% CPU with only the Orbit showing, on an M1. D4 recorded the Orbit as inside it. The D5 measurement, in Release on an Apple M4 Pro with `scripts/measure-cpu.sh`'s method (the change in the process's CPU time over 30 seconds after a 10-second warm-up), showed otherwise: 9.0% in `normal`, where the core breathes, and 9.5% in `incident`, where an alert pulses, against 0.4% in `quiet`, where nothing moves. P1's baseline run of the script on the unchanged code gave 8.89%, 5.56% and 0.47%.

The cost is not the drawing. The Orbit is a few circles, an arc and a pill. At 20 frames a second a `TimelineView` makes SwiftUI evaluate the view, lay it out, run the `Canvas` closure and commit a transaction to the render server on every frame, and that overhead is paid in Ian's process for a picture that changes by one radius and one opacity. P1 sets the target at two thirds of each budget, since no M1 is available: under 0.7% in `normal` and `incident`.

## Decision

The Orbit's two continuous motions run as Core Animation layer animations, which the render server animates outside Ian's process:

- the core's breath while `working`: a `CABasicAnimation` of `path` on a `CAShapeLayer`, from a circle of radius 6 to one of radius 7, which is the renderer's `6 + b` with `b = 0.5 + 0.5 sin(1.5 t)`;
- each alert satellite's rim pulse: a `CABasicAnimation` of `opacity` on a `CAShapeLayer`, from 0.5 to 1, which is the renderer's rim alpha `0.5 + 0.5 p` with `p = 0.5 + 0.5 sin(5 t)`.

Both autoreverse with ease in and ease out and repeat for ever. Their duration is half the sine's period (pi over the rate), so the cycle matches the renderer's. The layers sit in the renderer's 100 by 100 box and are scaled to the view; their paths and colours come from `OrbitRenderer`, which stays the single source of geometry.

The rest of the Orbit (the track, the arcs, the satellites, the chip and the resting core) is the still pose: `OrbitRenderer.drawing` at time 0 with Reduce Motion, drawn by the `Canvas` only when the model, the size or the motion state changes. The `TimelineView` is removed.

The animations exist only while the Orbit is on screen (not hidden or occluded), unsuppressed, Reduce Motion is off (the system's or the setting) and something in the model moves. Otherwise the layers are removed, and the still pose draws the resting state itself. While the layers run, the still pose leaves out the core and the rims they draw, so nothing is drawn twice.

Pillars are outside this decision. ADR 0004 still governs them, and a separate ADR chooses their route.

## Consequences

- ADR 0004 is amended for the Orbit only: its continuous motion is not drawn by `Canvas` in `TimelineView`. Its other rules stand: a pure renderer, a motion parameter, pausing when unseen.
- Ian's process does no work per frame for the Orbit. Idle cost is the state changes: a new snapshot redraws the still pose.
- Snapshots and live layers meet at the renderer. Snapshot tests still render `OrbitRenderer.drawing` through `OrbitDrawingView` at a fixed time and are unchanged. They do not show the layers; tests of the layers check their paths, key paths, durations and ranges against the same renderer values. The animated frames between the two values are the render server's and have no snapshot.
- The ease in and ease out curve approximates a sine. It matches the range and the period, not every intermediate value.
- A layer is a second drawing of the core and the rim, so the still pose and the layers must stay in step. One test checks that the still pose leaves out exactly the parts the layers draw.
- `Surface` imports QuartzCore for the layers; the import graph in `Packages/IanKit/README.md` says so.
- Anything later that moves on the Orbit should be a layer animation, not a clock.

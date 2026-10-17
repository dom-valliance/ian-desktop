# 0004. Rendering stays in SwiftUI

Date: 2026-10-17
Status: Accepted

## Context

The Orbit and Pillars were designed on the canvas "Ian desktop presence: avatar concepts" as SVG drawn each frame from a small 2.5D projection (constants and formulas in [docs/design/README.md](../design/README.md)). Spec 6.9 sets the budget: under 1% CPU idle with only the Orbit, under 15% CPU at 60 frames per second with Pillars animating, on an M1.

## Decision

Orbit and Pillars are drawn with SwiftUI `Canvas` inside `TimelineView`, using the same projection as the canvas. Rendering pauses whenever the view is hidden, occluded or suppressed. SceneKit or Metal is used only if the budget fails, and that change needs its own ADR.

## Consequences

- Each renderer is a pure function of (state, time, motion setting) to drawing commands. Snapshot tests fix the time and the motion setting, so they are deterministic.
- The projection, shading and sinking maths are ported once from the canvas source and tested against points computed from it.
- Reduce Motion is a parameter of the renderer, not a separate code path.
- If `Canvas` misses the budget, the fallback costs about two days (spec section 14). D9 measures it with Instruments before any polish.

# 0024. The Orbit's core is the Valliance star

Date: 2026-10-21
Status: Accepted, amends 0017

## Context

Spec 6.1 draws the Orbit "as drawn on the Scale and Recommended artboards", whose core is a dot of radius 6. ADR 0017 followed it: the breath is a `CABasicAnimation` of `path` on a `CAShapeLayer`, from a circle of radius 6 to one of radius 7. Dom decided on 21 October 2026 that the core is the Valliance star instead. The review of commits 64e5ee0 to 51afc3c found that the code, the design README and ADR 0017 then disagreed: the breath is now a scale, and the spec's reference drew a dot.

The Orbit has no backdrop of its own. Over a white window the off-white star has a contrast of about 1.2 to 1 and nearly disappears.

## Decision

Dom decided this on 21 October 2026.

**The shape.** `StarShape` draws the star as a vector path: the union of four quarter rings, one centred on each corner of a square, with an inner radius of 0.412 of the side. The fraction was fitted to the brand source PNGs in `assets/` by maximising the intersection over union of their coverage; the fit is 0.995. The union leaves four flat arms and a concave diamond hole at the centre. The source PNGs are not bundled into the app.

**The size and the colours.** The star is 18 units across at rest (half side 9), against the 12 unit dot it replaces. It is off-white `#F2EEEE` at rest and `#B0C1E3` while any item is `working`.

**The breath.** The breath is a `CABasicAnimation` of `transform.scale` on the core's layer, from 1 to 7/6, about the layer's centre. The layer is the box's size, so its anchor point (0.5, 0.5) is the box's middle and its position is the Orbit's centre (50, 50). The star grows from half side 9 to 10.5, 21 units across, which is the one in six the dot's radius grew. The range, the period (4.2 seconds, `pi / 1.5` each way) and the ease in and out are unchanged from ADR 0017. The breath stays a Core Animation layer animation and has no clock.

**The ring.** The still ring round a working core, drawn whenever the breath is held still, sits at radius 13.5: 3 units outside the arms at their longest, and 2.5 units outside the star's keyline.

**The keyline.** The star carries a thin dark outline, so it stays legible over a light window. The outline follows the star's outer edge and the edge of its hole. About 0.5 units of it show (about half a point at 96 points), in the ground colour `#171717`. It is drawn by stroking the star's path at twice that width, 1.0 unit, beneath the fill, so the inner half is hidden and the star's shape and size are unchanged. The still pose draws the stroke before the fill; the breathing layer is a container holding a stroke layer under a fill layer, and the container carries the scale, so the keyline breathes with the star. On the dark ground the design draws, the keyline is the ground's own colour and cannot be seen. Over white it lifts the contrast from about 1.2 to 1 to about 17 to 1.

**Spec 6.1.** The spec's phrase "as drawn on the Scale and Recommended artboards" holds for the Orbit's layout: the track, the arcs, the satellites and the chip. The core is the star, a deviation from those artboards that Dom decided and this ADR records. The design README's star row and its deviations table say so.

**Amendment to ADR 0017.** Its first bullet read "the core's breath while `working`: a `CABasicAnimation` of `path` on a `CAShapeLayer`, from a circle of radius 6 to one of radius 7". Read it as the breath above: `transform.scale` from 1 to 7/6 on the star's layer. The rim pulse, the rest of the decision and its consequences stand, except that the core's layer is now a container of a keyline layer and a fill layer.

## Consequences

- The Orbit's snapshots show the star and its keyline. A new snapshot records the star over a white backdrop.
- The keyline adds 0.5 units to the star's reach, and the still ring clears it. A test holds the gap.
- A change to the star's size, the breath's range or the ring's radius is checked against the ring's clearance of the keyline.
- The star draws twice while a layer runs (the still pose omits it then, ADR 0017), so the still pose and the layer must keep the same keyline. Tests check both.

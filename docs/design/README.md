# Design references

The Orbit and Pillars come from the canvas "Ian desktop presence: avatar concepts" (https://claude.ai/artifact/Xt1vNGhynLzzKFe7UTH2U8, version `1792226173-1f35`). The canvas needs a claude.ai sign-in, so its artboard sources were copied into [canvas/](canvas/) on 17 October 2026. They are HTML with inline SVG and a small script per artboard; open the script block of [Recommended.dc.html](canvas/Recommended.dc.html) to see every formula below in running form.

| Artboard | File | Used for |
|---|---|---|
| Recommended, Orbit at rest and Pillars on open | [Recommended.dc.html](canvas/Recommended.dc.html) | The Orbit, the field, the list beside it, the selection footer |
| Option F, Pillars | [Pillars.dc.html](canvas/Pillars.dc.html) | The field on its own; same maths as Recommended |
| Orbit at scale | [Scale.dc.html](canvas/Scale.dc.html) | Ring and satellites at quiet, normal and overloaded load, the overflow chip |
| Attention ladder | [Ladder.dc.html](canvas/Ladder.dc.html) | The four rungs; the spec's table in 6.6 is authoritative |
| Orbit in context, expanded | [Context.dc.html](canvas/Context.dc.html) | Card layout, confidence label, the "Tell Ian" field for hand-off |
| Five presences, four states | [Main.dc.html](canvas/Main.dc.html) | State colours. Ember, Sigil, Tide and Pane are out of scope |

`canvas/ds/valliance/` holds the Valliance design system's colour and type tokens, copied verbatim (so its comments keep their own punctuation).

Where the canvas and the spec differ, the spec wins. Differences found so far are listed at the end.

## Colour

Dark ground throughout. Values are sRGB.

| Use | Value | Token |
|---|---|---|
| Ground | `#171717` | grey-1000 |
| Card | `#242424` | grey-900 |
| Raised fill, chips | `#2E2E2E` | grey-800 |
| Expanded panel | `rgba(28,27,27,0.96)`, border `rgba(255,255,255,0.12)`, radius 16 | |
| Text | `#F2EEEE`; secondary at 0.8, 0.75, 0.7 and 0.6 opacity | off-white-50 |
| Commitment owed by you (`commitment_by`) | `#F3A982` (243, 169, 130) | peach-200 |
| Commitment owed to you (`commitment_to`) | `#B0C1E3` (176, 193, 227) | blue-200 |
| Proposal | `#F0B9E2` (240, 185, 226) | pink-200 |
| Alert | `#D88C8C` (216, 140, 140), always with a light rim | |
| Task | `#7FBFC1`, the AGENTS.md Q12 default; the canvas has no task colour | teal-100 |
| Resting core | `#A19A9A` | grey-500 |
| Load arc | `#8D8989` | grey-600 |
| Working (core, particles) | `#B0C1E3` | blue-200 |
| Resolved status text | `#9EC2A1` | |

Working and "owed to you" share a blue. They never collide on screen: working shows on the core and as rising particles, kinds show on satellites and pillar faces.

Type on the canvas is Satoshi (400, 500) with DM Mono for uppercase labels at 11 to 12 points and 0.16 em tracking. Version 0 uses the system font and `.monospaced()` for those labels unless Dom supplies the Satoshi files; bundling a font needs its licence checked first.

## Orbit

From Recommended. The avatar is drawn in a 100 by 100 unit box, rendered at 96 points. The spec's 16-point corner inset replaces the canvas's 28.

| Part | Geometry | Behaviour |
|---|---|---|
| Track | Circle r 34, stroke `rgba(255,255,255,0.10)`, width 2.5 | Always drawn |
| Load arc | Circle r 34, stroke `#8D8989`, width 2.5, round caps, from 12 o'clock clockwise | Length is `min(1, load / median)` of the circumference |
| Over-median arc | Circle r 42, stroke `#F3A982`, width 2.5, round caps, from 12 o'clock | Length is `clamp(load / median - 1, 0, 1)` of the circumference |
| Core | Circle at centre, r 6, `#A19A9A` | While any item is `working`: fill `#B0C1E3`, r `6 + b` with `b = 0.5 + 0.5 sin(1.5 t)` (a 4.2 second breath) |
| Satellites | On r 34 at -90, -18, 54, 126 and 198 degrees, in the server's order | r 4.5 in the kind colour. Alerts r 6.5 with a rim of width 1.5 in `rgba(242,238,238, 0.5 + 0.5 p)`, `p = 0.5 + 0.5 sin(5 t)` |
| Overflow chip | From Scale, whose 160 unit box maps to the 100 unit box at 100/160: pill 20 by 15, radius 7.5, fill `#2E2E2E`, stroke `rgba(255,255,255,0.3)` width 0.625, "+n" at 7.5 units in white | Shown when `overflow > 0`. Centred at -126 degrees on radius 40, between the first and last satellites. The Scale artboard's own position would overlap the 198 degree satellite on Recommended's layout |
| Whisper | Pill, padding 4 by 10, fill `#2E2E2E`, border `rgba(216,140,140,0.5)`, white 12-point text, to the left of the avatar | Urgent rung only, eight seconds, never while suppressed |
| Hover label | Pill, padding 4 by 10, fill `#2E2E2E`, border `rgba(255,255,255,0.15)` width 1, white 12-point text on one line | The top item's title, beside the avatar on the side facing the screen's centre, 8 points away. Not shown while suppressed |

Zero-length arcs are omitted: no load arc when `load` is 0 and no over-median arc when `load / median` is at most 1, since a round cap would draw a dot at 12 o'clock.

`load`, `median`, `working`, the satellite list and `overflow` all come from `GET /today`. The client draws them; it never counts or sorts them.

VoiceOver label (spec 6.1): "Ian, three need you now, forty-one open, one urgent".

## Pillars

From Recommended and Pillars. The field is a 5 by 3 grid drawn in a 540 by 420 unit box.

Constants: cell pitch `S = 64`, half-width of a pillar's base `HW = 25`, vertical squash `TILT = 0.52`, origin `CX = 300, CY = 250`, height for pressure 1 `MAXH = 120`, plate margin `pad = 0.62 S`.

- **Grid.** Column `c` is a unit of work (0 to 4, the fifth is "Other"). Row `r` is a horizon: 0 Later, 1 This week, 2 Now, so Now sits at the front. A cell's centre is `x = (c - 2) S`, `z = (r - 1) S`.
- **Yaw.** `psi = 45 degrees + turn * sin(0.22 t)`, with `turn` 10 degrees by default (0 to 30). Reduce Motion fixes `psi` at 45 degrees.
- **Projection.** `proj(x, z, h) = (CX + x cos psi - z sin psi, CY + (x sin psi + z cos psi) TILT - h)`.
- **Order.** Draw cells back to front, sorted by `x sin psi + z cos psi` ascending.
- **Base.** Corners at `(+-HW, +-HW)` around the centre, in the order (-1,-1), (1,-1), (1,1), (-1,1). Edge `e` runs from corner `e` to `e + 1` with outward normal (0,-1), (1,0), (0,1), (-1,0).
- **Height.** `h = max(0, 14 + pressure * MAXH + ripple) * grow * sink`, where `pressure` is the cell's aggregate pressure from the server.
  - `ripple = 4 sin(0.8 d - 2.6 t)`, `d` the distance in cells from the selected cell. Off under Reduce Motion.
  - `grow = easeOutCubic(clamp((t - openedAt - (2 - r) 0.09 - c 0.05) / 0.6))` when the client opens, so Now rises first. Reduce Motion replaces it with a fade.
  - `sink = 1 - easeOutCubic(clamp((t - settledAt) / 0.7))`, started when the server's event removes or settles the item, never on the click. Below 0.02 the pillar is gone and the cell draws as an empty tile.
  - `easeOutCubic(x) = 1 - (1 - x)^3`.
- **Faces.** A side face is drawn when `n.x sin psi + n.z cos psi > 0`. Its shade is `m = 0.6 + 0.2 (nx + 1) / 2` with `nx = n.x cos psi - n.z sin psi`. The top face uses `m = 0.96`. A shaded colour mixes the kind colour towards the ground: each channel is `23 + (k - 23) m`.
- **Top outline.** Selected: `#FFFFFF`, width 3. Alert: `rgba(242,238,238, 0.45 + 0.5 p)`, width 2.5, with the pulse `p` above. Otherwise the fill colour, width 1.
- **Empty cell.** Flat tile, fill `rgba(255,255,255,0.05)`, stroke `rgba(255,255,255,0.14)`.
- **Plate.** The quad from `(-2S - pad, -S - pad)` to `(2S + pad, S + pad)` at height 0, fill `rgba(255,255,255,0.025)`, stroke `rgba(255,255,255,0.08)`.
- **Row labels.** At `proj(-2S - pad - 6, (r - 1) S, 0)` plus 4 down, right-aligned, monospaced 11 points, tracking 1.6, `rgba(242,238,238,0.6)`: LATER, THIS WEEK, NOW.
- **Working.** Five particles rise from the top face's centre `(tx, ty)`. For particle `k`, phase `ph = (0.32 t + 0.2 k) mod 1`; position `(tx + 6 sin(6 ph + 1.7 k), ty - 8 - 80 ph)`; radius 2.2 for odd `k`, 3.2 for even; fill `#F2EEEE` for odd, `#B0C1E3` for even; opacity `0.85 sin(pi ph)`. Reduce Motion holds `t` at 0.4.
- **Panel entrance.** Opacity eases in over 0.3 seconds; the panel rises 14 points over 0.35 seconds.

## List beside the field

Rows sorted as the server sends them (the canvas sorts Now first, then by pressure; the server owns that order). Each row: a 10-point colour square with radius 2, the title at 13 points truncated with an ellipsis, and a monospaced tag at 11 points (the item count for a rolled-up group, else the horizon). Selected row: fill `rgba(255,255,255,0.08)`, border `rgba(255,255,255,0.3)`. A settled row dims to 0.35 until it leaves.

Selection footer: a monospaced line "KIND / UNIT / HORIZON", the title at 16 points weight 500, the meta line at 13 points, then the item's actions. Primary button: fill `#F2EEEE`, text `#171717`. Secondary: outline `rgba(255,255,255,0.2)`. "Hand to Ian" (only when `capabilities.handoff`): outline `rgba(176,193,227,0.45)`, text `#C7D3EB`. Buttons are at least 36 points tall with radius 6.

Copy on the canvas after an action ("Settled. Recorded on the ledger", "Approved. The executor will act", "Rejected. Counted against the rule", "Handed to Ian. A proposal will follow") shows the tone. In the client the item shows "Pending" until the server's event arrives, then the state the event carries.

## Attention ladder

The spec's table in 6.6 is authoritative. The Ladder artboard adds two columns the client does not act on, because Lance owns delivery (DL5): when Slack takes over (after ten idle minutes, or when the desktop app is not running; always at once for Stop) and when delivery is held back.

## Where the canvas and the spec differ

| Canvas | Spec, which wins |
|---|---|
| Orbit 28 points from the corner | 16-point inset |
| Scale artboard colours every needs-you satellite peach | Satellites take their kind colour, as on Recommended |
| A snoozed pillar shrinks to 45% at once | A snooze is an action; the server's event sets the new pressure or moves the item |
| Pillars settle on click | Pillars sink when the server's event arrives (ADR 0001) |
| The list is sorted on the client | The server sends the order |
| Ladder holds notifications for Focus and screen sharing | Suppression list in 6.5; Focus is AGENTS.md Q13 |
| The list sits beside the field | The Now list, This week and Later sit below the field (spec 6.3); the selection footer is pinned under them |
| A rolled-up group's tag is not specified | The week tag shows the group's item count. A Later row takes its colour from the kind of its first count. Both follow the server's order |
| The field only sways, at 10 degrees around 45 | The principal turns it by dragging sideways, all the way round, at 0.5 degrees a point; the sway carries on around the angle chosen, and Reduce Motion stops the sway but not the turn. A double-click returns to 45 degrees. The tilt never changes (ADR 0016) |
| Field panel 860 points wide | Expanded client 1,040 by 720 points, with Today's field inside it |
| Scale shows a variant grouped by unit of work | Not in version 0 |
| The fifth column is always Other | Columns are drawn left to right in the order the server sends `field.units`; Other is last when the server sends it (ADR 0009, item 20) |

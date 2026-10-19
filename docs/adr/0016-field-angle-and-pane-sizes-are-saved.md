# 0016. The field's angle and the pane sizes are saved

Date: 2026-10-19
Status: Accepted

## Context

Spec 6.4 lists the client settings stored in `UserDefaults`: corner, motion, notification levels, the two suppression toggles, launch at login and the environment profile. Non-negotiable 5 allows nothing else on disk but tokens in the Keychain and those settings. D4 saves the corner under `IanOrbitCorner`.

D5.1 lets the principal turn the Pillars field by dragging it, and resize the expanded client's three panes by dragging the dividers between them. Dom asked for all three values to survive a relaunch, so the field comes back as it was left. None of the three is in the spec 6.4 list, and none carries item content.

AppKit can autosave split view positions, but it chooses its own keys, and it does not cover the field's angle. Explicit keys make the stored values visible and testable.

## Decision

Three values join the client settings that may reach disk, in `UserDefaults` under explicit keys, each a number:

| Key | Value | Default |
|---|---|---|
| `IanFieldAngle` | The field's angle about its vertical axis, in degrees, `0..<360` | 45 |
| `IanSidebarWidth` | The sidebar's width, in points | 190 |
| `IanFieldHeight` | The field pane's height, in points | 300 |

`ClientLayoutSettings` in `Surface` reads and writes them. A value that is missing, not a finite number, or (for a size) not above zero reads as the default. The angle is saved when a turn or a double-click ends, and the sizes when a divider drag lets go. The panes clamp a saved size to their minimum and maximum sizes each time they lay out, so a saved size never leaves a pane unusable on a smaller display.

Nothing else about the layout is saved: the last view is still remembered for the life of the process only.

## Consequences

- Non-negotiable 5 and spec 6.4 are read as including these three keys. AGENTS.md and the spec are not edited here; the phase log and the next review of AGENTS.md carry the change.
- The values are numbers with no item content, so the diagnostics report and logs are unaffected.
- A principal who wants the defaults back double-clicks the field for the angle. There is no reset for the sizes in version 0; deleting the keys restores them.
- Tests use a scratch defaults suite and delete it, so no test writes to the real preferences.

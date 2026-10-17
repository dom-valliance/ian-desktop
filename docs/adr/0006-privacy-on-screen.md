# 0006. Privacy on screen

Date: 2026-10-17
Status: Accepted

## Context

Ian shows client names, commitments and alert text on a laptop that shares its screen in meetings. macOS offers no public signal that the screen is being shared. Recent macOS releases have weakened `sharingType` against some capture paths (spec section 14, the top risk for the phase review).

## Decision

Every window sets `sharingType = .none`. Suppression (spec 6.5: camera live, external meeting, quiet hours, user pause) hides all item text and holds notifications, while the Orbit keeps showing state. Screen-sharing protection cannot be switched off in Settings.

## Consequences

- Every new window or panel is created through one factory in `Surface` that sets `sharingType`, so none is missed. A test asserts it for each window the app opens.
- Suppression is computed on the client from local signals plus `today.context` from the server. This is the one decision the client takes itself, because its inputs are local; it never changes data.
- P0 still notifies while suppressed, with its text hidden.
- Acceptance (spec section 11) includes a recording with the system screenshot tool that shows no Ian window. It is rerun on each new major macOS release.

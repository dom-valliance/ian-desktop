# 0020. Notification levels, suppression toggles and the order of a new agent

Date: 2026-10-19
Status: Accepted

## Context

D7 builds the client settings of spec 6.4 and the Agents view of 6.3. Four points are not settled by the spec text, or need it read against another section:

- Spec 6.4 lists a "notification level per attention rung", and spec 6.6 says the Stop rung "always" notifies.
- Spec 6.6 gives Urgent a banner and the two lower rungs no notification. It names no other level.
- Spec 6.4 lists suppression toggles for a live camera and for external meetings. Spec 6.5 lists four triggers, and D8 reports a `suppressed` flag in the session heartbeat.
- D3's store appends an agent first seen in `agent.updated` at the end of its list. The contract's `GET /agents` returns the agents in the order Lance displays them.

## Decision

- **Stop is fixed.** Settings shows Stop as "Always" and saves nothing for it. Spec 6.6 wins over the letter of 6.4's "level per rung". The rungs Ambient, Needs you and Urgent each have a level.
- **Levels are Off and Banner,** saved as `off` or `banner` under `IanNotificationLevelAmbient`, `IanNotificationLevelNeedsYou` and `IanNotificationLevelUrgent`. The defaults are the spec 6.6 table: Ambient off, Needs you off, Urgent banner. D8 reads these through `ClientSettings.level(for:)` and follows the defaults. Stop notifies whatever the other levels say.
- **A toggled-off suppression trigger stops counting.** `IanSuppressOnCamera` and `IanSuppressInExternalMeeting` (both default true) remove the camera or the external meeting from the suppression computation. D8 uses the same computation for the heartbeat's `suppressed` flag, so a toggled-off trigger does not set it either. Quiet hours and the principal's own pause are not toggles and always suppress. Suppression still hides all item text and holds notifications for the triggers that remain, and P0 still notifies (AGENTS.md rule 6).
- **A new agent takes the server's order from a refetch.** When `agent.updated` names an agent the store does not hold, the reducer appends it so it shows at once, and the store then fetches `GET /agents` and replaces the list. The client relies on the server's order as its display order; it sorts nothing. An agent whose event arrives while the fetch is in flight keeps that newer copy, and a snapshot that arrives first wins over the older response. Contract 1.1.1 says so on `AgentsOverview.agents`, and records that a PATCH changing nothing emits no event.

## Consequences

- Three notification keys, two suppression keys and `IanReducedMotion` join the client settings that may reach disk. All are spec 6.4 settings and carry no item content, so non-negotiable 5 holds.
- D8's ladder function takes the levels and the toggles from `ClientSettings` and does not recompute suppression.
- A principal who wants Stop quieter cannot have it. That is the spec's choice.
- If Lance changes the order of `GET /agents`, the Agents view changes with it without a client release.

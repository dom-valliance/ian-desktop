# 0001. The client is thin and holds no write power

Date: 2026-10-17
Status: Accepted

## Context

Lance's non-negotiables put every write behind the ledger, the policy engine and a deterministic executor (Lance `AGENTS.md`, rules 1 to 3). A desktop client is a new surface beside the web app and Slack. The work item model (C1, C2), units of work (C3) and the orchestrator (F1) are not built, so any logic the client copied from today's server would be wrong within weeks. Dom chose a native Swift client on 16 October 2026 (spec section 0).

## Decision

The client is thin and holds no write power. Every action is one api call. The client computes no pressure, horizon, grouping, eligibility or policy outcome; it renders what the server sends, and draws the buttons an item's `actions` list offers, in order, sending the action id back. An action marks its item pending; only the server's event moves it. No content is written to disk. Tokens are kept in the Keychain. Everything else lives in memory for the life of the process.

## Consequences

- A new behaviour on screen needs a contract field first. When a view seems to need a calculation, the contract is missing a value, and the fix belongs in Lance (DL2, DL4).
- Policy, work items and roles can change on the server without a client release, because the actions an item offers come from the server.
- Offline is read-only. There is no queue of actions to replay.
- Client tests check rendering of given states and the event path, not business rules. Lance's tests own the rules.
- The client restarts with an empty store and refetches the snapshot every launch.

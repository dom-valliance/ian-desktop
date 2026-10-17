# 0009. Contract v1 fills gaps in spec section 5

Date: 2026-10-17
Status: Accepted

## Context

Spec section 5 sketches contract v1; D1 turns it into `contract/ian-desktop.v1.yaml`. Writing it out, and reviewing it against spec section 6, showed places where the sketch would force the client to compute, sort, count or key behaviour on ids (ADR 0001), where the Swift generator cannot express the sketch, and where Lance already has its own vocabulary (read from Lance on 17 October 2026: `packages/shared/src/enums.ts`, `packages/db/src/schema/principal-state.ts`, `apps/api/src/agents/view.ts`).

Naming a field the prose of spec 5 implies (such as `Snapshot.serverTime`, `Chase.count` or a `400` response) is not a departure. These are.

## Decision

**So the client computes nothing:**

1. **Views.** The snapshot carries `views`: the sidebar counts (spec 6.2), Proposals as groups by action class, Commitments as three ordered tabs, Tasks as horizon sections of unit groups, and Alerts as severity groups with P0 first (spec 6.3). A new event, `views.updated`, replaces them whole.
2. **Today.** `/today` adds `lists`: the `now` ids in display order, this week's groups and later counts by kind, each keyed to a field column. Each field cell carries `working` beside `kind` (AGENTS.md Q16), and its `itemIds` are in display order, so selecting a pillar selects its first item.
3. **Orbit.** The Orbit block adds `nowCount` and `urgentCount` for the VoiceOver label in spec 6.1. `median` is floored at 1.
4. **Attention.** Each item carries `attention` (`ambient`, `needs_you`, `urgent`, `stop`). Several spec 6.6 triggers (risk language, a foreign decision attempt, the budget ceiling) have no field the client could map, which is the condition AGENTS.md Q17 set for moving the rung to Lance.
5. **Labels.** Open strings the cards show carry a label written by the server: `actionClassLabel`, `targetSystemLabel`, `alertKindLabel` and the evidence source's `label`.
6. **Action input.** Each `ItemAction` carries `input` (`none`, `until`, `note`). The client asks for a time or a note from this field, never from the action's id or label.
7. **Eligibility.** Settings carry `liveEligible` and `liveOpensAt` for the dry-run-to-live switch (spec 6.4, Q9). A refused change answers `422`.

**So the server settles state:**

8. **Version on actions.** The action call takes a required body with `version`, so a stale read answers `409`. `until` and `note` stay optional.
9. **Correlation.** Both `200` and `202` from an action answer `{ correlationId }`, never the item, because the client never applies a response (ADR 0001). At least one event on the item carries that id, which clears its pending mark. Spec 5.2 said the `200` returns the updated item.
10. **Event order and replay.** Item events precede the `today.updated` and `views.updated` that reflect them. An id the server does not hold, older than the window or newer than its latest event, answers `410`. `heartbeat` carries no event id and is never stored or replayed, where spec 5.5 gives every event an id.

**Shape and vocabulary:**

11. **Absent, not null, for optional references.** `Item.severity`, `ProposalDetail.confidence` and `Agent.breaker` are omitted when they do not apply, where spec 5.1 writes `severity: ... | null`. `swift-openapi-generator` 1.14.1 silently drops a property declared as `oneOf` a reference and `null`. Inline values keep `type: [..., 'null']`.
12. **One copy of each fact.** Commitment direction is the item's kind, and severity is the item's `severity`; the detail objects do not repeat them, though spec 5.3 lists both. The alert's own kind is `alertKind`, since `kind` is the discriminator.
13. **Times.** Every time is UTC with milliseconds (`2026-10-16T08:00:00.000Z`), so one date transcoder decodes them all.
14. **Lance's vocabulary.** `policyDecision` is `forbid`, `propose` or `auto`; `decisionTier` is `hard_floor`, `personal`, `organisation` or `fallback`; costs are in pounds with one ceiling, the principal's; breakers are `closed`, `open` or `half_open`; quiet hours are a pair of local `HH:MM` times; the push budget is per hour; principal status is `onboarding`, `active`, `paused` or `offboarded`.
15. **Agents.** Watchers, agents and jobs are one list with `kind`; `pausable` says whether pause and resume apply within the principal's scope (`403` otherwise).
16. **Additions to `/me`.** `contractVersion`, the tag the server implements, for the diagnostics in spec 6.4.
17. **Headers and errors.** Every operation accepts `Desktop-Client-Version`; without it a request is not version-checked. A server that does not offer `POST /handoff` answers `404`.
18. **Lists.** `GET /items` takes `state` as `open` or `to_confirm`, and pages with `cursor` and `limit` (1 to 200, default 50, as Lance pages today). The snapshot's `items` include alerts and commitments awaiting confirmation; Today excludes the latter.
19. **Session id.** The heartbeat's `deviceId` is generated at launch and held in memory, so it adds no `UserDefaults` key beyond spec 6.4.
20. **Field columns.** The field's columns are `field.units`, up to five, drawn in the order sent. Other is last when the server sends it; spec 5.4's "four units plus Other" becomes the server's choice, so a principal with fewer units or nothing ungrouped gets fewer columns, and the client never recognises Other by its id.

## Consequences

- The client renders every view, the Orbit, its VoiceOver label, actions and the mode switch from fields alone. D8 reads `attention` instead of mapping the spec 6.6 table.
- Lance's façade must produce values it does not hold today. Each is listed in [docs/companion/lance-track.md](../companion/lance-track.md) under the package that owns it.
- A new enum value is a breaking change in v1 (generated Swift enums reject unknown values), so open-ended values (`actionClass`, `targetSystem`, `alertKind`, task `status`) are strings with labels.
- Any later departure from spec section 5 adds an ADR; this one is not edited.

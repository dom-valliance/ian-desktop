# Ian desktop: a standalone Mac client for Lance

Date: 2026-10-16
For: Claude Code in a new repository, `ian-desktop`, with a small companion track in the `lance` repository
Design source: the canvas "Ian desktop presence: avatar concepts" (https://claude.ai/artifact/Xt1vNGhynLzzKFe7UTH2U8), artboards Recommended, Pillars, Scale and Ladder
Suggested home: `docs/spec.md` in `ian-desktop`, with a one-paragraph pointer in `lance/docs/plans/desktop.md`

---

## 0. What this builds, and when

A native macOS client for Lance. At rest it is the Orbit avatar in a corner of the screen. Opened, it is the expanded client with seven views: Today, Proposals, Commitments, Tasks, Alerts, Agents and Settings. It is a thin client. Lance holds every rule, every computed value and every write.

Version 0 runs on a developer's Mac from Xcode, unsigned, against a mock server in the same repository by default, with a switch to Lance dev. Apple signing, notarisation, packaging, Intune deployment, Platform SSO and Conditional Access are a fast follow (section 12).

Decisions Dom made on 16 October, which this plan follows:

- Native Swift and SwiftUI, Mac only.
- Mock server by default, with a switch to Lance dev.
- This spec is a markdown briefing for Claude Code.
- No global shortcut in version 0.
- Orbit is the resting avatar. Pillars is the hero of the Today view, not the avatar.
- The user-facing name is Ian. The API keeps Lance identifiers, per B1.

Out of scope for this track: Windows, voice, the global shortcut, Val and team scope, job authoring, Lev pages, the Ember, Sigil, Tide and Pane avatar styles, and editing a proposal's content. Each has a home elsewhere or waits for evidence.

The desktop client is not in the MVP cut proposed on 13 October. It belongs in Should, beside G2 and G3. The product owner decides its placement, and it needs a register entry, because a new client surface widens what the phase review must cover.

Read `CLAUDE.md` in `lance`, the roadmap, the foundations backlog, the playback changes briefing and this file before writing code. Write ADRs 0001 to 0006 (section 3) in `ian-desktop/docs/adr/` before the first feature commit.

---

## 1. What the client stands on in Lance

The client reads and acts through the Lance api. These parts of Lance exist today and are what the client renders:

| Lance concept | What the client shows | Notes |
|---|---|---|
| Proposals with policy decisions, expiry and confidence | Proposals view, Orbit satellites, Today | Decided through the existing decision path; confidence carries its source per ADR 0037 |
| Commitments, both directions, with evidence, chase state and the To confirm tab | Commitments view, Today | Native table; settle, snooze, chase and confirm already exist for web and Slack |
| Tasks as ontology `Task` nodes pointing at Notion and Jamie (ADR 0009) | Tasks view, Today | Completing a task is a `complete_task` proposal, never a direct write |
| Alerts P0 to P3 with dedupe keys | Alerts view, Orbit, notifications | Acknowledge and snooze |
| Agent runs, watchers, breakers, cost | Agents view | Pause and resume exist as Slack commands |
| `principal_state`: pause, mode, quiet hours, push budget, cost ceiling | Settings | Global `system_state` shown read-only |
| The ledger and correlation trail | "Open in Lance" links | The client links out; it does not render the ledger |

What Lance does not have yet, and the client needs, is listed as the companion track in section 9: a stable versioned contract for an external client, a Today aggregation, a desktop event stream, surface sessions and arbitration, and a minimum client version.

The work item model (C1, C2) and units of work (C3) are not built. The contract in section 5 abstracts over them with one item envelope, so the client does not change when `work_items` lands.

---

## 2. Repository layout

```
ian-desktop/
  App/                         Xcode project, macOS app target "Ian"
  Packages/IanKit/             Swift package, all logic and views
    Sources/
      Contract/                generated from contract/ian-desktop.v1.yaml
      Client/                  HTTP, SSE, environment profiles
      Auth/                    dev token provider, PKCE loopback for Lance dev
      Store/                   observable state, reducers for snapshot and events
      Surface/                 Orbit and Pillars renderers, window model
      Features/                Today, Proposals, Commitments, Tasks, Alerts, Agents, Settings
      Attention/               notifications, attention ladder, suppression
    Tests/
  contract/ian-desktop.v1.yaml OpenAPI 3.1, the source of truth for v1
  mock/                        Node 22, TypeScript, Fastify mock server
  docs/spec.md                 this file
  docs/adr/
  scripts/dev.sh               starts the mock and opens the app
  .github/workflows/           macOS build and test, mock tests, contract lint
```

Toolchain: Xcode 16, Swift 6 with strict concurrency, macOS 14 minimum. Dependencies are kept to:

- `swift-openapi-generator`, `swift-openapi-runtime` and `swift-openapi-urlsession`
- `swift-snapshot-testing`, for tests only

MSAL arrives with the fast follow. Lint with `swift-format`. The mock uses pnpm, Fastify, Zod and an OpenAPI response validator in its tests.

---

## 3. ADRs to write first

**0001. The client is thin and holds no write power.** Every action is one api call. The client computes no pressure, horizon, grouping, eligibility or policy outcome; it renders what the server sends. No content is written to disk. Tokens are kept in the Keychain. Everything else lives in memory for the life of the process.

**0002. The contract is owned here and versioned.** `contract/ian-desktop.v1.yaml` is the source of truth for v1. Swift models and the mock are generated from it or validated against it. Lance implements a `/desktop/v1` façade that conforms to a pinned tag of the contract, checked by a conformance test in Lance CI. A breaking change means `v2`, never an edit to `v1`.

**0003. The mock server is the default environment.** The app starts against the mock unless a profile says otherwise. The mock serves invented data only. A debug build compiles two profiles, `mock` and `lance-dev`. No production profile exists until the fast follow, and then only in release builds.

**0004. Rendering stays in SwiftUI.** Orbit and Pillars are drawn with SwiftUI `Canvas` inside `TimelineView`, using the same 2.5D projection as the canvas mock. Rendering pauses whenever the view is hidden, occluded or suppressed. SceneKit or Metal is used only if the performance budget in section 6.9 fails, and that change needs its own ADR.

**0005. Window model.** The Orbit is a borderless, non-activating `NSPanel` at `.floating` level. It joins all Spaces and appears over full-screen apps as an auxiliary. It is click-through outside its hit area. The expanded client is a separate `NSPanel` that can become key, so text fields work. It is anchored to the Orbit's corner and closes on Escape. A `MenuBarExtra` mirrors the count and offers Open, Pause me, Settings and Quit, so Ian is reachable when the Orbit is hidden.

**0006. Privacy on screen.** Every window sets `sharingType = .none`. Suppression (section 6.5) hides all item text and holds notifications, while the Orbit keeps showing state. Screen-sharing protection cannot be switched off in Settings.

---

## 4. Data flow

1. Launch, then resolve the environment profile and obtain a token (section 8).
2. `GET /desktop/v1/me`. If the server's `minClientVersion` is above the app's version, show the upgrade state and stop.
3. `GET /desktop/v1/snapshot` fills the store in one call: Today, open items of every kind, alerts, agents and principal settings.
4. Open `GET /desktop/v1/events` (SSE) with the snapshot's `cursor` as `Last-Event-ID`. Apply events to the store in order.
5. If the stream drops, reconnect with backoff and the last event id. If the server answers `410 Gone` (replay window exceeded), refetch the snapshot. While disconnected for more than 60 seconds, poll the snapshot every 60 seconds and mark the data with its age.
6. Actions are `POST` calls. The client marks the item as pending, never as done. The server's event moves it to its new state. On an error the pending mark clears and the error shows on the item.
7. Every 60 seconds, and on any change, the client posts a session heartbeat for arbitration (section 6.6).

Actions are disabled while offline. There is no action queue, because acting on stale state is worse than waiting.

---

## 5. Contract v1

All paths sit under `/desktop/v1`. Bearer authentication is required on every path. Errors use `application/problem+json`. `426` means the client is below the minimum version. `409` means the item changed since it was read, and the body carries the current item.

### 5.1 The item envelope

Every proposal, commitment, task and alert reaches the client as an `Item`:

```yaml
Item:
  id: string                      # stable, prefixed by kind, e.g. prop_01J..., cmt_..., task_..., alrt_...
  kind: proposal | commitment_by | commitment_to | task | alert
  title: string                   # display text, already in the principal's voice rules
  meta: string                    # one line: counterparty, due, source
  unit: { id: string, name: string }      # unit of work; see 5.4
  horizon: now | week | later
  pressure: number                # 0 to 1, computed by the server; drives pillar height
  dueAt: string | null            # ISO 8601
  severity: P0 | P1 | P2 | P3 | null      # alerts only
  working: boolean                # an agent is acting on it now
  version: integer                # for 409 checks
  actions: [ { id: string, label: string, style: primary | secondary | quiet, confirm: string | null } ]
  detail: { ... }                 # kind-specific, see 5.3
  links: { lance: string, source: string | null }   # web page and system of record
```

The server decides which actions an item offers. The client draws the buttons it is given, in order, and sends the action id back. This is how version 0 stays correct as policy, work items and roles change.

### 5.2 Endpoints

| Method and path | Purpose |
|---|---|
| `GET /me` | Principal id, display name, status, mode, time zone, `minClientVersion`, `capabilities` (feature flags such as `handoff`) and server time |
| `GET /snapshot` | Today, all open items, alerts, agents, principal settings, and a `cursor` for the event stream |
| `GET /today` | Orbit block (up to five `now` item ids, `overflow` count, `load`, `median`, `working`), field block (up to five units, three horizons, cells with item ids and aggregate pressure), and context (`inExternalMeeting`, `quietHours` active) |
| `GET /items?kind=&horizon=&state=` | Filtered lists for the views; paged with a cursor |
| `GET /items/{id}` | One item with full detail |
| `POST /items/{id}/actions/{actionId}` | Run an action; optional body `{ until?: string, note?: string }` for snooze and chase; returns the updated item or `202` with a correlation id when a proposal is raised |
| `POST /handoff` | "Hand to Ian": `{ itemId, instruction? }`; returns a correlation id. Only offered when `capabilities.handoff` is true |
| `GET /agents` | Watchers, agents and jobs with state, last run, next run, breaker state, cost today and the principal's ceiling |
| `POST /agents/{id}/pause`, `POST /agents/{id}/resume` | Within the principal's own scope |
| `GET /settings`, `PATCH /settings` | Principal settings: quiet hours, push budget, mode, own pause; global state read-only |
| `GET /events` | SSE stream; see 5.5 |
| `POST /sessions` | Heartbeat: `{ deviceId, clientVersion, active, suppressed, idleSeconds }` |

### 5.3 Detail by kind

- **Proposal.** Action class, target system, summary of the change, policy decision and the tier that produced it, confidence with its source (`lev_trusted`, `lev_untrusted`, `self_report`) and `expiresAt`. Editing is out of scope; the `lance` link opens the editor.
- **Commitment.** Direction, counterparty, the verbatim evidence quote and its source, chase state and last chase, and whether it sits in To confirm.
- **Task.** Source (`notion` or `jamie`), assignee, status, project or unit, and due date. Its "Done" action raises a `complete_task` proposal. The policy engine decides whether that auto-executes.
- **Alert.** Kind, severity, raised time, dedupe key, related item ids and a short explanation.

### 5.4 Server-side computation the client relies on

- **Pressure.** A 0 to 1 value from due time, severity, overdue state and proposal expiry. The formula lives in Lance and is versioned there.
- **Horizon.** `now` means due today, overdue, P0 or P1, or a proposal expiring today. `week` means due within seven days. Everything else is `later`.
- **Unit of work.** Until C3 lands, grouping falls back in order. First the project from an `ABOUT` edge. Then the counterparty organisation. Then "Other". The field shows the four units with the highest summed pressure plus "Other".
- **Orbit selection.** Up to five `now` items ordered by pressure, with the remainder in `overflow`.
- **Load and median.** `load` is the count of open items. `median` is the principal's 30-day median of daily open counts, from a nightly job inside `withPrincipal`.

### 5.5 Events

Event types: `item.upserted`, `item.removed`, `today.updated`, `alert.raised`, `alert.cleared`, `agent.updated`, `settings.updated`, `client.deprecated` and `heartbeat` every 25 seconds.

- Each event carries a monotonically increasing id per principal.
- The server keeps 24 hours of replay.
- Payloads carry whole objects, never patches, so a missed event cannot corrupt the store.

---

## 6. Client behaviour

### 6.1 Orbit

As drawn on the Scale and Recommended artboards.

- **Satellites.** Satellites are the Orbit's `now` items, coloured by kind, with a "+n" chip for `overflow`. Alerts are drawn larger with a pulsing light rim.
- **Ring.** The inner ring arc shows `load / median`. An outer peach arc shows load above the median.
- **Core.** The core breathes blue while any item is `working`.
- **Position.** It sits bottom-right of the main display with a 16-point inset. It can be dragged to any corner, and the corner is remembered locally.
- **Click.** Clicking toggles the expanded client.
- **Hover.** Hovering shows the top item's title, unless suppressed.
- **Right-click.** Right-clicking opens the same menu as the menu bar extra.
- **VoiceOver.** The label reads "Ian, three need you now, forty-one open, one urgent".

### 6.2 Expanded client

- **Size and anchoring.** The default size is 1,040 by 720 points, with a minimum of 880 by 600. It is anchored above the Orbit's corner.
- **Navigation.** A sidebar lists the seven views with counts. The header shows the environment when it is not `mock`, and the data's age when stale.
- **Memory.** It remembers the last view. Every view works with the keyboard alone.

### 6.3 The views

- **Today.** The Pillars field, as on the Pillars artboard:
  - columns are units of work
  - rows are horizons, with Now at the front
  - height is pressure
  - colour is kind
  - rising light means `working`
  - a settled item's pillar sinks

  Below the field sits the Now list with its actions, This week as rolled-up groups, and Later as counts linking to the relevant view. Selecting a pillar selects its list row and the reverse. The list is the accessible path; the field is never the only way to reach an item.
- **Proposals.** Pending proposals grouped by action class, soonest expiry first. Each card shows the summary, target system, decision tier, confidence with its source label, and expiry. Approve and Reject come from the item's actions. Edits go through Open in Lance.
- **Commitments.** Three tabs: Owed by me, Owed to me, and To confirm. Cards show the counterparty, due date, evidence quote and chase state. Actions are settle, snooze, chase, confirm and dismiss, as the server offers them.
- **Tasks.** Grouped by horizon, then unit, with a source badge. Done raises a proposal and shows the result when the event arrives. Open in source opens Notion or Jamie.
- **Alerts.** Grouped by severity, with P0 pinned. Actions are acknowledge and snooze.
- **Agents.**
  - A table of every watcher, agent and job, showing state (running, idle, paused, breaker open, failed), last run, next run, cost today and share of the ceiling.
  - Pause and resume within the principal's own scope.
  - A banner when the global kill switch is on, read-only.
- **Settings.** Two sections, described in 6.4.

### 6.4 Settings

**Client settings, stored locally in `UserDefaults`:**

- Corner.
- Motion: on, or reduced. The system's Reduce Motion setting forces reduced.
- Notification level per attention rung.
- Suppression toggles for a live camera and for external meetings.
- Launch at login. This is best effort in version 0, since an unsigned build may not register.
- Environment profile, which signs out and clears the store on change.
- Sign out.
- Diagnostics: app version, contract version, event lag, last snapshot time and a copy-to-clipboard report with ids only.

**Principal settings, read and written through `PATCH /settings`:**

- Quiet hours.
- Push budget.
- Mode. The switch from dry run to live is enabled only when the server reports eligibility, and it asks for confirmation.
- Own pause.

Time zone, cost ceiling and global state are read-only.

### 6.5 Suppression

Suppression is active when any of these holds:

- The camera is live, detected through the CoreMediaIO "device running somewhere" property.
- `today.context.inExternalMeeting` is true.
- Quiet hours are active.
- The user has paused notifications from the menu.

While suppressed, the Orbit shows state with no text, hover shows nothing, and notifications follow the ladder in 6.6. Screen-share detection has no public API. `sharingType = .none` is the defence, and section 13 records the gap.

### 6.6 Attention ladder

As on the Ladder artboard.

| Rung | Triggers | Orbit | Notification |
|---|---|---|---|
| Ambient | Agent runs, P3 | State only | None |
| Needs you | Pending proposals, commitments due today, P2 | Grows and holds colour | None |
| Urgent | P1, risk language, proposal expiring within 15 minutes | One-line whisper for eight seconds | Banner with the item's actions |
| Stop | P0, kill switch, budget ceiling, foreign decision attempt | The panel opens on the next pointer movement | Always |

Local notifications use `UNUserNotificationCenter`, with categories built from the item's actions. Notification text is hidden while suppressed. Time-sensitive delivery needs an entitlement and moves to the fast follow.

The heartbeat in section 4 lets Lance decide delivery. The desktop delivers while active. Slack takes over after ten idle minutes, or when no session is alive. The rule is enforced in Lance (DL5); the client only reports.

### 6.7 Offline and errors

- Offline shows a banner and disables actions. The data stays visible with its age.
- `426` shows an upgrade state with no data.
- `401` clears the token and asks the user to sign in.
- `409` replaces the item and tells the user it changed.

### 6.8 Accessibility

- Every control is a real control, with VoiceOver labels on the Orbit and every pillar's list row.
- Colour is never the only signal: alerts carry a rim, and urgency also changes size.
- Reduce Motion stops the ripple, the turn and the breathing, and replaces growth with a fade.
- Full keyboard navigation works inside the expanded client.

### 6.9 Performance budget

- Idle with only the Orbit visible: under 1% CPU on an M1 and under 150 MB resident.
- Expanded with Pillars animating: under 15% CPU and 60 frames per second at the default size.
- One SSE connection per app.
- Rendering stops when the expanded client is hidden or suppressed.

---

## 7. Mock server

- **Stack.** Node 22, TypeScript, Fastify and Zod schemas generated from the contract. Every response is validated against the OpenAPI document in tests.
- **Data.** Fixtures are invented, with placeholders such as `[CLIENT]` and `[PERSON]`. No real names, mail or clients appear.
- **Scenarios.** Selected with `POST /__mock/scenario`:

| Scenario | What it simulates |
|---|---|
| `quiet` | Three open items |
| `normal` | About 18 open items, one urgent |
| `overloaded` | About 42 open items, above the median |
| `incident` | A P0 and the kill switch on |
| `offline` | Drops the stream and refuses requests |
| `stale-client` | Answers `426` |
| `external-meeting` | Sets the meeting context |

- **Events.** `POST /__mock/emit` pushes any event type. A CLI wraps it: `pnpm mock emit alert --severity P1`.
- **Clock.** `POST /__mock/clock` sets or advances mock time, so pressure and horizons change on demand.
- **Actions.** These behave like Lance. Settle moves the item and emits events. Approve emits a `202` with a correlation id, then an `item.removed`. Task Done raises a mock proposal.
- **Auth.** The mock accepts any `Bearer dev-...` token.
- **Running it.** `pnpm --dir mock dev` listens on port 4317. `scripts/dev.sh` starts it and opens the app.

---

## 8. Environments and sign-in

| Profile | Base URL | Sign-in |
|---|---|---|
| `mock` (default) | `http://localhost:4317/desktop/v1` | None; the app sends `Bearer dev-local` |
| `lance-dev` | The dev api host from the Lance runbook's known-values table, plus `/desktop/v1` | Entra authorisation code with PKCE, through the system browser and a loopback redirect on `http://localhost:<random port>` |

The `lance-dev` sign-in needs a new Entra public client registration, "Ian Desktop (dev)". It is configured as follows:

- a loopback redirect
- delegated access to the Lance api scope
- the `Lance.User` role check that the api already applies

Device code flow is not used, because tenant policy commonly blocks it. Tokens live in the Keychain as generic password items, which works for unsigned builds. MSAL with the Enterprise SSO plug-in replaces this in the fast follow.

The profile is chosen in Settings or with the launch argument `-IanEnvironment lance-dev`. Changing it signs out and clears the store. The expanded client's header shows "Lance dev" whenever that profile is active.

---

## 9. Companion track in `lance`

Lance work packages the `lance-dev` switch depends on. Each one lands behind `FF_DESKTOP_API`, default off.

| # | Package | Depends on | Size |
|---|---|---|---|
| DL1 | `/desktop/v1` façade on the api: bearer from the new public client, `Lance.User` role, principal from `oid`, `withPrincipal` on every call, problem+json errors, `minClientVersion` from config | Phase 5 | 1.5 days |
| DL2 | Today aggregation: pressure, horizon, interim unit grouping, Orbit selection, nightly per-principal median job in the registry | DL1 | 1.5 days |
| DL3 | Desktop event stream: per-principal ids, 24-hour replay, whole-object payloads, heartbeat | DL1 | 1 day |
| DL4 | Action mapping: each item's offered actions resolved to existing procedures; task Done to a `complete_task` proposal; `surface: 'desktop'` on every ledger payload; no new ledger kinds | DL1 | 1 day |
| DL5 | Surface sessions table under RLS, arbitration in the delivery path (desktop active wins, Slack after ten idle minutes or no session), push budget shared across surfaces | DL3 | 1 day |
| DL6 | Conformance test in CI against the contract at a pinned `ian-desktop` tag | DL1 to DL4 | 0.5 days |

`POST /handoff` stays unimplemented in Lance until the orchestrator (F1, F2) can receive it. `capabilities.handoff` is false in `lance-dev` until then, and the client hides the button.

---

## 10. Work packages in `ian-desktop`

| # | Package | Depends on | Size |
|---|---|---|---|
| D1 | Repository, Xcode project, IanKit package, CI on a macOS runner, contract v1 draft, ADRs 0001 to 0006 | none | 1.5 days |
| D2 | Mock server: contract validation, fixtures, scenarios, emit, clock, actions | D1 | 1.5 days |
| D3 | Client core: generated models, HTTP, SSE with replay and backoff, store, environment profiles, mock auth, PKCE loopback for `lance-dev` | D1 | 2 days |
| D4 | Window model, Orbit, menu bar extra, suppression | D3 | 2 days |
| D5 | Expanded client shell and Today with Pillars | D4 | 2.5 days |
| D6 | Proposals, Commitments, Tasks and Alerts views with actions | D5 | 2.5 days |
| D7 | Agents and Settings | D5 | 1.5 days |
| D8 | Notifications and the attention ladder, heartbeat | D6 | 1 day |
| D9 | Accessibility pass, performance budget check, snapshot tests of every Orbit and pillar state, local run guide, demo against the mock and against Lance dev | all | 1.5 days |

This totals about 16 days in `ian-desktop` and about 6.5 days in `lance`. One Swift engineer and one engineer on the Lance api can run the two tracks in parallel. D1 to D9 complete against the mock without any Lance package merged.

---

## 11. Acceptance criteria

| Criterion | Evidence expected |
|---|---|
| The app runs locally with no Apple setup | A fresh clone, `scripts/dev.sh`, and the app shows the `normal` scenario within ten seconds on an unsigned debug build |
| The contract is the single source | Swift models are generated from the YAML; the mock's tests validate every response against it; DL6 passes in Lance CI |
| The client holds no logic | Code review finds no pressure, horizon, grouping or eligibility computation in IanKit; every button comes from an item's `actions` |
| All seven views work | Each view renders every mock scenario; every action in the mock round-trips and the item updates from the event, not from the client |
| Orbit and Pillars match the design | Snapshot tests for `quiet`, `normal`, `overloaded` and `incident` match the Scale, Pillars and Recommended artboards in encoding |
| The stream recovers | Killing the mock's stream and restoring it replays missed events; a gap beyond the window triggers a snapshot refetch; data shows its age while offline |
| Suppression holds | With the camera live, or in `external-meeting`, no item text appears on the Orbit or in notifications, and P0 still notifies |
| Windows stay out of screen captures | A screen recording taken with the system screenshot tool shows no Ian windows |
| The switch to Lance dev works | With DL1 to DL4 merged, Dom signs in through the browser, sees his own items, settles a commitment, and the ledger shows the event with `surface: 'desktop'` |
| Arbitration works | With DL5 merged, an alert raised while the app is active reaches the desktop and not Slack; after ten idle minutes the next one reaches Slack |
| The budget holds | Instruments traces for idle and expanded meet section 6.9 |
| Accessibility holds | VoiceOver reaches every item and action through the lists; Reduce Motion stops all animation |

---

## 12. Fast follow: Apple and Intune

Not in version 0. Each item below has its own small package after D9.

- **Apple Developer Program, organisation type.** Gives the Developer ID Application and Developer ID Installer certificates. The hardened runtime is enabled.
- **CI release workflow.**
  - Sign, build the `.pkg` with `productbuild`, sign the installer, notarise with `notarytool` and staple.
  - Certificates and the notary key live in a dedicated Key Vault, read through OIDC federation by the release workflow only.
- **Production profile.** Added to release builds only.
- **MSAL with the Enterprise SSO plug-in, and Platform SSO where deployed.** Replaces the loopback flow.
- **Conditional Access.** The Ian Desktop client requires a compliant device.
- **Intune deployment.**
  - The app as a macOS PKG app, Required for `Lance Users`, deployed in rings.
  - A managed preferences profile carrying the api URL, tenant id and client id.
  - A Notifications profile.
  - A Managed Login Items profile by Team ID.
- **Time-sensitive notification entitlement**, for the Stop rung.
- **Governance.** The app enters the ISO 27001 asset register. Signing key custody is recorded. A register entry covers the new surface.

---

## 13. Open questions and defaults

| # | Question | Default in force |
|---|---|---|
| Q1 | Minimum macOS | 14 |
| Q2 | Bundle identifier | `ai.valliance.ian.desktop`, with `.dev` for debug builds |
| Q3 | Who owns the contract | `ian-desktop`, tagged per release; Lance pins a tag |
| Q4 | Proposal editing in the desktop | No; Open in Lance |
| Q5 | Unit grouping before C3 | Project, then organisation, then Other; four units plus Other |
| Q6 | Load baseline | The principal's 30-day median of daily open counts |
| Q7 | Polling fallback | Every 60 seconds after 60 seconds without the stream |
| Q8 | Hand to Ian before the orchestrator | Shown in the mock; hidden in `lance-dev` through `capabilities` |
| Q9 | Going live from the desktop | Only when the server reports eligibility, with confirmation |
| Q10 | Other avatar styles | Orbit only in version 0 |
| Q11 | Screen-share detection | None beyond `sharingType = .none`; revisit if Apple publishes an API, or if a meeting-app integration is built |

---

## 14. Risks

- **Contract drift.** The client and Lance move at different speeds. The generated models, the mock's validation and DL6 make drift a failing build rather than a runtime surprise.
- **Building ahead of C2 and F1.** The item envelope and server-offered actions absorb the work item model and the orchestrator. If either changes the envelope, that is `v2`, and the mock carries both versions during the switch.
- **Content on a shared screen.** Without a public screen-share signal, `sharingType` is the main defence, and recent macOS releases have weakened it against some capture paths. The suppression list reduces the exposure; it does not remove it. Treat this as the top risk in the phase review.
- **Unsigned builds handling real data.** The `lance-dev` profile on an unsigned build reads Dom's dev data. Debug builds are for engineers and Dom only, carry no production profile, and keep tokens in the Keychain. The fast follow closes the gap with Conditional Access on a compliant device.
- **Distraction.** An avatar that is always present can become noise. The attention ladder, the suppression rules and the shared push budget exist to stop that. The pilot measures how often Dom opens the client and how often he dismisses without acting.
- **SwiftUI rendering cost.** If `Canvas` misses the budget, the ADR 0004 fallback to SceneKit costs about two days. D9 measures this before any polish.

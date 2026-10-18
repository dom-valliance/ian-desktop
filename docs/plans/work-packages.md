# Work packages

D1 to D9 from spec section 10, expanded into what to build and how to prove it. Run them in Claude Code from the repository root. `/package D<n>` loads an entry, checks its dependencies against [the phase log](../adr/0000-phase-log.md) and starts the branch.

```
D1 ─┬─ D2 ───────────────────────────┐
    └─ D3 ── D4 ── D5 ─┬─ D6 ── D8 ──┼── D9
                       └─ D7 ────────┘
```

D2 and D3 can run in parallel after D1, as can D6 and D7 after D5. For parallel sessions, create each git worktree by hand from the working branch, tell Dom the paths, and pin each session to its path (a Lance lesson: tool-made worktrees started from a stale `main`).

Every package is done only when all of these pass by exit code, in addition to its own list:

- The commands in `.github/workflows/` (swift-format, build, test, xcodebuild, the mock's lint, typecheck and test, the contract lint)
- No em dashes, en dashes or real data in the diff
- An ADR for every deviation from the spec
- The phase log entry: date, branch, commit range, commands and exit codes, the spec section 11 criteria evidenced

## How to start

Open Claude Code in this folder (`~/workspace/desktop-ian`) and paste:

> Read CLAUDE.md, then run `/package D1`. This folder has never been under git: start with `git init -b main` and commit the prepared workspace as it stands as `chore: prepare workspace` before any D1 change, then branch for D1.

After D1, each package starts with `/package D<n>` and nothing else.

---

## D1. Repository, project, package, CI, contract draft

Branch `feat/d1-foundations`. Depends on nothing. About 1.5 days.

Read: spec sections 2, 3, 5 and 13; ADRs 0001 to 0006; AGENTS.md Q14 to Q16; `contract/README.md`; `Packages/IanKit/README.md`.

Build:

- `Packages/IanKit/Package.swift`: Swift tools 6.0, macOS 14, one target per `Sources/` folder with the dependency graph in `Packages/IanKit/README.md`, one test target per source target. Dependencies: `swift-openapi-generator`, `swift-openapi-runtime`, `swift-openapi-urlsession`, and `swift-snapshot-testing` for tests only. Remove the `.gitkeep` files as folders gain sources.
- `App/project.yml` and the generated `App/Ian.xcodeproj` (Q15): app target `Ian`, bundle identifiers per AGENTS.md, macOS 14, Swift 6 language mode, Sign to Run Locally, `LSUIElement` true (Q14). The app launches to a placeholder menu bar extra reading "Ian". Write ADR 0007 for the XcodeGen choice.
- `contract/ian-desktop.v1.yaml`, OpenAPI 3.1, every endpoint in spec 5.2 with bearer security on all. `Item` as in 5.1 with `kind` including `task`, `detail` as a `oneOf` keyed on kind (5.3), the `confidenceSource` enum from E1, `problem+json` errors, the `409` body carrying the current item, `426`. The `/today` field cell carries `kind` (Q16). `GET /events` as `text/event-stream` with each event type's payload schema in `components`. Examples use placeholders only.
- Generator wiring for the `Contract` target, by symbolic link or a committed CLI run (AGENTS.md gotcha). Record which in the phase log.
- `.swift-format` with the default rules, line length 100.
- Workflows `macos.yml`, `mock.yml` (it may only install and run an empty test until D2) and `contract.yml`, actions pinned to commit SHAs.

Done when:

- A fresh clone builds with `xcodebuild` on a Mac with no Apple account signed in to Xcode.
- `swift test --package-path Packages/IanKit` runs a test that decodes a sample `Item` of each kind through the generated types.
- The contract lint passes, and every endpoint and event in spec section 5 appears in the document (list them in the phase log).
- `git tag contract-v1.0.0` is created locally on the merge commit once Dom has merged; Dom pushes it.

## D2. Mock server

Branch `feat/d2-mock`. Depends on D1. About 1.5 days.

Read: spec sections 4, 5 and 7; ADR 0003; `mock/README.md`.

Build:

- `mock/` as a pnpm package (`packageManager` field, Node 22): strict TypeScript, ESLint, Prettier, vitest, Fastify, Zod. Zod schemas generated from the contract; record the generator in the phase log.
- Every endpoint in 5.2 under `/desktop/v1`, accepting any `Bearer dev-...` token and refusing others with `401`.
- Fixtures for the seven scenarios in spec 7, invented, with `[CLIENT]` and `[PERSON]` placeholders: `quiet` (3 open), `normal` (about 18, one urgent), `overloaded` (about 42, above the median), `incident` (a P0 and the kill switch on), `offline` (drops the stream, refuses requests), `stale-client` (`426`), `external-meeting` (sets the meeting context).
- The event stream: per-principal monotonic ids, 24 hours of replay from `Last-Event-ID`, `410` for an id older than the window or newer than the latest event, whole-object payloads, item events before the `today.updated` and `views.updated` that reflect them, `heartbeat` every 25 seconds with no id and no replay (ADR 0009).
- Actions that behave like Lance: every action answers `{ correlationId }` and at least one event on the item carries it; settle answers `200` and moves the item by its events; approve answers `202`, then emits `item.removed`; task Done answers `202` and raises a mock proposal; an action whose `input` is `until` or `note` takes that field; a stale `version` answers `409` with the current item.
- `POST /__mock/scenario`, `POST /__mock/emit`, `POST /__mock/clock`, and `GET /__mock/sessions` (the heartbeats received, for D8). The CLI `pnpm mock emit alert --severity P1`.
- `scripts/dev.sh`, first half: start the mock on 4317 and wait until it answers.

Done when:

- `pnpm --dir mock lint`, `typecheck` and `test` pass.
- A test calls every endpoint in every scenario and validates each response against the contract.
- A test disconnects, emits five events, reconnects with `Last-Event-ID` and receives the five in order; a test past the replay window receives `410`.

## D3. Client core

Branch `feat/d3-client-core`. Depends on D1 (and D2 for its integration tests). About 2 days.

Read: spec sections 4, 5, 6.7 and 8; ADRs 0001 to 0003; AGENTS.md errata E2 and E3.

Build:

- `Client`: every request through `URLSessionConfiguration.ephemeral`; environment profiles `mock` and `lance-dev` (base URL from E3, tenant id, the desktop client id and the Lance api scope as configuration, never literals in views); `-IanEnvironment` launch argument.
- `Auth`: the `dev-local` token for the mock; Entra authorisation code with PKCE through the system browser and a loopback listener on a random `localhost` port; tokens in the Keychain as generic passwords; sign-out clears them.
- The SSE reader: `Last-Event-ID` resumption, backoff with jitter up to 30 seconds, `410` triggers a snapshot refetch, 60-second snapshot polling after 60 seconds without the stream, stopping when it returns.
- `Store`: an `@Observable`, `@MainActor` store; applies a snapshot, then events in id order, `today.updated` and `views.updated` included; ignores a repeated id; replaces whole objects; marks an item pending on an action, clears the mark when an event carrying the action's `correlationId` arrives, and clears it with an error on failure; handles `401`, `409`, `426` as spec 6.7 says; refuses to start below `minClientVersion` from `GET /me`.
- The OpenAPIRuntime configuration and the SSE decoding described in the AGENTS.md gotchas (UTC millisecond times, unknown event types skipped).
- A temporary debug list in the menu bar extra showing open items and the data's age, removed in D5.

Done when:

- Unit tests cover the reducer (order, repeats, replacement, removal, pending and error marks) and the SSE parser, using a stubbed `URLProtocol`.
- An integration test run with the mock up (`scripts/dev.sh --mock-only`, then `IAN_MOCK_URL=http://localhost:4317 swift test --package-path Packages/IanKit --filter Integration`; without the variable the suite is skipped) shows the `normal` scenario arriving, an emitted event applied, and recovery after the stream is killed.
- With the `lance-dev` profile the app opens the browser for sign-in and, until Lance DL1 lands, fails with a message naming the missing scope (E2).

## D4. Window model, Orbit, menu bar extra, suppression

Branch `feat/d4-orbit`. Depends on D3. About 2 days.

Read: spec sections 6.1, 6.5 and 6.8; ADRs 0004 to 0006; [design README](../design/README.md), Orbit section; the Scale and Recommended artboards.

Build:

- Add `swift-snapshot-testing` to `Package.swift` for the snapshot test targets (deferred from D1, which had no snapshot test and no XCTest on its machine).
- One window factory in `Surface` that sets `sharingType = .none` on everything it makes.
- The Orbit panel per ADR 0005: borderless, non-activating, floating, all Spaces, full-screen auxiliary, click-through outside the avatar. Bottom-right of the main display with a 16-point inset; draggable to any corner, remembered in `UserDefaults`.
- The Orbit renderer: `Canvas` in `TimelineView`, a pure function of the `/today` Orbit block, time and the motion setting, paused when hidden or suppressed.
- Click toggles an empty expanded panel; hover shows the top item's title unless suppressed; right-click opens the menu bar extra's menu.
- The menu bar extra with the count and Open, Pause me, Settings and Quit.
- Suppression: the camera's "running somewhere" property through CoreMediaIO, `today.context.inExternalMeeting`, quiet hours, the user's pause.
- The VoiceOver label from spec 6.1, read from the Orbit block's `nowCount`, `load` and `urgentCount`.

Done when:

- Snapshot tests of the Orbit for `quiet`, `normal`, `overloaded` and `incident`, with motion on at a fixed time and with motion off.
- A test asserts `sharingType == .none` on every window the app opens.
- Suppression tests: with each trigger set, no item text reaches the Orbit or its hover.
- The phase log records a manual check: the Orbit stays visible across Spaces and over a full-screen app, and clicks beside it reach the app beneath.

## D5. Expanded client and Today

Branch `feat/d5-today`. Depends on D4. About 2.5 days.

Read: spec sections 6.2, 6.3 (Today) and 6.8; ADR 0004; the design README's Pillars and list sections; the Pillars and Recommended artboards.

Build:

- The expanded panel, 1,040 by 720 points by default and 880 by 600 at least, anchored above the Orbit's corner, closing on Escape. A sidebar of the seven views with counts; the header names the environment when it is not `mock` and the data's age when stale; the last view is remembered.
- Today: the Pillars field per the design README, with the Now list and its actions below, This week as rolled-up groups and Later as counts linking to their views. Selecting a pillar selects its row and the reverse.
- Pillars sink when the server's event arrives; Reduce Motion replaces growth with a fade; rendering stops when the panel hides. D3's store deletes an item on `item.removed`, so D5 adds a short-lived record of removed items with their `outcome` line for the sinking pillar and the settled row.
- Remove the D3 debug list.

Done when:

- Snapshot tests of the field for the four scenarios, at a fixed time with motion on and with motion off.
- Tests of selection both ways, and of a pillar sinking after `item.removed` and not after the click.
- The phase log records a keyboard-only pass and a VoiceOver pass through Today reaching every item from the list.

## D6. Proposals, Commitments, Tasks and Alerts

Branch `feat/d6-views`. Depends on D5. About 2.5 days.

Read: spec sections 5.3, 6.3 and 6.7; ADR 0001; the Context artboard for cards.

Build:

- Every view draws the groups, order and sidebar counts in `views` as sent (ADR 0009); the client groups and sorts nothing.
- Proposals in their action-class groups, with summary, target system label, decision tier, confidence and its source label, expiry, and Open in Lance.
- Commitments in the three tabs (Owed by me, Owed to me, To confirm) showing counterparty, due date, evidence quote and chase state.
- Tasks in their horizon sections and unit groups, with a source badge and Open in source.
- Alerts in their severity groups, P0 first and pinned.
- One action component for every view: it draws `actions` in order, asks the `confirm` text when present, asks for a time or a note when the action's `input` says so, marks the item pending, and shows a `409` change or an error on the item.
- "Hand to Ian" with an optional instruction, shown only when `capabilities.handoff` is true.

Done when:

- Each view renders every mock scenario, and every action the mock offers round-trips with the item moving on the event, not on the click.
- A test renders an item whose actions have invented ids and labels and finds exactly those buttons, in order.

## D7. Agents and Settings

Branch `feat/d7-agents-settings`. Depends on D5. About 1.5 days.

Read: spec sections 6.3 (Agents) and 6.4; ADR 0003.

Build:

- Agents: a table of watchers, agents and jobs with state, last run, next run, cost today and share of the ceiling; pause and resume within the principal's own scope; a read-only banner when the global kill switch is on. D3's store appends an agent first seen in `agent.updated` at the end of its list, so D7 decides with the server how a new agent is ordered.
- Settings, client side, in `UserDefaults`: corner, motion, notification level per rung, the two suppression toggles, launch at login (best effort through `SMAppService`), environment profile (changing it signs out and clears the store), sign out, and diagnostics (app version, contract version, event lag, last snapshot time, copy report with ids only).
- Settings, principal side, through `PATCH /settings`: quiet hours, push budget, own pause, and mode, whose dry-run-to-live switch is enabled only when the server reports eligibility and asks for confirmation. Time zone, cost ceiling and global state are read-only.

Done when:

- Each setting round-trips against the mock and survives a relaunch where it should.
- A test reads the diagnostics report from the `normal` scenario and finds no item title in it.

## D8. Notifications, the attention ladder and the heartbeat

Branch `feat/d8-attention`. Depends on D6. About 1 day.

Read: spec sections 4 (step 7), 6.5 and 6.6; AGENTS.md Q17; the Ladder artboard.

Build:

- The behaviour of each rung from the spec 6.6 table, driven by the item's `attention` from the server (Q17, ADR 0009), as one pure function.
- Local notifications through `UNUserNotificationCenter`, with categories built from the item's actions. Urgent shows a banner with the item's actions and an eight-second whisper by the Orbit. Stop opens the expanded panel on the next pointer movement and always notifies. Text is hidden while suppressed; P0 still notifies.
- The session heartbeat to `POST /sessions` every 60 seconds and on any change: device id, client version, active, suppressed, idle seconds.

Done when:

- Tests of the behaviour for every rung of the 6.6 table.
- A test shows notification content without item text while suppressed, and a P0 still delivered.
- `GET /__mock/sessions` shows heartbeats at the right interval and on change.

## D9. Accessibility, performance, snapshots, run guide and demo

Branch `feat/d9-hardening`. Depends on all. About 1.5 days.

Read: spec sections 6.8, 6.9 and 11; every ADR.

Build and check:

- A VoiceOver pass and a keyboard-only pass through every view; Reduce Motion stops every animation.
- Instruments traces for idle (Orbit only) and expanded (Pillars animating) on an M1 or later, against spec 6.9. If `Canvas` misses the budget, stop and report with the traces before any fallback (ADR 0004).
- Snapshot tests for every Orbit and pillar state not yet covered.
- `docs/run-local.md`: a fresh clone to the `normal` scenario on screen, then the switch to `lance-dev`.
- The demo against the mock, then against Lance dev once DL1 to DL4 are merged.

Done when every row of spec section 11 has its evidence in the phase log, or a named reason it waits on Lance.

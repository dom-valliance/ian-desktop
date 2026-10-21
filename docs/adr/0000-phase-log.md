# Phase log

Acceptance evidence for each work package, appended when its checks pass. A package is not done until its entry is here. Plan and checks: [work-packages.md](../plans/work-packages.md). Acceptance criteria: [spec section 11](../spec.md#11-acceptance-criteria).

Each entry records:

- Date, branch and commit range
- Every command run and its exit code (the workflow commands and the package's own checks)
- Which spec section 11 criteria it evidences, and how
- ADRs written, deviations taken, and anything left for a later package

| Package | Status |
|---|---|
| D1 | Done, 18 October 2026 |
| D2 | Done, 18 October 2026 |
| D3 | Done, 18 October 2026 |
| D4 | Done, 19 October 2026 |
| D5 | Done, 19 October 2026 |
| D5.1 | Done, 19 October 2026 |
| P1 | Done, 19 October 2026 |
| D6 | Done, 20 October 2026 |
| D7 | Done, 20 October 2026 |
| D8 | Done, 20 October 2026 |
| D9 | Done, 21 October 2026 |
| N1 | Not started |

## Entries

### D1. Repository, project, package, CI, contract draft

- Date: 17 October 2026
- Branch: `feat/d1-foundations`, from `main` at `72520dc` (`chore: prepare workspace`). Commits `732b0b1..557cd40`, plus this entry.
- Machine: macOS 26.5, Command Line Tools only (Swift 6.3.2, swift-format 6.3.0), no Xcode. Node 22.23.2, pnpm 12.4.2.

#### Commands and exit codes

Run from a fresh clone of the branch at `557cd40`:

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions` | 1: `no such module 'Testing'`. Command Line Tools keep Swift Testing outside the default search paths; Xcode does not |
| The same, with `-Xswiftc -F$D/Frameworks -Xlinker -F$D/Frameworks -Xlinker -rpath -Xlinker $D/Frameworks -Xlinker -rpath -Xlinker $D/usr/lib`, where `D=/Library/Developer/CommandLineTools/Library/Developer` | 0: 5 tests, 13 cases, all passed |
| `scripts/check-generated.sh` | 0 |
| `pnpm install --frozen-lockfile` then `pnpm lint`, in `contract/` | 0, 0 |
| `pnpm install --frozen-lockfile` then `pnpm test`, in `mock/` | 0, 0 (no tests until D2) |
| `actionlint` 1.7.12 on `.github/workflows/*.yml` | 0 |
| `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' build` | Not run: no Xcode on this machine. The `macOS` workflow runs it on `macos-26` with Xcode 26.6 and no Apple account |

The build prints about 25 warnings, all in `Sources/Contract/Generated`: the generator's `public import` lines are unused in some files under Swift 6.3. They are left in place, since generated code is not edited and `unsafeFlags` would be needed to silence them.

#### Done when

1. A fresh clone builds with `xcodebuild` on a Mac with no Apple account: waiting. Signing is Sign to Run Locally with no team; the first `macOS` workflow run is the evidence, appended here when it passes.
2. `swift test` runs a test that decodes a sample `Item` of each kind through the generated types: `ContractTests` "decodes each item example with the kind and detail of its kind" passes for `proposal`, `commitment_by`, `commitment_to`, `task` and `alert`. Its fixtures are the contract's own `components.examples`, extracted by `scripts/generate-contract.sh`.
3. The contract lint passes, and every endpoint and event in spec section 5 is in the document (checked by script against 5.2 and 5.5):
   - Operations, each with bearer security, `Desktop-Client-Version`, `401` and `426`: `GET /me`, `GET /snapshot`, `GET /today`, `GET /items`, `GET /items/{itemId}`, `POST /items/{itemId}/actions/{actionId}`, `POST /handoff`, `GET /agents`, `POST /agents/{agentId}/pause`, `POST /agents/{agentId}/resume`, `GET /settings`, `PATCH /settings`, `GET /events`, `POST /sessions`.
   - Events: `item.upserted`, `item.removed`, `today.updated`, `alert.raised`, `alert.cleared`, `agent.updated`, `settings.updated`, `client.deprecated`, `heartbeat`, and `views.updated` (ADR 0009).
   - `409` carries the current item, the stream answers `410`, and the field cell carries `kind` (Q16).
4. `git tag contract-v1.0.0` on the merge commit: after Dom merges.

#### Generator wiring

A committed CLI run, not the build plugin. `scripts/generate-contract.sh` runs `swift-openapi-generator` 1.14.1 from `scripts/tools` and writes `Packages/IanKit/Sources/Contract/Generated`, with `swift-format-ignore-file` at the top of each file. The plugin was rejected because Xcode asks to trust a package plugin, which breaks a fresh-clone `xcodebuild`, and because it rebuilds the generator on every clean build. `scripts/check-generated.sh` regenerates the code, the fixtures and the Xcode project in CI and fails on drift.

#### Spec section 11 criteria evidenced

- The contract is the single source: the Swift models are generated from the YAML and drift-checked in CI. The mock's validation is D2's; DL6 is Lance's.
- The client holds no logic: the contract carries every grouping, order, count, rung and label the views need (ADR 0009), so later packages have no reason to compute them.
- The app runs locally with no Apple setup: in part. The project signs to run locally with no team; the build evidence is the first CI run, and `scripts/dev.sh` arrives in D2 and D3.

#### ADRs, deviations and what is left

- ADR 0007, XcodeGen keeps the Xcode project (Q15). ADR 0008, build with Xcode 26, where spec section 2 says Xcode 16. ADR 0009, contract v1 fills gaps in spec section 5. The Opus review of the contract found 25 issues; all were addressed or recorded in ADR 0009.
- Departures from the D1 plan:
  - The generator lives in the `scripts/tools` package, not in IanKit's `Package.swift`, because nothing in IanKit uses it at build time. The same package pins XcodeGen 2.46.0 and Yams 5.4.0.
  - `swift-snapshot-testing` is not added yet. It imports XCTest, which Command Line Tools lack, and D1 has no snapshot test. D4 adds it with the first one; its plan says so.
  - `.swift-format` is the default configuration, whose line length is already 100.
- Left for later:
  - Xcode keeps its own `Package.resolved` for the app under `App/Ian.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`. The first package run with Xcode installed commits it and adds `-onlyUsePackageVersionsFromResolvedFile` to the `xcodebuild` step. `check-generated.sh` leaves that folder out.
  - D2 validates with `discriminator` as an annotation, and asserts `item.kind == item.detail.kind` and that every `unitId` is in `field.units` (`contract/README.md`).
  - D3 follows the AGENTS.md gotchas on the date transcoder and on decoding the event stream.
  - Lance's façade has the gaps listed in [docs/companion/lance-track.md](../companion/lance-track.md).

#### Completion, 18 October 2026

- Merged as pull request #1, merge commit `6d91427` on `main`. The pull request's `macOS`, `Mock` and `Contract` checks passed (reported by Dom), so the first `Done when` item holds on GitHub's `macos-26` runner with Xcode 26.6 and no Apple account.
- `contract-v1.0.0` tags `6d91427` and is pushed. `git diff feat/d1-foundations origin/main` is empty, so the tag carries exactly the reviewed tree.
- On branch `chore/xcode-27`, ADR 0010 moves the build to Xcode 27.1 (27A9275) and supersedes ADR 0008. From a fresh clone of that branch at `e1d6dad`, on macOS 27.0.1 with Xcode 27.1 and no Apple account signed in to Xcode:

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions` | 0: 5 tests, 13 cases, no extra flags |
| `scripts/check-generated.sh` | 0 |
| `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile build` | 0, `BUILD SUCCEEDED` |
| `pnpm install --frozen-lockfile` then `pnpm lint`, in `contract/` | 0, 0 |
| `pnpm install --frozen-lockfile` then `pnpm test`, in `mock/` | 0, 0 |

- The follow-up on the app's pins is closed by ADR 0010: Xcode 27.1 wrote no `Package.resolved` for the app, so `scripts/generate-project.sh` copies IanKit's into the project. A probe with `swift-collections` pinned to 1.7.2 showed Xcode resolving 1.7.2, so the copy is honoured.

### D2. Mock server

- Date: 18 October 2026
- Branch: `feat/d2-mock`, from `main` at `9efcaf9`. Commits `ee2d606..6c153da`, plus this entry; `40cbfe9` before them is a notes entry.
- Machine: macOS 27.0.1, Xcode 27.1 (27A9275), Node 22.23.2, pnpm 12.4.2.

#### Commands and exit codes

| Command | Exit |
|---|---|
| `pnpm install --frozen-lockfile` in `mock/` | 0, and the lockfile passes the two-week `minimumReleaseAge` policy |
| `pnpm --dir mock lint` (ESLint, then Prettier) | 0 |
| `pnpm --dir mock typecheck` | 0 |
| `pnpm --dir mock test` | 0: 142 tests in 7 files |
| `pnpm generate` in `mock/`, then `git diff --exit-code -- src/generated` and an empty `git status --porcelain -- src/generated` | 0 |
| `pnpm install --frozen-lockfile` then `pnpm lint`, in `contract/` | 0, 0 |
| `scripts/check-generated.sh`, `swift format lint`, `swift build` and `swift test` for IanKit, after the contract patch | 0 each |
| `scripts/dev.sh` | Mock answered `GET /me` 1.4 seconds after start |
| `scripts/dev.sh` again on the same port | 1, with "something already answers on 127.0.0.1:4317" |
| D3's integration suite against this mock (`IAN_MOCK_URL=http://localhost:4317 swift test --filter Integration`, from the D3 branch) | 0: 3 tests in 0.94 seconds |

#### Done when

1. Lint, typecheck and test pass: above.
2. Every endpoint in every scenario is called and each response validated against the contract: `endpoints.test.ts` calls all 14 operations in `quiet`, `normal`, `overloaded`, `incident`, `external-meeting` and `stale-client`, drains and validates every stream event, and asserts that every `operationId` was covered. `offline` is tested for refused connections. The invariants the schema cannot express (`item.kind` equals `detail.kind`, every `unitId` in `field.units`, every id in Today and Views in the snapshot, severity on alerts only) are checked per scenario.
3. A client disconnects, five events are emitted, and reconnecting with `Last-Event-ID` receives the five in order; an id past the replay window, newer than the latest, or from an earlier process receives `410`: `stream.test.ts`.

#### Choices recorded

- Zod schemas are generated from the contract by `@hey-api/openapi-ts` 0.99.0 with its Zod plugin (Zod 4.6.5), committed under `mock/src/generated`, and drift-checked in `mock.yml`. Request bodies, path and query parameters and the version header are parsed with them.
- Responses are validated in tests by an independent Ajv 2020 validator over the contract itself (`mock/src/testing/contractValidator.ts`), with `discriminator` and `example` as annotations.
- The mock is a small in-memory Lance: it derives horizon, pressure, attention, the Orbit, the field, the lists and the views from seed items and a frozen mock clock that moves only through `POST /__mock/clock`. The pressure formula is documented in `mock/src/domain/derive.ts`; Lance's is its own.
- Event ids start from the wall clock at process start, so an id from an earlier process answers `410`. Actions are held in flight until their last event, so a second action meanwhile answers `409`. `POST /__mock/capabilities` turns hand-off off, so `/handoff` answers `404` as Lance will.
- Placeholders are `[CLIENT A]` to `[CLIENT D]` and `[PERSON A]` to `[PERSON D]`, so the field has distinct columns.
- A malformed `Desktop-Client-Version` is treated as absent rather than answered with `400`, which the contract does not define on every operation.

#### Spec section 11 criteria evidenced

- The contract is the single source: the mock's tests validate every response and event against the contract, and its request schemas are generated from it.
- The stream recovers, server side: replay from `Last-Event-ID`, and `410` beyond the window. The client side is D3's.

#### ADRs, deviations and what is left

- No ADR. Contract 1.0.1, a description-only patch: a stream opens with the comment line `: open` and `X-Content-Type-Options: nosniff`, because the Swift client showed the stream live only at the first 25-second heartbeat without it. Tag `contract-v1.0.1` after the merge. The same rule is in Lance's DL3 note.
- `scripts/dev.sh` has its first half. D3 adds building and opening the app at the marked place.
- Reviewed by an Opus review against REVIEW.md: 1 Blocking (this entry), 5 Should fix and 7 Suggestions, all fixed.

### D3. Client core

- Date: 18 October 2026
- Branch: `feat/d3-client-core`, rebased onto `feat/d2-mock` at `f5d054d` so the two merge in order. Commits `a2197cd..71cd2c2`, plus this entry.
- Machine: macOS 27.0.1, Xcode 27.1 (27A9275), Swift 6.4, Node 22.23.2, pnpm 12.4.2.

#### Commands and exit codes

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions` | 0: 122 tests (Store 50, Client 42, Auth 25, Contract 5); the 3 integration tests skip without `IAN_MOCK_URL` |
| `scripts/check-generated.sh` | 0 |
| `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -derivedDataPath build/DerivedData build` | 0, `BUILD SUCCEEDED` |
| `scripts/dev.sh --mock-only`, then `IAN_MOCK_URL=http://localhost:4317 swift test --package-path Packages/IanKit --force-resolved-versions --filter Integration` | 0: 3 tests in 0.97 seconds |
| `scripts/dev.sh` from the branch | Installed the mock's packages, started the mock, built the app and opened it; the app held an established connection to the mock on port 4317 |
| `pnpm --dir mock lint`, `typecheck` and `test`; the contract lint | 0 each (142 mock tests), inherited from D2 |

#### Done when

1. Unit tests cover the reducer (order, repeated ids, whole-object replacement, removal, pending marks set and cleared by correlation id, error marks, `409`, `426`, `client.deprecated`, the minimum version) and the event stream with a stubbed `URLProtocol` on an ephemeral session (parsing, unknown types skipped, `Last-Event-ID`, `410` refetch, backoff bounds, polling after 60 seconds and stopping when the stream returns, with an injected clock).
2. With the mock up, the integration suite shows the `normal` scenario arriving live, an emitted event applied, and recovery after the stream is killed: 3 passed.
3. With the `lance-dev` profile, sign-in fails with a message naming the missing setting and Lance DL1 (erratum E2), tested in `AuthTests`. Deviation: it fails before the browser opens, not after, because the desktop public client "Ian Desktop (dev)" is not registered until DL1, so `IAN_LANCE_CLIENT_ID` and `IAN_LANCE_SCOPE` are empty. Once they are set, the same flow opens the browser and maps Entra's `invalid_scope` to the same message.

#### Choices recorded

- `Client` holds the environment profiles, the generated client over an ephemeral `URLSessionTransport` with the `.iso8601WithFractionalSeconds` transcoder, a middleware adding `Authorization` and `Desktop-Client-Version`, and the `SyncEngine`: `/me` first, then the snapshot, then the stream from its cursor; a silence limit of 55 seconds; backoff from 1 to 30 seconds with jitter; snapshot polling after 60 seconds without the stream.
- `Auth` holds the `dev-local` provider and Entra authorisation code with PKCE (S256), `state` checked, a loopback listener bound to 127.0.0.1 on a random port, refresh shared by concurrent callers, and tokens in the Keychain as one generic password per profile.
- `Store` is one `@Observable`, `@MainActor` store over a pure reducer. A pending mark records the version it was sent with and clears on its correlation event, or on a snapshot that shows the item moved or gone. Sync tasks carry a generation, so nothing applies after a reset.
- The only `UserDefaults` key is `IanEnvironment`, read and never written: the spec 6.4 environment profile.
- The menu bar shows a temporary readout until D5: the environment when it is not `mock`, the open count from the server's `orbit.load`, the data's age, and the connection, sign-in or upgrade state. It shows no item titles, since suppression arrives in D4.
- ADR 0012 records the `TestSupport` library target and the declared imports (swift-http-types, Network, CryptoKit, Observation, os).

#### Spec section 11 criteria evidenced

- The stream recovers: killing the stream and restoring it applies the events that follow; `410` refetches the snapshot; offline keeps the data with its age.
- The client holds no logic: the store sorts, counts and groups nothing it receives; the open count is the server's `load`.
- The app runs locally with no Apple setup, in part: `scripts/dev.sh` builds and opens the app against the mock. D9 times the ten seconds.

#### What is left

- Reviewed by an Opus review against REVIEW.md: 1 Blocking (this entry), 8 Should fix and 13 Suggestions; all fixed except three left for later packages, now in the plan: a record of removed items for D5, the order of a new agent for D7, and the readout showing a count rather than a list.
- A pending mark has no timeout; the contract has no signal for an action that never settles. Revisit if one is seen in use.

### D4. Window model, Orbit, menu bar extra, suppression

- Date: 19 October 2026
- Branch: `feat/d4-orbit`, from `main` at `92fa69e`. Commits `588fba3..98d1d02`, plus this entry.
- Machine: MacBook Pro, Apple M4 Pro, macOS 27.0.1, Xcode 27.1 (27A9275), with an external display.

#### Commands and exit codes

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions`, three runs | 0 each: 194 tests (Surface 62 including 8 snapshot tests, Store 50, Client 43, Auth 25, Attention 9, Contract 5) |
| `scripts/check-generated.sh` | 0 |
| `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -derivedDataPath build/DerivedData build` | 0, `BUILD SUCCEEDED` |
| `scripts/export-orbit-fixtures.sh`, twice | Byte-identical fixtures both times |

The mock and the contract did not change.

#### Done when

1. Snapshot tests of the Orbit for `quiet`, `normal`, `overloaded` and `incident`, with motion on at a fixed time (0.6 seconds) and with motion off: eight references in `Packages/IanKit/Tests/SurfaceTests/__Snapshots__/OrbitSnapshotTests/`, at `precision: 0.998, perceptualPrecision: 0.98`. The fixtures are the mock's own snapshots at `2026-10-16T09:30:00.000Z`. The lead compared the images with the Scale and Recommended artboards: the ring and over-median arc, the kind colours, the larger alert with its rim, the overflow chip and the working core match.
2. A test calls `start()` and asserts `sharingType == .none` on every entry in `NSApp.windows`, including the panels from the factory and windows the system creates (ADR 0014).
3. Suppression: for each trigger alone (camera, external meeting, quiet hours, user pause), driven through the controller, the hover text is absent, the hover label paints nothing, and the accessibility label carries no title. The menu bar label, the menu and the D3 status lines carry no item text.
4. Manual check by Dom on 19 October 2026, on the machine above, against the mock with `scripts/dev.sh`, all reported good:
   - The Orbit appears bottom-right of the primary display, and hover shows the top item's title.
   - A click opens and closes the expanded panel; Escape closes it; clicking the Orbit while Ian is active closes it.
   - Clicks beside the Orbit, including inside the square around the circle, reach the app beneath.
   - A drag snaps to the nearest corner, and the corner survives a relaunch.
   - Right-click opens Open, Pause me, Settings and Quit Ian; Pause me hides the hover.
   - The Orbit stays visible on another Space and over a full-screen app.
   - The menu bar reads "Ian 9" in `normal`.
   - `incident` draws the larger alert with its rim, and `external-meeting` hides the hover.
   - VoiceOver reads the Orbit's label from the menu bar item.

#### Choices recorded

- **Click-through route (ADR 0005).** The Orbit panel is 96 by 96 points and starts with `ignoresMouseEvents` set. Global and local mouse-moved monitors clear it only while the pointer is inside the avatar's circle, writing only on change. The hosting view's hit test also ignores points outside the circle. The expanded panel accepts mouse-moved events, so the Orbit stays clickable while Ian is active. Hiding the panel deactivates Ian, so focus returns to the previous app.
- **Hover label.** The hover label is a separate panel from the factory that takes no mouse events, so the Orbit panel never grows.
- **Frame rate.** At the display's rate, a Debug build in `normal` used about 17% CPU in `top` while the core breathed. At 20 frames a second it used 0.0 to 0.7%, on this M4 Pro. Spec 6.9's budget is for an M1; D9 measures a Release build with Instruments. The timeline runs only while the Orbit is on screen, unsuppressed, with motion on and something moving.
- **Settings.** The corner is the spec 6.4 setting, stored as `IanOrbitCorner`; the Orbit snaps to the corners of the main display. "Pause me" is the spec 6.5 user pause of this Mac's notifications, held in memory only. It is not the principal's own pause in spec 6.4, which D7 wires through `PATCH /settings`.
- **Right-click menu.** It holds the shared entries; D3's status lines stay in the menu bar extra until D5 removes them.
- **Overflow chip.** It uses the Scale artboard's geometry scaled into the 100-unit box, and zero-length arcs are omitted, as `docs/design/README.md` now records.
- **Snapshot testing.** `swift-snapshot-testing` 1.19.6 is added for `SurfaceTests` only, as the plan says.

#### Spec section 11 criteria evidenced

- Orbit and Pillars match the design: the Orbit half, by the snapshot tests and the comparison above.
- Suppression holds: on the Orbit and its hover, by the trigger tests. Notifications are D8's.
- Windows stay out of screen captures: every app window is set to `.none` and tested. The recording with the system screenshot tool is part of D9.
- Accessibility holds: the Orbit's VoiceOver label is read from the menu bar item.

#### ADRs and what is left

- ADR 0013 records the imports Attention and Surface gained. ADR 0014 records that windows the system creates are swept to `.none`, because the factory cannot build them.
- Reviewed by an Opus review against REVIEW.md: 3 Blocking (this entry, the system windows, the import ADR), 5 Should fix and 10 Suggestions, all fixed.
- D9 measures the Orbit's idle cost on a Release build against spec 6.9.

### D5. Expanded client and Today

- Date: 19 October 2026
- Branch: `feat/d5-today`, from `main` at `c448481`. Commits `674d9aa..e2be8ae`, plus this entry.
- The Pillars field was built in parallel in the worktree `.worktrees/d5-field` (originals `8334800..368410e`) and cherry-picked as `82adb03..b61b8ba`; `git cherry` shows every one matched.
- Machine: MacBook Pro, Apple M4 Pro, macOS 27.0.1, Xcode 27.1 (27A9275).

#### Commands and exit codes

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions`, five runs | 0 each: 328 tests (Surface 107 including 8 Orbit and 8 Pillars snapshot tests, Features 82, Store 57, Client 43, Auth 25, Attention 9, Contract 5). The agent also ran it 20 times with every core loaded, all 0 |
| `scripts/check-generated.sh` | 0 |
| `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -derivedDataPath build/DerivedData build` | 0 |

#### Done when

1. **Field snapshots.** The field is snapshotted for `quiet`, `normal`, `overloaded` and `incident`, with motion on at a fixed time and with motion off: eight references in `Packages/IanKit/Tests/SurfaceTests/__Snapshots__/PillarsSnapshotTests/`, at `precision: 0.998, perceptualPrecision: 0.98`. The lead compared them with the Pillars artboard: the grid with Now at the front, face shading, alert rims, empty tiles, the plate, row labels on their baseline behind the cells, and working particles.
2. **Selection and sinking tests.** Selection is tested both ways, for Now items, week groups and later groups, and through the field's tap. A pillar sinks after `item.removed` and never after the action's click, including when `item.removed` and `today.updated` arrive with no refresh between (`settledRowAndOutcomeSurviveTheTodayUpdate`, `settledRowLeavesWithItsPillar`, and the scene builder tests).
3. **Manual passes.** Dom ran a keyboard-only pass and a VoiceOver pass through Today on 19 October 2026, against the mock in `normal`, and reported everything working:
   - The sidebar moves with the arrow keys, and the counts are shown.
   - The list rows move with the arrow keys, and the selected pillar is outlined.
   - The footer buttons work from the keyboard. The time prompt takes focus, Escape cancels only the prompt, and Return sends.
   - Settling a commitment shows Pending, then the row dims and leaves as its pillar sinks, with the outcome line in the footer.
   - Week group members and Later counts are reachable through the footer, and Escape closes the panel.
   - VoiceOver reads the sidebar with counts, the field as one label, and each row's kind, title, horizon and state, and it reaches and presses every action.

#### Choices recorded

- **ADR 0015.** `Features` may import the generated contract types, never the generated client.
- **Last view.** The last view is remembered for the life of the process only, because spec 6.4 does not list it among the settings that reach disk.
- **Layout.** The lists sit below the field (spec 6.3); the design README's differences table records it, with the week tag's count and the Later row's colour.
- **Removal record.** It keeps the removed item, its `outcome`, its place in `lists.now` and the time it left. It clears on expiry (ten seconds), on an upsert of the same id, or on a reset, never on `today.updated`. A settled row dims and leaves with its pillar after 0.7 seconds, and a departing column stays until its pillar has sunk.
- **Accessible path to every item.** A This week group's footer lists its member items, and a Later group's footer lists its counts as links, so no item is reachable only through the field (non-negotiable 8).
- **Action component.** One action component draws `actions` in order and asks for `confirm`, a time or a note from `input`. The time must be in the future and the note not blank. Pending, error, the 409 notice and offline states are shown. D6 reuses it.
- **Smaller decisions.**
  - A cleared alert's outcome line reads "Closed", since `alert.cleared` carries none.
  - The panel eases in (a fade over 0.3 seconds and a 14-point rise; fade only under Reduce Motion).
  - Settings in the menu opens the Settings view.
  - The kind colours live in one `KindPalette`.
  - The list selection uses the system accent colour, which Dom saw and left as it is.
- **The temporary status lines.** D3's temporary status lines are gone from the menu bar extra; the header names the environment and the data's age.

#### CPU, and P1

| Measurement (Release, this M4 Pro, mock running) | CPU |
|---|---|
| Field alone, in a test harness at 60 frames a second | about 14% |
| Panel open on Today in `normal` | 23.4% |
| Panel closed, Orbit only, in `normal` (core breathing) | 9.0% |
| Panel closed, Orbit only, in `incident` (alert pulsing) | 9.5% |
| Panel closed, Orbit only, in `quiet` (nothing moving) | 0.4% |

The last three were measured by the lead on the app's own process with `ps -o time`, over 30 seconds after a 10-second warm-up. Most of the cost is SwiftUI's per-frame layout and commit, not the drawing. D4's "under 1%" figure for the Orbit was wrong. Dom chose to fix this before D6 and D7, in the new package P1, against two thirds of each budget on this M4 Pro, since no M1 is available.

#### Spec section 11 criteria evidenced

- **Orbit and Pillars match the design:** the Pillars half, by the snapshot tests and the comparison above.
- **The client holds no logic:** the lists, groups, order and counts come from `today.lists` and `views`, and buttons only from `actions`.
- **Accessibility holds:** for Today, by Dom's keyboard-only and VoiceOver passes.

#### Reviews and what is left

- **Review.** An Opus review against REVIEW.md found 4 Blocking (one was this entry), 8 Should fix and 9 Suggestions. All are fixed, except the optional accessibility actions on Now rows.
- **Next.** D5.1, which Dom asked for on 19 October: turning the field by dragging, and resizable panes, both saved across relaunches. Then P1.

### D5.1. Turn the field and resize the panes

- Date: 19 October 2026
- Branch: `feat/d5-1-field-controls`, from the D5 branch `feat/d5-today` at `3cde236`. Commits `d6dae10..d3a84e6`, plus this entry. Merge D5 first.
- Machine: MacBook Pro, Apple M4 Pro, macOS 27.0.1, Xcode 27.1 (27A9275).
- Dom asked for it on 19 October 2026 and chose a full turn with the sway kept, a double-click to reset, both values saved across relaunches, and to build it before P1.

#### Commands and exit codes

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions`, three runs | 0 each: 373 tests (Surface 146, Features 88, Store 57, Client 43, Auth 25, Attention 9, Contract 5) |
| `scripts/check-generated.sh` | 0 |
| `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -derivedDataPath build/DerivedData build` | 0 |

#### Done when

1. **Tests** cover:
   - the drag mapping and its direction (dragging right moves the front edge right);
   - the sway around the chosen angle;
   - Reduce Motion holding the chosen angle;
   - the double-click reset;
   - a click below the 4-point threshold selecting, and a drag never selecting;
   - a click after an abandoned drag;
   - the hit test at 135 and 225 degrees, through a face centre that hits at 45 degrees and misses when turned;
   - labels at the leftmost end and not flipping during the sway;
   - the three settings saved and restored through a scratch suite;
   - the pane limits;
   - the field following its pane.
2. **Snapshots** of the field in `normal`, motion off, turned to 135 and 225 degrees (`pillars.normal-motion-off-135.png` and `-225.png`), checked by eye. The existing Orbit and Pillars snapshots are unchanged.
3. **Manual check** by Dom on 19 October 2026, against the mock:
   - Dragging turns the field all the way round, with the front edge following the pointer, and the tilt fixed.
   - The sway carries on around the new angle, and a click selects.
   - A double-click resets, and a click after an Escape mid-drag selects without a jump.
   - The panes resize, with the field scaling, and stay usable when the panel shrinks.
   - Reduce Motion stops the sway, not the drag.
   - The angle and both divider positions survive a relaunch.
   - The first check found that the dividers' resize cursor never appeared. A cursor rect under SwiftUI is overridden by the hosting view. After `d3a84e6` (a tracking area plus a hover handler setting the cursor on every move), Dom confirmed both cursors work, including while dragging at a limit.

#### Choices recorded

- **Turning.** The field turns at 0.5 degrees per point of drag. A double-click is a second click within the system's double-click interval and 8 points. A double-click on a pillar selects it and then resets the angle.
- **Row labels.** They sit at whichever end of each row projects leftmost, chosen from the principal's angle rather than the sway, so the sway never flips them.
- **Saved values (ADR 0016).**

  | Key | Default |
  |---|---|
  | `IanFieldAngle` | 45 |
  | `IanSidebarWidth` | 190 |
  | `IanFieldHeight` | 300 |

  The values are checked on read and written only when a drag or reset ends. There is no reset for the pane sizes; deleting the keys restores them. AGENTS.md's non-negotiables 5 and 7, REVIEW.md and the IanKit README now name these keys and the sway.
- **Pane limits.**
  - The sidebar is 160 to 320 points wide, and the right-hand panes keep at least 480.
  - The field pane is at least 180 points tall, and the lists and footer keep at least 220.
  - Saved sizes are clamped each time the panes lay out.
- **Field size.** The field's canvas is drawn at its fitted size inside the pane, so its per-frame area is unchanged; the gesture covers the whole pane. `TodayView` reads only its pane's height, so a sidebar drag does not rebuild the lists.
- **Divider accessibility.** The dividers are hidden from VoiceOver, since the lists are the accessible path. Exposing them as adjustable elements was suggested and left for later.

#### Reviews and what is left

- An Opus review against REVIEW.md found 1 Blocking (the rules still naming only spec 6.4), 5 Should fix and 9 Suggestions. All are fixed except the optional accessible dividers.
- P1 measures CPU at the default pane sizes.

### P1. Rendering within the budget

- Date: 19 October 2026
- Branch: `perf/rendering-budget`, from `main` at `33f615a`. Commits `7c2a9f7..f6cc303`, plus this entry.
- The field work was built in parallel in `.worktrees/p1-field` and cherry-picked as `428a389` and `ae91595`. One build fix, `89292e3`, removed a duplicate colour helper both halves had added.
- Machine: MacBook Pro, Apple M4 Pro (Mac16,7), macOS 27.0.1, Xcode 27.1 (27A9275), with external displays.

#### Commands and exit codes

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions`, three runs | 0 each: 429 tests |
| `scripts/check-generated.sh` | 0 |
| `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -derivedDataPath build/DerivedData build` | 0 |
| `scripts/measure-cpu.sh` | 0, every target met (below) |

#### Done when

1. **`scripts/measure-cpu.sh` reports the targets.**
   - How the script measures: it builds Release, starts the mock and runs Ian with the display kept awake. It measures Ian's own process from `ps -o time` over 30 seconds after a 10-second warm-up, and fails if the panel did not open.
   - The final run on the machine above, with the Mac left alone:

     | State | Before P1 (baseline run) | After P1 | Target | WindowServer, after |
     |---|---|---|---|---|
     | Orbit only, `quiet` | 0.47% | 0.07% | none | 29.6% |
     | Orbit only, `normal` (core breathing) | 8.89% | 0.07% | under 0.7% | 32.6% |
     | Orbit only, `incident` (alert pulsing) | 5.56% | 0.07% | under 0.7% | 35.3% |
     | Panel open on Today, `normal` | 15.22% | 7.46% | under 10% | 41.3% |

   - WindowServer is the system compositor, which includes the external displays; it has no target. The motion now runs there, adding about 3 to 6 points for the Orbit and about 12 with the panel open over `quiet`.
2. **Traces.**
   - A Time Profiler trace (`xcrun xctrace record --template 'Time Profiler' --attach`) ran for 15 seconds on the Release app with the panel open on Today in `normal`. It recorded 1,504 samples, about 10% of one core, on the main thread:
     - painting the field with Core Graphics (`PillarsPainter`, rasterising in `argb32_mark` and `aa_render`) is about 57%;
     - the field's maths (`PillarsRenderer`) is 5%;
     - SwiftUI's view graph (AttributeGraph) is under 1%.
   - Before P1, the field agent's `sample` traces showed most of the time in SwiftUI's per-frame layout, view-graph update and commit, and an empty `Canvas` in the same timeline cost as much as the field.
   - The traces are kept locally in the lead's scratchpad (`p1-panel-open.trace`) and in `/private/tmp/claude-501/scratch-p1/`, not in the repository.
3. **Snapshots.** The Orbit snapshots pass unchanged. The ten Pillars snapshots were re-recorded once, because Core Graphics draws the row titles about a point lower than SwiftUI did; the polygons and colours match, and the field agent looked at every image.
4. **Stopping and Reduce Motion are tested.**
   - The Orbit's layers are removed when it is hidden, occluded or suppressed (each of the four triggers), and under Reduce Motion.
   - The field's display link pauses when nothing moves, when the field is hidden, occluded or suppressed, or under Reduce Motion with no transition running.
   - A resize repaints the field even with the link paused.
5. **Hand check.** Dom checked on screen on 19 October 2026 and reported everything as good:
   - the Orbit's breath and the alert's pulse are smooth, and the breath does not restart when satellites change;
   - the field's sway, ripple, particles and sinking are smooth;
   - resizing never stretches the field;
   - Reduce Motion stills both, while dragging still turns the field and resizing still redraws.

#### Choices recorded

- **ADR 0017.** The Orbit's still pose is a `Canvas` drawn only when its state changes. The breath and pulse are Core Animation animations (eased, the same limits and periods, 20 to 30 frames a second), so Ian's process does nothing per frame.
- **ADR 0018.** The field is Core Graphics in a layer-backed `NSView` on a display link, with an 8-bit backing store and row titles laid out once. A frame is repainted only when a point moves by a device pixel or a colour by a visible step. Dom accepted on 19 October 2026 that this meets spec 6.9's "60 frames per second": every visible change appears on the next display frame, and identical frames are not repainted.
- **ADR 0004** is amended by 0017 and 0018. AGENTS.md, REVIEW.md, the IanKit and design READMEs and D9's plan now describe the new drawing, and say to run `scripts/measure-cpu.sh` after any rendering change.
- **Opening the panel for measurement.** `-IanOpenPanelOnLaunch YES` opens the panel on Today once after the first snapshot. It is read from the launch arguments only and never saved.
- **No M1 was available,** so the targets were two thirds of spec 6.9's budgets, on the M4 Pro (Dom's decision in D5).

#### Reviews and what is left

- **Review.** An Opus review against REVIEW.md found 2 Blocking (the field stretched after a resize; stale docs), 6 Should fix and 10 Suggestions. All are fixed.
- **An agent's crash.** During the work, a measurement harness crashed three times from a recursion bug and put dialogs on Dom's screen. The bug was fixed and tested before the code was used, and the lesson is in `.claude/notes/global.md`.
- **For D9.** D9 re-runs `scripts/measure-cpu.sh`. If the field ever needs to cost less, the remaining cost is pixel filling, not SwiftUI.

### D6. Proposals, Commitments, Tasks and Alerts

- Date: 20 October 2026, built from 19 October
- Branch: `feat/d6-views`, from `main` at `2a00e87`. Commits `355c337..d7f57be`, plus this entry.
- Machine: MacBook Pro, Apple M4 Pro (Mac16,7), macOS 27.0.1, Xcode 27.1 (27A9275).
- D7 was built in parallel in `.worktrees/d7` and is rebased onto this branch.

#### Commands and exit codes

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions`, three runs | 0 each: 478 tests, the integration tests skipped |
| `scripts/check-generated.sh` | 0 |
| `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -derivedDataPath build/DerivedData build` | 0 |
| `pnpm --dir contract install --frozen-lockfile && pnpm --dir contract lint` | 0 |
| `pnpm --dir mock lint && pnpm --dir mock typecheck && pnpm --dir mock test` | 0 |
| `scripts/dev.sh --mock-only`, then `IAN_MOCK_URL=http://localhost:4317 swift test --package-path Packages/IanKit --force-resolved-versions --filter Integration` | 0 |

#### Done when

1. **Each view renders every mock scenario.**
   - `ViewListTests` builds the Proposals, Commitments, Tasks and Alerts models from `quiet`, `normal`, `overloaded` and `incident`, and finds exactly the groups and items `views` names, in order, with nothing invented or repeated.
   - `ViewSnapshotTests` holds 14 references in `Packages/IanKit/Tests/FeaturesTests/__Snapshots__/ViewSnapshotTests/`: Proposals, the three Commitments tabs and Tasks in `normal`, Alerts in `incident` (the P0 group pinned) and `normal`, and the empty states. They are drawn in an `NSHostingView` at 640 by 720 points in the fixture's time zone, at `precision: 0.998, perceptualPrecision: 0.98`. The lead looked at them against the Context artboard.
2. **Every action the mock offers round-trips, and the item moves on the event.** `ViewActionIntegrationTests` loads `normal`, runs each action on one item, requires the item pending after the click with its version unchanged, then requires the pending mark cleared and the item removed or at a higher version. It relies on the mock's 250 ms action delay (`MOCK_ACTION_DELAY_MS`) to see the pending state, and says so.

   | View | Item | Actions |
   |---|---|---|
   | Proposals | `prop_01MOCK000000000001` | approve, reject |
   | Commitments, owed by me | `cmt_01MOCK000000000001` | settle, snooze (until), dismiss |
   | Commitments, owed to me | `cmt_01MOCK000000000102` | settle, chase (note), snooze (until) |
   | Commitments, to confirm | `cmt_01MOCK000000000201` | confirm, dismiss |
   | Tasks | `task_notion_01MOCK000000000001` | done |
   | Alerts | `alrt_01MOCK000000000001` | acknowledge, snooze (until) |

   A hand-off on a task passed the same way.
3. **Invented action ids give exactly those buttons, in order.** The `card-invented-actions` snapshot draws an item whose actions are `qq_9`, `aa_1` and `mm_5`, and shows the buttons Qq_9, Aa_1 and Mm_5 in that order. D5's `ItemActionsTests` prove the action component itself.
4. **Hand to Ian.** `HandoffTests` covers the capability gate, the instruction trimmed or absent, pending until the event with its correlation id, one hand-off at a time, the 2,000-unit limit, and the offline and failure notices.
5. **Hand check.** Dom checked on screen against the mock on 20 October 2026, from the D7 worktree (which holds D6), and reported everything working:
   - the four views in `normal`, `incident` and `quiet`, with the URGENT badge, the pinned P0 group while the alerts below it scroll, and a settled card dimming with its outcome before it leaves;
   - Hand to Ian sending, pending until the event, and vanishing with the capability off;
   - every card button and the Commitments tabs by keyboard, the cards by VoiceOver, and the panel at its narrowest width.

#### Choices recorded

- **Contract 1.1.0.** `ViewGroup` gains an optional `pinned` flag, which the server sets on the P0 alert group, so the client does not pin by item severity (ADR 0001). The mock sends it and reports 1.1.0. `docs/companion/lance-track.md` says Lance must send it. Dom tags `contract-v1.1.0`.
- **Cards in a scroll view.** The views draw cards in a `ScrollView` holding a `VStack`, not a `List`, because buttons inside a macOS list row are not in the Tab order. Card buttons are reached the way Today's footer buttons are, with the system keyboard-navigation setting.
- **Urgency.** The red rim and an URGENT or STOP badge follow the server's `attention`, for every kind, and VoiceOver reads the rung. The design README's differences table records the badge.
- **Leaving cards.** The mock drops a removed item from `views` in the same burst as `item.removed`. A removed card keeps its last group and place, dimmed, with the server's outcome line and no buttons, for the life of the store's removal record (ten seconds), as Today keeps a leaving row. If `views` still names the item, the server's place wins.
- **Dates and limits.** Card dates are in `me.timeZone`. The hand-off instruction is counted in UTF-16 code units, as Lance's TypeScript and the mock's Zod count it.
- **Fixtures.** One copy of the scenario fixtures (`today`, `views`, `items` and `me` per scenario) lives in `Packages/IanKit/Tests/TestSupport/Fixtures`, exported by `scripts/export-scenario-fixtures.sh` (renamed from `export-orbit-fixtures.sh`). The Orbit and Pillars snapshots pass unchanged. AGENTS.md's gotcha names the new script.
- **Access.** `DesktopAPI`'s `client`, `call` and `upgrade`, and `IanStore`'s `service` and `notices` setter, are module-internal so the hand-off can live in its own extension files.
- **No ADR.** Nothing departs from the spec. D7's ADR takes the next number.

#### Reviews and what is left

- **Review.** An Opus review against REVIEW.md found 2 Blocking (card actions out of the Tab order; this entry), 8 Should fix and 5 Suggestions. All are fixed.
- **Verification.** A second Opus pass confirmed the fixes and found 2 Blocking (urgency shown by colour alone; this entry), 3 Should fix and some Suggestions. All are fixed; the stale-outcome guard on actions and the hand-off went to D7, where the profile switch makes it reachable.
- **Alert notifications.** Dom asked during the hand check for a notification when an alert arrives, perhaps only for the highest priority. That is D8; D7's defaults already notify P0 always and P1 with a banner.

### D7. Agents and Settings

- Date: 20 October 2026, built from 19 October
- Branch: `feat/d7-agents-settings`, rebased onto `feat/d6-views` at `d6dac5e`. Commits `a828d16..2ffeaea`, this entry (`0e22a0e`), the CI fix `d4ff493..8ef6807` and its update to this entry. Merge D6 first.
- Machine: MacBook Pro, Apple M4 Pro (Mac16,7), macOS 27.0.1, Xcode 27.1 (27A9275).

#### Commands and exit codes

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions`, three runs | 0 each: 583 tests, the integration tests skipped |
| `scripts/check-generated.sh` | 0 |
| `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -derivedDataPath build/DerivedData build` | 0 |
| `pnpm --dir contract install --frozen-lockfile && pnpm --dir contract lint` | 0 |
| `pnpm --dir mock lint && pnpm --dir mock typecheck && pnpm --dir mock test` | 0 |
| `scripts/dev.sh --mock-only`, then `IAN_MOCK_URL=http://localhost:4317 swift test --package-path Packages/IanKit --force-resolved-versions --filter Integration` | 0: 15 tests |

#### Done when

1. **Each setting round-trips against the mock.** The integration suite, against the running mock:
   - quiet hours, the push budget, and the principal's own pause with a reason and its resume, each shown only after `settings.updated`;
   - going live refused with `422` in `normal`, and in `quiet` going live and back to dry run, once through the store and once through the Settings model with the dialog's dismissal in between;
   - pausing and resuming an agent, and `403` with the server's detail on `job_nightly_median`, which is not `pausable`;
   - `GET /agents` in the server's order.

   The client settings are tested against a scratch defaults suite: corner, motion, the three notification levels and the two suppression toggles are saved and read back, and each takes effect (the Orbit moves, motion reaches the Orbit and the field, a toggled-off trigger stops counting). A profile switch signs out, clears the store, saves `IanEnvironment` and syncs against the new profile.
2. **Settings survive a relaunch where they should.** The client settings and the environment are read back from a fresh defaults object in the tests, and Dom relaunched on screen and found them as he left them. The principal's settings live in Lance and come back with the snapshot.
3. **The diagnostics report from `normal` holds no item title.** `DiagnosticsReportTests` builds the report from the `normal` scenario fixture, with a pause reason, a kill-switch reason and agent names added, and finds no title, meta line, evidence quote, counterparty, reason or agent name in it. Every line starts with a label from a fixed list: app version, contract version, environment, event lag and last snapshot.
4. **Snapshots.** Six references in `Packages/IanKit/Tests/FeaturesTests/__Snapshots__/AgentsSettingsSnapshotTests/`: Agents in `normal` at 640 and 1,000 points wide, Agents in `incident` with the kill-switch banner, and Settings in `normal` (the top and the whole view) and with going live allowed. They caught a table that could not fit the panel, which was rebuilt.
5. **Hand check.** Dom checked on screen against the mock on 20 October 2026 and reported everything working:
   - Agents: pause and resume, no button on the job, and the kill-switch banner in `incident`;
   - Settings: quiet hours, push budget, pausing Ian everywhere, going live and back in `quiet`, the corner moving the Orbit, motion, the camera toggle, launch at login refusing cleanly on the unsigned build, the environment switch to Lance dev and back, and the copied report;
   - every control by keyboard and VoiceOver, and the settings after a relaunch.

   The first pass found that going live did nothing; the environment switch had the same fault. Both are fixed in `8b8be5f`, tested in the dialog's real order, and Dom rechecked both.

#### Choices recorded

- **ADR 0019.**
  - Stop always notifies, so it has no setting.
  - The levels are Off and Banner, with spec 6.6's defaults: Ambient off, Needs you off, Urgent banner.
  - A toggled-off suppression trigger stops counting everywhere, including D8's heartbeat flag. Quiet hours and the principal's pause are not toggles, and P0 still notifies.
  - A new agent first appears at the end of the list. The store then refetches `GET /agents` and takes the server's order, and a snapshot that arrives first wins over the older reply.
- **Keys on disk.** New spec 6.4 settings in `UserDefaults`: `IanReducedMotion`, `IanSuppressOnCamera`, `IanSuppressInExternalMeeting`, `IanNotificationLevelAmbient`, `IanNotificationLevelNeedsYou` and `IanNotificationLevelUrgent`. `IanOrbitCorner` and `IanEnvironment` are unchanged. Launch at login is read from `SMAppService` and not saved.
- **Contract 1.1.1.** Descriptions only:
  - `GET /agents` is in display order.
  - Lance emits `settings.updated` after every accepted PATCH that changes a value.
  - A PATCH that changes nothing answers with the current settings and emits no event, and the client settles on that reply.

  The mock now behaves that way. `docs/companion/lance-track.md` has a DL4 row for each rule. Dom tags `contract-v1.1.1` after `contract-v1.1.0`.
- **Nothing moves on a click.** A PATCH, a pause or a resume only marks pending. Only `settings.updated`, `agent.updated` or a snapshot moves the shown value. A refused change resets only its own controls to the server's value.
- **Stale outcomes are dropped.** Every command, action and hand-off carries the store's generation. A result that arrives after a sign-out or a profile switch is dropped, whether it is a notice, a pending clear, a `401` sign-out or a `426`. A sign-out or switch also cancels a sign-in in progress.
- **Event lag.** The clock offset is estimated from `me.serverTime` against the midpoint of the `GET /me` request. Lag is a heartbeat's arrival minus its `serverTime`, corrected by that offset, so it can be slightly negative.
- **Where things live.**
  - `ClientSettings` and the pasteboard are in Surface.
  - The levels and the toggles are in Attention.
  - The `SMAppService` adapter is in the app target, behind a protocol, so no test touches the real login items.
- **Copy says Ian.** Settings, Agents and the client's error messages no longer name Lance, except the environment name "Lance dev" and "Open in Lance".

#### Reviews and what is left

- **Review.** An Opus review against REVIEW.md found no Blocking findings, 8 Should fix and 12 Suggestions. Among the Should fix: a sign-in racing a profile switch, one unsettled PATCH locking every setting, and two refetch races. All are fixed.
- **Verification.** A second Opus pass confirmed the fixes. It found stale outcomes on actions and the hand-off, and five Suggestions:
  - the settings model was rebuilt on every event;
  - a refusal reset every draft;
  - drafts survived a profile switch;
  - the controls were locked during sign-in;
  - error copy still named Lance.

  All are fixed, and the pause reason is now counted in UTF-16 code units.
- **CI.** The first pull request run failed three Settings snapshots that passed locally. The `xcode-27` runner has Reduce Motion on and a US English region: the motion row's text wrapped to a second line, and the quiet hours pickers read 7:00 PM. Forcing both locally gave CI's numbers exactly. `d4ff493` pins the pickers to `en_GB`, like every other time in Ian, and gives the motion row an environment value the snapshots hold at false. The six Agents and Settings snapshots and the view snapshots pass unchanged with a US locale and Reduce Motion forced on. `8ef6807` makes CI print the runner's macOS, region and Reduce Motion, and upload failed snapshot images for seven days.
- **Lessons.** The dialog fault and the runner's settings are recorded in `.claude/notes/surface.md`.
- **For D8.** D8 reads the levels and toggles through `ClientSettings` and ADR 0019. Dom asked for a notification when an alert arrives, which D8's ladder delivers: P0 always, and P1 with a banner by default.

### D8. Notifications, the attention ladder and the heartbeat

- Date: 20 October 2026
- Branch: `feat/d8-attention`, from `main` at `9c5a3e0`. Commits `bac2fd5..6feb090` (19 commits), plus this entry.
- Built in two tracks in parallel: the ladder and notifications in `.worktrees/d8`, the heartbeat in `.worktrees/d8-heartbeat`. The heartbeat commits were rebased onto the ladder's and their fixes cherry-picked, so the branch holds no merge commits.
- Machine: MacBook Pro, Apple M4 Pro (Mac16,7), macOS 27.0.1, Xcode 27.1 (27A9275).

#### Commands and exit codes

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions`, three runs | 0 each: 705 tests, the integration tests skipped |
| `scripts/check-generated.sh` | 0 |
| `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -derivedDataPath build/DerivedData build` | 0 |
| `pnpm --dir contract install --frozen-lockfile && pnpm --dir contract lint` | 0 |
| `pnpm --dir mock lint && pnpm --dir mock typecheck && pnpm --dir mock test` | 0 |
| `scripts/dev.sh --mock-only`, then `IAN_MOCK_URL=http://localhost:4317 swift test --package-path Packages/IanKit --force-resolved-versions --filter Integration` | 0: 16 tests |

#### Done when

1. **Every rung of the spec 6.6 table.** `AttentionLadderTests` covers each rung, at each notification level, suppressed and not: the Orbit cue, the notification and whether item text shows. `EscalationPlannerTests` covers what counts as a moment to notify.
2. **No item text while suppressed, and a P0 still delivered.** `AttentionCoordinatorTests` (`stopDeliveredWhileSuppressed`) delivers a Stop while suppressed with the title "Ian", a fixed body and only Open, and checks that no title, meta line, quote or name reaches the notification, its category or its `userInfo`. A text-bearing notification is withdrawn, and a delivered Stop re-delivered without its text, when suppression starts.
3. **`GET /__mock/sessions` shows heartbeats at the right interval and on change.** The integration test runs the reporter against the mock with a two-second interval: the second heartbeat arrives, no third arrives before the interval, the third then arrives, and a change of `suppressed` arrives within a second as the fourth. The mock's clock stands still, so the interval is asserted from the client's side; `HeartbeatReporterTests` proves the 60-second schedule and the sends on change on a manual clock.
4. **Hand check.** Dom checked on screen against the mock on 20 October 2026 and reported everything working:
   - a P1 alert whispered its title beside the Orbit for about eight seconds and showed a banner offering Acknowledge and Open; Acknowledge marked it pending until the server removed it;
   - a proposal near expiry whispered and showed Approve and Open, without Reject, which asks for confirmation; the banner opened the panel on Proposals;
   - a P2 showed nothing at the default level and a banner once Needs you was set to Banner;
   - a P0 showed a banner with a sound and opened the panel on Alerts at the next mouse movement, once, and did nothing more with the panel already open;
   - with "Pause me" on, text-bearing banners left Notification Centre, the P0s stayed with "Something needs you now.", a P1 showed nothing, and a P0 notified with only Open and did not open the panel;
   - a relaunch in `incident` gave one banner, for the P0, and cleared the earlier ones;
   - `GET /__mock/sessions` showed a heartbeat at launch and about one a minute with one device id, `active` false while locked, `suppressed` true while paused, and a heartbeat on return from idle.

#### Choices recorded

- **ADR 0020, the ladder and notifications.**
  - One pure function maps the server's `attention`, the ADR 0019 levels and the suppression to a behaviour.
  - Only escalations notify: a new item, or a rise in rung. The first snapshot after a launch or reset is a baseline in which only Stop notifies.
  - While suppressed, only Stop notifies, with the title "Ian", a fixed line and only Open. A delivered Stop is replaced by that content, and every other banner that shows item text is withdrawn. Nothing whispers, Stop does not open the panel, and nothing is replayed afterwards.
  - Buttons are the item's actions that need no confirmation, time or note, in the order sent, then Open, under a category named for the item and its version. A button runs only on the version it showed, with nothing pending and actions enabled; otherwise the item's view opens.
  - Everything Ian delivered is withdrawn at start, a notification goes when its item leaves, and Stop arrives last in a batch.
  - `Attention` may import `UserNotifications`. Only the app creates the real notification centre.
- **ADR 0021, the heartbeat.**
  - A heartbeat goes every 60 seconds, and at once when `active` or `suppressed` changes or the principal returns after a minute idle.
  - The device id is held in memory for the life of the process.
  - `active` reads the login session live (unlocked, on the console, displays awake, not going to sleep), and the lock notifications are delivered immediately with a second look a second later.
  - `idleSeconds` comes from the input event source.
  - Heartbeats go only while running and live, and are never queued. A failure backs off from 5 to 60 seconds, and a change still goes at once.
  - The reporter wakes about once a minute while the principal works, every 5 seconds only while idle at an unlocked Mac, and not at all while signed out.
  - `Attention` imports nothing new; `StoreTests` gains a test-only dependency on `Attention`.
- **Lance.** `docs/companion/lance-track.md` gains two DL5 notes: one delivery decision per item needs a contract field the client does not have, and a session silent for about two intervals counts as gone.

#### Reviews and what is left

- **Reviews.**
  - The Opus review of the ladder and notifications found 3 Blocking, 5 Should fix and 5 Suggestions. The Blocking findings: a banner button could act on a newer version and skip a confirmation; banners delivered before suppression kept their text; two concurrency escape hatches had no reasons.
  - The review of the heartbeat found no Blocking, 3 Should fix and 4 Suggestions, among them a lock missed while Ian is not active and a failed heartbeat counted as sent.
  - A verification pass found 2 Should fix (an endlessly retried failing heartbeat; a P0 withdrawn when suppression starts) and 7 Suggestions.
  - All are fixed.
- **For D9 and later.**
  - Time-sensitive delivery for Stop needs an entitlement and stays in the fast follow (spec 12).
  - Focus is not a suppression trigger in version 0 (Q13).
  - Arbitration itself is Lance's (DL5), checked in spec 11 once DL5 is merged.

### D9. Accessibility, performance, snapshots, run guide and demo

- Date: 21 October 2026, built from 20 October
- Branch: `feat/d9-hardening`, from `main` at `7b647f2`. Commits `28911d3..80b8048` (31 commits), plus this entry.
- Built in parallel: snapshots, Reduce Motion, stream recovery and the accessibility fixes in `.worktrees/d9`; the run guide, the demo script and the measurement in `.worktrees/d9-docs`, cherry-picked onto the branch. An Opus audit of all of IanKit ran beside them.
- Machine: MacBook Pro, Apple M4 Pro (Mac16,7), macOS 27.0.1, Xcode 27.1 (27A9275), with external displays.

#### Commands and exit codes

| Command | Exit |
|---|---|
| `swift format lint --recursive --strict Packages App scripts` | 0 |
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 0 |
| `swift test --package-path Packages/IanKit --force-resolved-versions`, five runs | 0 each: 754 tests, the integration tests skipped |
| `scripts/check-generated.sh` | 0 |
| `xcodebuild ... -onlyUsePackageVersionsFromResolvedFile -derivedDataPath build/DerivedData build` | 0 |
| `pnpm --dir contract install --frozen-lockfile && pnpm --dir contract lint` | 0 |
| `pnpm --dir mock lint && pnpm --dir mock typecheck && pnpm --dir mock test` | 0 |
| Integration suite against `scripts/dev.sh --mock-only`, run serially (`--no-parallel`) | 0: 19 tests |
| Fresh clone of `main` at `7b647f2`, in a new folder: IanKit build, IanKit tests, `xcodebuild` build, the mock's install and tests | 0 each: 33 s, 29 s, 45 s, 9 s (warm caches) |
| `scripts/measure-cpu.sh` | 0, every target met (below) |
| `scripts/test-measure-lib.sh`, `bash -n scripts/measure-cpu.sh` | 0, 0 |

#### Spec section 11

| Criterion | Evidence | Status |
|---|---|---|
| The app runs locally with no Apple setup | A fresh clone built, tested and built the app with no signing and no Apple account (above). Launch to data on the unsigned Debug build that `dev.sh` makes: 1.00 s against a target of 10 s. Dom cloned the D9 branch into a new folder, ran `scripts/dev.sh`, and saw the `normal` scenario within about ten seconds of the app opening, on 21 October 2026 | Evidenced |
| The contract is the single source | `scripts/check-generated.sh` regenerates the Swift types from `contract/ian-desktop.v1.yaml` and fails on drift (D1, every package since); the mock validates every response against the same file and its tests pass (D2, 144 tests); tags `contract-v1.0.0` to `contract-v1.1.1` | Evidenced here; "DL6 passes in Lance CI" waits on Lance DL6 |
| The client holds no logic | An Opus audit of every source file in IanKit and the app found no pressure, horizon, grouping, Orbit selection, eligibility or policy computation, and every item button comes from `actions`; each client decision found is presentation an ADR or the spec allows | Evidenced |
| All seven views work | Today (D5: models, Dom's passes; D9: snapshots of the lists in all four scenarios and the footer for an item, a week group, a later group and a removed item), the four item views (D6: models from every scenario, 14 snapshots, every mock action round-tripped against the mock), Agents and Settings (D7: round trips against the mock, 6 snapshots), and the header's banners and the sidebar (D9: 14 snapshots) | Evidenced |
| Orbit and Pillars match the design | Orbit and Pillars snapshots for `quiet`, `normal`, `overloaded` and `incident` with motion on and off (D4, D5, P1) and turned angles (D5.1). D9 adds 11 Orbit states (a working core, the overflow chip at +1 and +128, an alert alone, one satellite of each kind, empty, load at and twice the median) and 14 Pillars states (selected, a selected alert, mid-sink, mid-growth, every kind at five pressures with working particles, empty, two units), each with motion on and off where motion changes the drawing. Every new reference renders the same with a US region, another time zone and Reduce Motion forced on | Evidenced |
| The stream recovers | `StoreIntegrationTests+Recovery` against the mock: with the stream dropped (`offline`), events logged meanwhile are replayed in order from `Last-Event-ID` with no snapshot refetch; with the mock's clock moved past the 24-hour window, the reconnect answers `410` and the snapshot is refetched; while disconnected the data keeps its age and actions are off, which the header's stale banner shows (snapshots). Unit tests in ClientTests and SyncEngineTests (D3). The mock's replay log now ages events by their own time (fixed in D9) | Evidenced |
| Suppression holds | D4's suppression tests and D8's notification tests (no item text while suppressed, a P0 still delivered). Dom checked on 21 October 2026: with Photo Booth's camera on, and again in `external-meeting`, the Orbit's hover showed no title, a P1 notified nothing, and a P0 read "Something needs you now." | Evidenced |
| Windows stay out of screen captures | Every window from `WindowFactory` sets `sharingType = .none` and system windows are swept (ADR 0014). Dom recorded the whole screen with the system's tool on 21 October 2026, with the Orbit and the panel showing: no Ian window appears in the recording, which he then deleted | Evidenced |
| The switch to Lance dev works | `docs/run-local.md` documents the switch | Waits on Lance DL1 to DL4 |
| Arbitration works | The client reports heartbeats (D8, ADR 0021) | Waits on Lance DL5 |
| The budget holds | `scripts/measure-cpu.sh` and two Time Profiler traces on the M4 Pro (below): every CPU and memory target met. No M1 was available, so the CPU targets are two thirds of spec 6.9's budgets (Dom's decision in D5) | Evidenced on an M4 Pro |
| Accessibility holds | An Opus audit of every view found no Blocking issue and VoiceOver reaching every item and action through the lists; its findings are fixed (below). `ReduceMotionInventoryTests` lists every animation and fails on one not listed; each has a test showing Reduce Motion stops it or makes it a fade, and the Orbit's glide to a corner now honours it. Dom's passes on 21 October 2026: with Keyboard navigation off, Today's rows by the arrow keys, Return into the footer's actions, Left and Right between them and Escape back, and Command-1 to 3 on Commitments; with it on, Tab through every control, one prompt open at a time; VoiceOver reading each row's kind and rung, the labelled footer, the spoken whisper and confirmation question; Reduce Motion stopping the breath (the working ring showing) and the sway while a drag still turns the field, the panel fading in and the Orbit jumping to its corner. ADR 0022 records what needs Keyboard navigation | Evidenced |

#### Measurements

`scripts/measure-cpu.sh` on 20 October 2026, Release build against the mock, 30 seconds after a 10-second warm-up, the Mac left alone:

| State | Ian CPU | Target | WindowServer | Average memory | Peak memory | Memory target |
|---|---|---|---|---|---|---|
| Orbit only, `quiet` | 0.13% | none | 5.88% | 97.1 MB | 100.9 MB | under 150 MB |
| Orbit only, `normal` | 0.10% | under 0.7% | 20.55% | 97.9 MB | 98.5 MB | under 150 MB |
| Orbit only, `incident` | 0.52% | under 0.7% | 17.29% | 93.8 MB | 102.0 MB | under 150 MB |
| Panel open on Today, `normal` | 7.90% | under 10% | 21.23% | 100.5 MB | 101.2 MB | none |

Launch to data, from process start to the mock reporting an open event stream (which follows the first snapshot): Release, Orbit only, cold 0.95 s; Release, panel open 0.39 s; Debug as `dev.sh` builds it 1.00 s; target 10 s.

Time Profiler, 15 seconds each, Release against the mock:

- Orbit only in `incident`: 24 samples, 0.16% of one core: stream reading, the store and the heartbeat, no drawing and nothing from notifications. The 0.52% above comes from `ps` at a 0.01-second resolution.
- Panel open on Today in `normal`: 900 samples, 6.0% of one core, 52% of them painting the field (`PillarsPainter`, pixel fills), SwiftUI's view graph negligible, as in P1.

The traces are kept in the lead's scratchpad, not in the repository.

#### Reduce Motion inventory

`ReduceMotionInventoryTests` counts every animation API in `Surface` and `Features` and fails when one appears that is not listed here.

| Animation | Where | Under Reduce Motion | Test |
|---|---|---|---|
| The Orbit's core breath | `OrbitMotion` (Core Animation) | No layers; the still pose at the breath's midpoint, with a ring while working | `OrbitMotionTests`, `OrbitRendererTests` |
| The alert rim's pulse | `OrbitMotion`, `OrbitRenderer` | No layers; the rim held full | `OrbitMotionTests`, `OrbitRendererTests` |
| The field's sway | `PillarsRenderer` | None; the chosen angle held | `FieldTurnTests`, `PillarsRendererTests` |
| The field's ripple | `PillarsRenderer` | None | `PillarsRendererTests` |
| An alert's outline pulse in the field | `PillarsRenderer` | Held | `PillarsRendererTests` |
| Working particles | `PillarsRenderer` | Held at one point | `PillarsRendererTests` |
| A pillar growing | `PillarsRenderer` | A fade at full height | `PillarsRendererTests`, `pillars.growing-motion-off` |
| A pillar sinking | `PillarsRenderer` | A fade at full height | `PillarsRendererTests`, `pillars.sinking-motion-off` |
| The field's display link | `PillarsFieldNSView` | Ticks only through a growth or a sink, then pauses | `PillarsFieldViewTests` |
| The principal's drag | `PillarsFieldNSView` | Still turns the field (AGENTS.md rule 7) | `PillarsFieldViewTests` |
| The panel's entrance | `SurfaceController`, `ExpandedEntrance` | A fade, no rise | `ExpandedEntranceTests` |
| The Orbit's glide to a corner | `SurfaceController` | Placed at once (fixed in D9) | `MotionPreferenceTests` |
| The header's age | `ExpandedClientView` (`TimelineView`, every 15 seconds) | Moves nothing on screen | `ReduceMotionInventoryTests` |
| The whisper, the hover label, list scrolling, selection | No animation | Not applicable | `ReduceMotionInventoryTests` |

#### Choices recorded

- **ADR 0022.** List rows move with the arrow keys with no system setting. Buttons and other controls are reached with Tab through macOS's Keyboard navigation setting, the platform's convention. The Commitments tabs also answer Command-1 to Command-3. Resizing the panes and turning the field are pointer-only conveniences that carry no information.
- **Accessibility fixes from the audit.**
  - Today's Now rows name their kind in the tag, and Later rows use a neutral swatch rather than a kind the server did not send.
  - One prompt is open per window, so Return and Escape act only on it.
  - Today's labels carry the rung, and the footer is a labelled container.
  - A confirmation question and the whisper are announced to VoiceOver, the whisper never while suppressed.
  - A working core shows a static ring when Reduce Motion stills it.

  The design README records the differences from the canvas.
- **Snapshot harness.** Views drawn with `List` render in a borderless window that is never ordered on screen, since a `List` draws nothing without one.
- **Measurement.** `scripts/measure-cpu.sh` now also reports resident memory (failing at 150 MB for the Orbit-only states) and the time from launch to the stream opening after the first snapshot (failing at 10 seconds), with no change to the app.
- **Docs.** `docs/run-local.md` takes a fresh clone to the `normal` scenario and describes the switch to `lance-dev`; `docs/demo.md` is a ten-minute demo against the mock.

#### Reviews and what is left

- **Audit and review.**
  - An Opus audit of all of IanKit found no client-side logic and no Blocking accessibility issue.
  - Its two Should fix findings (kind shown by colour alone on Today; Return and Escape reaching another card's prompt) and its eight suggestions are fixed.
  - An Opus review of the branch then found 1 Blocking (this entry and the measurement), 6 Should fix and 4 Suggestions. Among them were launch to data timed to the first request rather than the stream, a fixed wait in the snapshot harness, Later rows dropping the server's colour, a weak Reduce Motion inventory, and ADR 0022 not naming its narrowing. All are fixed.
- **Two timing flaws found in full runs.**
  - The `List` snapshots could capture a scroll bar's gutter before SwiftUI hid the indicators. The harness now forces overlay scrollers with the bars hidden, and lays out again before capturing.
  - A D3 store test checked the sign-out count before the store's sign-out task had run. It now waits for the call.

  The final checks use five full test runs instead of three.
- **Keyboard (ADR 0022).** Dom accepted on 20 October 2026 that controls follow macOS's Keyboard navigation setting, a narrowing of spec 6.2 and 6.8. Today's footer has a key path that needs no setting.
- **Open: the field stopped once.** During the hand check the Today field stopped animating at some point, and only a relaunch restarted it. Toggling system Reduce Motion, "Pause me", the camera, locking the screen and a screen recording did not reproduce it. The field's clock and the panel's on-screen state now log each change, at a level the system keeps, with no item content, and `docs/run-local.md` says how to read them, so the next occurrence leaves evidence.
- **Waiting on Lance.** The switch to Lance dev (DL1 to DL4) and arbitration (DL5), and the contract's single source in Lance CI (DL6). The demo against Lance dev waits on the same.
- **Next.** N1, "Call it Ian everywhere", added to the plan at Dom's request on 21 October 2026.

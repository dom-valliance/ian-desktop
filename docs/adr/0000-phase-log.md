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
| D5.1 | Not started |
| P1 | Not started |
| D6 | Not started |
| D7 | Not started |
| D8 | Not started |
| D9 | Not started |

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

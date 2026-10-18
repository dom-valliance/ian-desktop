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
| D3 | Not started |
| D4 | Not started |
| D5 | Not started |
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

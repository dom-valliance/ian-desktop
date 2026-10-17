# Phase log

Acceptance evidence for each work package, appended when its checks pass. A package is not done until its entry is here. Plan and checks: [work-packages.md](../plans/work-packages.md). Acceptance criteria: [spec section 11](../spec.md#11-acceptance-criteria).

Each entry records:

- Date, branch and commit range
- Every command run and its exit code (the workflow commands and the package's own checks)
- Which spec section 11 criteria it evidences, and how
- ADRs written, deviations taken, and anything left for a later package

| Package | Status |
|---|---|
| D1 | Built; waiting on the first CI run (`xcodebuild`) and the merge tag |
| D2 | Not started |
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

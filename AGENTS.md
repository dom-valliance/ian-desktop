# Ian desktop

A native macOS client for Lance, Dom's personal operating agent. At rest it is the Orbit avatar in a screen corner; opened, it is the expanded client with Today, Proposals, Commitments, Tasks, Alerts, Agents and Settings. Swift 6 and SwiftUI, macOS 14, a Node mock server, one OpenAPI contract.

How to work in this repository, for AI agents and people. `CLAUDE.md` imports this file, so Claude Code and Codex read the same rules. The specification is [docs/spec.md](docs/spec.md). Read it before writing code; this file summarises how to work here and does not replace it. Valliance global standards (each developer's `~/.claude/CLAUDE.md`) apply and are not repeated. Review rules are in [REVIEW.md](REVIEW.md).

## Read first

1. [docs/spec.md](docs/spec.md), all of it.
2. This file, including the errata below.
3. Lance's [AGENTS.md](../ian/AGENTS.md) and [roadmap](../ian/docs/plans/roadmap.md). The Lance checkout sits beside this one (`~/workspace/ian`, GitHub `valliance-ai/valliance-agents`). Its non-negotiables are why this client holds no write power.
4. [docs/context/lance-context.md](docs/context/lance-context.md): the foundations backlog, playback and Lev items the spec cites (B1, C1 to C3, F1, F2, G2, G3, the MVP cut, confidence sources), summarised. The full briefings live outside the repository.
5. [docs/design/README.md](docs/design/README.md) before any work in `Surface` or `Features`.
6. The package's entry in [docs/plans/work-packages.md](docs/plans/work-packages.md).

## Naming

The user-facing name is Ian. The server and the API keep Lance identifiers (B1).

| Where | Value |
|---|---|
| Repository | `ian-desktop` (a local folder named `desktop-ian` is the same repository) |
| App target, scheme, display name | `Ian` |
| Swift package | `IanKit` |
| Bundle identifier | `ai.valliance.ian.desktop`, with `.dev` for Debug |
| Contract | `contract/ian-desktop.v1.yaml`, served by Lance at `/desktop/v1` |
| Entra public client (dev) | `Ian Desktop (dev)` |
| App role checked by the api | `Lance.User` |
| Ledger payload marker | `surface: 'desktop'` |

UI copy says Ian. Code and docs that describe the server say Lance. New identifiers name the role, `principal`, never a person.

## Non-negotiables

Enforced in code and tested. From ADRs 0001 to 0006 and the spec.

1. **Thin client.** IanKit computes no pressure, horizon, unit grouping, Orbit selection, eligibility or policy outcome. It renders what the server sends. Buttons come only from an item's `actions`, in the order sent, and the client sends the action id back.
2. **The server settles state.** An action marks its item pending. Only the server's event moves the item. No optimistic completion, no offline action queue; actions are disabled while offline.
3. **The contract is the source.** Swift types are generated from `contract/ian-desktop.v1.yaml`; generated code is never edited by hand. The mock validates every response against the same file. A breaking change is `v2`, never an edit to `v1`.
4. **Mock by default, invented data only.** The app starts against the mock unless a profile says otherwise. Debug builds carry `mock` and `lance-dev` only; no production profile exists in version 0.
5. **Nothing on disk but two things.** Tokens in the Keychain, and the client settings in spec 6.4 in `UserDefaults`. No response caches (use an ephemeral `URLSession` configuration), no item content in logs (log ids only, through `os.Logger` with private interpolation), no crash reports or diagnostics carrying titles.
6. **Off screen captures.** Every window and panel sets `sharingType = .none`. Settings cannot switch it off. Suppression hides all item text on the Orbit and in notifications; P0 still notifies.
7. **Rendering costs nothing when unseen.** Animation stops when the expanded client is hidden, occluded or suppressed. Reduce Motion stops the ripple, the turn and the breathing.
8. **The list is the accessible path.** Every item and action in the Pillars field is reachable from a list row with VoiceOver and the keyboard. The field is never the only way to an item.

## How to use the spec

1. Build in the order of [docs/plans/work-packages.md](docs/plans/work-packages.md). A package is done when its checks pass by exit code and its evidence is in [docs/adr/0000-phase-log.md](docs/adr/0000-phase-log.md).
2. Record every deviation from the spec as an ADR in `docs/adr/NNNN-title.md` before implementing it. Deviations without an ADR are bugs.
3. Open questions in spec section 13, and Q12 onwards below, have defaults. Build the default; do not block.
4. Where the spec and the design canvas disagree, the spec wins. Note the difference in [docs/design/README.md](docs/design/README.md).
5. British English in UI copy, logs, comments and docs. No em dashes or en dashes anywhere. No emojis in UI copy.
6. Conventional commits, header at most 72 characters (`.githooks/commit-msg`; enable with `git config core.hooksPath .githooks`). Branches are `type/short-description`.

## Spec errata

Checked against the Lance repository on 17 October 2026. The spec text is unchanged; these rows correct it.

| # | Spec | Fact | Do |
|---|---|---|---|
| E1 | 1 and 5.3: confidence source "per ADR 0037" | Lance's ADR 0037 is "Inbound commitments need a definite recipient". The confidence-source rule is ADR 0037 in the Lev briefing, not yet written, and it will take a new number | Use the enum `lev_trusted`, `lev_untrusted`, `self_report`. Cite it as the Lev confidence-source rule |
| E2 | 8: "delegated access to the Lance api scope" | The `Lance (Valliance)` registration exposes no API scope. The api accepts bearer tokens whose audience is the Lance client id (`apps/api/src/auth/entra.ts`) | Lance package DL1 adds the scope and accepts its audience. Until then `lance-dev` fails at sign-in with a clear message. The scope string lives in the profile configuration |
| E3 | 8: dev api host "from the Lance runbook's known-values table" | That table lists no hostname. The dev api host is `ca-lance-api-dev.graygrass-c682ce2c.uksouth.azurecontainerapps.io`, recorded in Lance's `docs/runbooks/entra-setup.md` | Base URL `https://ca-lance-api-dev.graygrass-c682ce2c.uksouth.azurecontainerapps.io/desktop/v1`. Re-read it with `az containerapp show -g rg-lance-dev -n ca-lance-api-dev --query properties.configuration.ingress.fqdn -o tsv` |
| E4 | 6.3: "colour is kind" | The design canvas colours commitments, proposals and alerts; `task` has no colour | Q12 |
| E5 | 6.5: suppression list | The Ladder artboard also holds notifications for Focus and screen sharing | The spec wins. Focus is Q13. Screen sharing has no public signal; `sharingType` is the defence |
| E6 | 12: Intune "Required for `Lance Users`"; Conditional Access | Lance ADR 0020: the tenant has no Entra ID P1, so the `Lance Users` group was never created, and Conditional Access needs P1 | Fast-follow prerequisite, recorded in [docs/companion/lance-track.md](docs/companion/lance-track.md). No effect on version 0 |

## Open questions beyond the spec

| # | Question | Default in force |
|---|---|---|
| Q12 | Colour for `task` items | Valliance teal-100 `#7FBFC1`, until Dom picks |
| Q13 | Focus mode as a suppression trigger | Not in version 0 |
| Q14 | Dock icon and app menu | Accessory app (`LSUIElement`), no Dock icon. The Orbit and the menu bar extra are the entry points |
| Q15 | How the Xcode project is kept | `App/project.yml` with XcodeGen is the source; the generated `App/Ian.xcodeproj` is committed so a fresh clone opens without XcodeGen; CI fails if they drift. D1 records it as ADR 0007 |
| Q16 | Colour of a field cell that holds items of several kinds | The server sends the cell's kind (the kind of its highest-pressure item). D1 puts `kind` on the field cell in the contract draft, so the client chooses nothing |
| Q17 | Attention rung per item | Settled in D1: the spec 6.6 table names triggers the client cannot see (risk language, a foreign decision attempt, the budget ceiling), so `Item.attention` carries the rung from Lance and the client maps nothing (ADR 0009) |

## Toolchain and commands

Xcode 27.1 (ADR 0010) with Swift 6 in strict concurrency mode, macOS 14 minimum. Node 22 through nvm (`nvm use`), pnpm through corepack. Dependencies are the four Swift packages in spec section 2 and nothing else without an ADR. Build tools that never ship (`swift-openapi-generator`, XcodeGen, and Yams for the `extract-examples` tool that turns the contract's examples into test fixtures) are pinned in `scripts/tools/Package.swift` and run through the scripts in `scripts/` (ADR 0007).

Once D1 and D2 land, these are the checks. Every one must pass, judged by exit code, before a task is marked done:

```
swift format lint --recursive --strict Packages App scripts
swift build --package-path Packages/IanKit --force-resolved-versions
swift test --package-path Packages/IanKit --force-resolved-versions
scripts/check-generated.sh
xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile build
pnpm --dir mock lint && pnpm --dir mock typecheck && pnpm --dir mock test
pnpm --dir contract install --frozen-lockfile && pnpm --dir contract lint
```

Until D2, the mock has only an empty `test`. Read the workflows in `.github/workflows/` rather than this list when they differ; the workflows win.

## Git and GitHub

GitHub is Dom's: he creates the remote, opens pull requests and merges. Use plain git for branches and commits. Never install or use the `gh` CLI. Hand over a branch name and a commit range, then a numbered list of Dom's actions with exact commands. Before each commit run `git reflog -5`, and `git log --oneline origin/main..HEAD` once a remote exists; the branch must hold only your own commits.

## Working beside Lance

- Read Lance freely; never change it from a session in this repository. Lance packages DL1 to DL6 run in a Lance session, on a Lance branch, under Lance's `AGENTS.md`.
- [docs/companion/lance-track.md](docs/companion/lance-track.md) holds what Lance must build and the gaps found so far. Lance's pointer to this repository is `docs/plans/desktop.md` in Lance.
- A contract change that Lance must follow is tagged here first (`contract-v1.MINOR.PATCH`), then pinned in Lance.

## Data

- No real data in this repository: no mail, transcripts, task titles, meeting names, client or counterparty names, in fixtures, snapshots, tests, screenshots, docs or pull request text. Mock fixtures use `[CLIENT]` and `[PERSON]` placeholders.
- Snapshot tests render mock fixtures only. Never record a snapshot, screenshot or trace against `lance-dev`.
- The diagnostics report copies ids, versions and timings only.

## Gotchas

Promoted here when the same lesson appears more than twice in `.claude/notes/`. Seeded with what is known before the first line of code.

- A borderless `NSWindow` or `NSPanel` returns false from `canBecomeKey`. The Orbit panel must stay that way; the expanded client's panel overrides it so text fields take input.
- `URLSession.shared` and the default configuration write responses to a disk cache. Build every session from `URLSessionConfiguration.ephemeral`.
- The Swift contract types come from `scripts/generate-contract.sh`, which runs `swift-openapi-generator`'s CLI and writes `Packages/IanKit/Sources/Contract/Generated`. The output is committed and `scripts/check-generated.sh` fails CI on drift. Do not use the build plugin: Xcode asks to trust it, which breaks a fresh-clone `xcodebuild`.
- Xcode ignores a local package's `Package.resolved`. `scripts/generate-project.sh` copies IanKit's into `App/Ian.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`, so a dependency change is resolved in `Packages/IanKit` and then regenerated, never resolved in Xcode.
- Keep `.swift-format` to the keys that differ from the default. A full `dump-configuration` from one swift-format version fails to load in the next, which adds required keys.
- `swift-openapi-generator` silently drops a property declared as `oneOf` a `$ref` and `null`. Make such a property optional and absent when it does not apply (ADR 0009); inline values can use `type: [string, 'null']`.
- Contract times are UTC with milliseconds. Configure OpenAPIRuntime with the `.iso8601WithFractionalSeconds` date transcoder, and decode event `data` with a `JSONDecoder` whose date strategy matches; the default `.iso8601` rejects them.
- `asDecodedServerSentEventsWithJSONData` throws on the first event it cannot decode, which ends the stream, and the generated `StreamEvent` rejects an unknown `type`. Use `asDecodedServerSentEvents()`, skip events whose `event` field is not a known type, and refetch the snapshot when a known type fails to decode.
- The `lance-dev` profile reads Dom's real dev data. Keep it out of every test, snapshot and recording.

## Review guidelines

OpenAI Codex reads this section when it reviews a pull request. Claude Code follows it for local reviews through `/review-pr`.

- Review against [REVIEW.md](REVIEW.md), the non-negotiables above and the ADRs in `docs/adr/`. Cover the pull request description as well as the code and docs.
- Map REVIEW.md severities to priorities: **Blocking to P1**, **Should fix to P2**, **Suggestion to P3**. Use **P0** only for a leaked secret or token, or real mail, transcript, task or personal data committed to the repository or written into the pull request.
- Automated review is advisory. Never approve a pull request and never request changes. Post findings as comments.

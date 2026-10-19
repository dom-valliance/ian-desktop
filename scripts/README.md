# Scripts

| Script | Does |
|---|---|
| `dev.sh` | Starts the mock on port 4317, waits until it answers, then builds the app and opens it against the mock. `--mock-only` starts only the mock |
| `generate-contract.sh` | Regenerates `Packages/IanKit/Sources/Contract/Generated` and the JSON fixtures in `Packages/IanKit/Tests/ContractTests/Fixtures` from `contract/ian-desktop.v1.yaml`. The fixtures are the contract's `components.examples` |
| `generate-project.sh` | Regenerates `App/Ian.xcodeproj` from `App/project.yml`, and copies IanKit's `Package.resolved` into it, because Xcode ignores a local package's pins |
| `export-orbit-fixtures.sh` | Starts the mock on a free port, sets its clock to 2026-10-16T09:30:00Z and writes the `today` and `items` of the `quiet`, `normal`, `overloaded` and `incident` snapshots to `Packages/IanKit/Tests/SurfaceTests/Fixtures`. The Orbit snapshot tests render these. Running it twice gives byte-identical files |
| `measure-cpu.sh` | Builds Release, starts the mock, runs Ian and prints the CPU of Ian's own process: the Orbit alone in `quiet`, `normal` and `incident`, and the panel open on Today in `normal` (opened with the launch argument `-IanOpenPanelOnLaunch YES`). Exits non-zero when a target in P1 is missed. Takes about four minutes after the build |
| `check-generated.sh` | Runs both generators and fails if any generated file differs from what is committed. CI runs it |

Acceptance (spec section 11) requires a fresh clone to show the `normal` scenario within ten seconds of running `dev.sh`, once the app is built. The first build takes a few minutes; D9 measures the ten seconds.

The generators run from `scripts/tools`, a package that pins `swift-openapi-generator` and XcodeGen, so every machine and CI use the same versions.

Scripts must work from a fresh clone with no Apple account, and must fail with a clear message when Xcode, Node 22 or pnpm is missing.

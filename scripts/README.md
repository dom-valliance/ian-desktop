# Scripts

| Script | Does |
|---|---|
| `dev.sh` | Starts the mock on port 4317, waits until it answers, then builds the app and opens it against the mock. `--mock-only` starts only the mock |
| `generate-contract.sh` | Regenerates `Packages/IanKit/Sources/Contract/Generated` and the JSON fixtures in `Packages/IanKit/Tests/ContractTests/Fixtures` from `contract/ian-desktop.v1.yaml`. The fixtures are the contract's `components.examples` |
| `generate-project.sh` | Regenerates `App/Ian.xcodeproj` from `App/project.yml`, and copies IanKit's `Package.resolved` into it, because Xcode ignores a local package's pins |
| `export-scenario-fixtures.sh` | Starts the mock on a free port, sets its clock to 2026-10-16T09:30:00Z and writes the `today`, `views`, `items` and `me` of the `quiet`, `normal`, `overloaded` and `incident` snapshots to `Packages/IanKit/Tests/TestSupport/Fixtures`. The Orbit, Pillars and view tests read these. Running it twice gives byte-identical files |
| `measure-cpu.sh` | Builds Release, starts the mock, runs Ian and measures its own process: CPU, resident memory and launch to data (Release, plus one launch of the Debug build). States: the Orbit alone in `quiet`, `normal` and `incident`, and the panel open on Today in `normal` (opened with the launch argument `-IanOpenPanelOnLaunch YES`). Prints three tables and exits non-zero when a target is missed. See below. Takes about four minutes after the build |
| `test-measure-lib.sh` | Checks the parsing `measure-cpu.sh` does on the mock's state and on `ps`, against fixed samples. Needs no display and starts nothing |
| `check-generated.sh` | Runs both generators and fails if any generated file differs from what is committed. CI runs it |

## What `measure-cpu.sh` measures

It opens Ian on your screen, so run it from a terminal on a Mac you are not using, with the display awake and unlocked. It needs Xcode 27, Node 22 and pnpm.

| Measure | Method | Target |
|---|---|---|
| CPU | Change in the process's cumulative CPU time (`ps -o time`) over 30 seconds, after a 10-second warm-up | Orbit alone under 0.7% in `normal` and `incident`; panel open under 10% (two thirds of spec 6.9 on the M4 Pro, P1) |
| Resident memory | `ps -o rss`, sampled each second over the same 30 seconds; the average and the peak, in MB | Peak under 150 MB for the three Orbit-only states (spec 6.9). The panel's figure has no target |
| Launch to data | Time from starting the process to the mock's `GET /__mock/state` reporting an open event stream, polled every 50 ms by elapsed time. Two Release launches (the first cold) and one launch of the Debug build, built as `dev.sh` builds it, into `build/DerivedData` | Under 10 seconds for each launch (spec 11). The Debug figure is the one spec 11 names |

WindowServer's CPU is reported beside Ian's, with no target.

Launch to data needs no change in the app. The app logs nothing when it applies the first snapshot, so the script reads the nearest outside signal: the sync engine applies the snapshot and only then opens the event stream, and the mock reports `openStreams` on `GET /__mock/state`. A connection to the mock proves nothing, because the app's first request is `GET /me`, long before the snapshot. Before each launch the script waits until the mock reports no stream, and after stopping the app it waits again, so a stream left by one launch is never counted for the next. The output says which build each launch figure is from. It does not include the moment SwiftUI draws the data, and the first Release launch includes a cold start. If a tighter figure is wanted, the smallest app change is one `os.Logger` line with a public, item-free message ("first snapshot applied") where the store applies its first snapshot, read with `log stream --predicate 'subsystem == "ai.valliance.ian.desktop"'`. That is Dom's decision; it is not made.

The script puts its temporary files in one directory and removes it, and stops the mock and the app it started, on every exit, including a failure inside a command substitution and Ctrl-C. Its parsing of the mock's state and of `ps` is in `measure-lib.sh`, and `test-measure-lib.sh` checks it against fixed samples with no display and no build: run `scripts/test-measure-lib.sh`.

Acceptance (spec section 11) requires a fresh clone to show the `normal` scenario within ten seconds of running `dev.sh`, once the app is built. The first build takes a few minutes; D9 measures the ten seconds.

The generators run from `scripts/tools`, a package that pins `swift-openapi-generator` and XcodeGen, so every machine and CI use the same versions.

Scripts must work from a fresh clone with no Apple account, and must fail with a clear message when Xcode, Node 22 or pnpm is missing.

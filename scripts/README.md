# Scripts

| Script | Does |
|---|---|
| `dev.sh` | Starts the mock and opens the app against it. Arrives in D2 and D3 |
| `generate-contract.sh` | Regenerates `Packages/IanKit/Sources/Contract/Generated` and the JSON fixtures in `Packages/IanKit/Tests/ContractTests/Fixtures` from `contract/ian-desktop.v1.yaml`. The fixtures are the contract's `components.examples` |
| `generate-project.sh` | Regenerates `App/Ian.xcodeproj` from `App/project.yml`, and copies IanKit's `Package.resolved` into it, because Xcode ignores a local package's pins |
| `check-generated.sh` | Runs both generators and fails if any generated file differs from what is committed. CI runs it |

`dev.sh` starts the mock on port 4317, waits for it to answer, then builds and opens the app against it. Acceptance (spec section 11) requires a fresh clone to show the `normal` scenario within ten seconds of running it. Built across D2 and D3.

The generators run from `scripts/tools`, a package that pins `swift-openapi-generator` and XcodeGen, so every machine and CI use the same versions.

Scripts must work from a fresh clone with no Apple account, and must fail with a clear message when Xcode, Node 22 or pnpm is missing.

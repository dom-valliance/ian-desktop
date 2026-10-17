# Workflows

D1 adds three workflows. Dom owns the GitHub side (ADR 0007 in Lance applies here too); CI runs from the first push.

| Workflow | Runs | On |
|---|---|---|
| `macos.yml` | `swift-format lint`, `swift build` and `swift test` for IanKit, `xcodebuild build` for the app | macOS runner with Xcode 16 |
| `mock.yml` | `pnpm install --frozen-lockfile`, lint, typecheck and test in `mock/` | Ubuntu |
| `contract.yml` | OpenAPI lint of `contract/ian-desktop.v1.yaml` | Ubuntu |

Pin every action to a commit SHA, as Lance does. Before the first push, run each workflow's commands locally with the same binaries the workflow installs.

# Workflows

D1 adds three workflows. Dom owns the GitHub side (Lance ADR 0007 applies here too); CI runs from the first push. All three run on pull requests and on pushes to `main`, with read-only `contents` permission, and cancel an earlier run of the same ref.

| Workflow | Runs | On |
|---|---|---|
| `macos.yml` | Swift format lint, `swift build` and `swift test` for IanKit, the generated-code check, `xcodebuild build` for the app | `xcode-27` runner with Xcode 27.1, build 27A9275 (ADR 0010) |
| `mock.yml` | `pnpm install --frozen-lockfile`, lint (ESLint and Prettier), typecheck, the generated-schema drift check and test in `mock/` | Ubuntu 24.04 |
| `contract.yml` | `pnpm install --frozen-lockfile` and OpenAPI lint of `contract/ian-desktop.v1.yaml` | Ubuntu 24.04 |

## Steps

`macos.yml`, in order:

1. Check out the repository.
2. Select Xcode 27.1 with `xcode-select`.
3. Print `xcodebuild -version`, `swift --version` and `swift format --version`, so a formatting difference against a developer's toolchain can be diagnosed.
4. `swift format lint --recursive --strict Packages App scripts`
5. `swift build --package-path Packages/IanKit --force-resolved-versions`
6. `swift test --package-path Packages/IanKit --force-resolved-versions`
7. `scripts/check-generated.sh`, which regenerates the contract code, its fixtures, the Xcode project and the project's copy of IanKit's pins, and fails on drift.
8. `xcodebuild -project App/Ian.xcodeproj -scheme Ian -configuration Debug -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile build`

`mock.yml`, in order:

1. Check out the repository.
2. Set up Node from `.nvmrc`.
3. `corepack enable`
4. `pnpm install --frozen-lockfile` in `mock/`
5. `pnpm lint` in `mock/`
6. `pnpm typecheck` in `mock/`
7. `pnpm generate`, then `git diff --exit-code -- src/generated` and an empty `git status --porcelain -- src/generated`, in `mock/`; fails when the committed Zod schemas differ from what the contract generates, or a file is new
8. `pnpm test` in `mock/`

`contract.yml`, in order:

1. Check out the repository.
2. Set up Node from `.nvmrc`.
3. `corepack enable`
4. `pnpm install --frozen-lockfile` in `contract/`
5. `pnpm lint` in `contract/`

## Rules

- Every action is pinned to a full commit SHA with its version in a trailing comment, as Lance does. Checkout runs with `persist-credentials: false`.
- Every pnpm step sets `working-directory:` to its package, so corepack reads the pnpm version from that package's `packageManager` field; there is no root `package.json`. Locally, `pnpm --dir` works with pnpm 12.4.2 on the path, as AGENTS.md lists.
- Before the first push, run each workflow's commands locally with the same binaries the workflow installs.

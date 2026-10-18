# 0012. Test support library and declared imports

Date: 2026-10-18
Status: Accepted

## Context

`Packages/IanKit/README.md` fixes the import graph of the shipped targets, and spec section 2 limits dependencies to the swift-openapi packages and swift-snapshot-testing. D3 needed four things the graph does not mention:

- Tests in `AuthTests`, `ClientTests` and `StoreTests` share a stubbed `URLProtocol`, a manual clock, a scripted `DesktopService` and invented fixtures. One copy per test target would drift.
- The generated client and the request middleware import `HTTPTypes`. It is a dependency of `swift-openapi-runtime` and resolved already (version 1.8.0 in `Package.resolved`), but IanKit did not declare it, so the build leaned on a transitive module.
- Auth needs the Network framework for the loopback listener on a random `localhost` port (spec section 8), and CryptoKit for the SHA-256 of the PKCE challenge.
- Client and Store log through `os.Logger` (AGENTS.md non-negotiable 5), and Store is `@Observable`, which is the Observation framework.

## Decision

- Add `TestSupport`, a library target under `Tests/TestSupport` that only test targets depend on. No product includes it, so it never ships.
- Declare `swift-http-types` in `Package.swift` with `.upToNextMinor(from: "1.8.0")` and add its `HTTPTypes` product to `Contract` and `Client`. It is already part of the resolved graph of the spec's packages, so no new code is fetched and the pinned version does not change.
- Allow these system frameworks, which add no package: Network and CryptoKit in `Auth`, `os` in `Client` and `Store`, Observation in `Store`.

The README import column is updated to match.

## Consequences

- The dependency graph is explicit, and a later change to `swift-openapi-runtime` that drops `HTTPTypes` does not break the build silently.
- Test helpers have one home. Changing a helper's behaviour is a change to every suite that uses it.
- `Package.resolved` is unchanged. The app project's copy follows it through `scripts/generate-project.sh`.

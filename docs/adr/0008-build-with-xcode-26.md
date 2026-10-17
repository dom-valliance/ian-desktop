# 0008. Build with Xcode 26

Date: 2026-10-17
Status: Accepted

## Context

Spec section 2 and AGENTS.md name Xcode 16 as the toolchain. Checked on 17 October 2026:

- The current releases of the packages spec section 2 names declare newer Swift tools versions: `swift-openapi-generator` 1.14.1 and `swift-openapi-runtime` 1.13.1 need 6.2; `swift-openapi-urlsession` 1.3.2 needs 6.1. Xcode 16.4 ships Swift 6.1, so it would hold the generator at 1.13.1 and the runtime at 1.12, and transitive packages such as `swift-collections` would need hand pins to releases older than their current ones.
- The development Mac runs macOS 26.5 with Swift 6.3.2.
- GitHub's `macos-26` runner image defaults to Xcode 26.6 (image of 7 September 2026).

## Decision

Ian builds with Xcode 26 (Swift 6.2 or later). CI selects Xcode 26.6 on the `macos-26` image. Swift 6 language mode with complete strict concurrency is unchanged, and the deployment target stays macOS 14 (spec Q1). Package manifests keep `swift-tools-version` 6.0, the lowest that expresses them.

## Consequences

- Dependencies track their current releases, resolved and pinned in each `Package.resolved`.
- The app still runs on macOS 14. Any API newer than macOS 14 needs an availability check; the compiler enforces it.
- A developer needs Xcode 26, which runs on macOS 15.6 or later.
- AGENTS.md and `.github/workflows/README.md` say Xcode 26. Spec section 2 is left as written; this ADR corrects it.
- Revisit when GitHub moves the `macos-26` default past Xcode 26.6 or publishes an image with Xcode 27.

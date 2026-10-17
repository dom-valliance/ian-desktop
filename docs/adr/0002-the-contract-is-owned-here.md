# 0002. The contract is owned here and versioned

Date: 2026-10-17
Status: Accepted

## Context

The client and Lance move at different speeds and are built by different engineers in parallel (spec section 10). Lance has no versioned contract for an external client today; its web app talks tRPC. Spec section 14 names contract drift as the first risk.

## Decision

`contract/ian-desktop.v1.yaml` (OpenAPI 3.1) is the source of truth for version 1. Swift models are generated from it with `swift-openapi-generator`; the mock validates every response against it in tests. Lance implements a `/desktop/v1` façade that conforms to a pinned tag of this repository (`contract-v1.MINOR.PATCH`), checked by a conformance test in Lance CI (DL6). A breaking change means `v2`, never an edit to `v1`.

## Consequences

- Drift fails a build in one of three places: Swift generation, the mock's response validation, or Lance's conformance test.
- Additive changes raise MINOR and old clients ignore what they do not know. Clients must therefore tolerate unknown fields and unknown event types.
- During a move to `v2` the mock serves both versions, and Lance serves both until `minClientVersion` passes the last `v1` client.
- The contract is reviewed here first, then pinned in Lance. A Lance-side need starts as a pull request to this repository.

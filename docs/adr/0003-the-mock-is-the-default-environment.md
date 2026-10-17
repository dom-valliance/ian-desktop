# 0003. The mock server is the default environment

Date: 2026-10-17
Status: Accepted

## Context

Dom chose a mock server by default, with a switch to Lance dev, on 16 October 2026 (spec section 0). The Lance façade (DL1 to DL4) lands after Phase 5 and may lag the client. Debug builds run unsigned on engineers' Macs (spec section 14).

## Decision

The app starts against the mock unless a profile says otherwise. The mock serves invented data only. A Debug build compiles two profiles, `mock` (`http://localhost:4317/desktop/v1`, `Bearer dev-local`) and `lance-dev` (the Lance dev api with PKCE sign-in). The profile is chosen in Settings or with the launch argument `-IanEnvironment lance-dev`; changing it signs out and clears the store. No production profile exists until the fast follow, and then only in Release builds.

## Consequences

- Work packages D1 to D9 complete against the mock without any Lance package merged.
- Every view and every scenario can be shown, tested and snapshotted with no real data in reach.
- The mock must behave like Lance where the client can tell: `202` with a correlation id for proposals, whole-object events, `409`, `410` and `426`. When Lance's behaviour is learned to differ, the mock changes first.
- The expanded client's header names the environment whenever it is not `mock`, so real data is never mistaken for fixtures.

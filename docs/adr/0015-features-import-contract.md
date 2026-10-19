# 0015. Features may import the generated contract types

Date: 2026-10-19
Status: Accepted

## Context

`Packages/IanKit/README.md` fixes the import graph of the shipped targets, and a change to it needs an ADR. The `Features` row allows `Store`, `Surface` and `Attention`. D5 builds the Today view and the one action component that every later view reuses, and both read the server's objects: an item's `actions`, each action's `confirm` and `input`, the item's `kind`, `unit`, `horizon` and `meta`, and `today.lists`, `today.field` and `views.counts`.

Features cannot read those through `Store` alone. `StoreState` holds the generated types as they arrive, and wrapping every one in a hand-written mirror would copy the contract into a second place that drifts from it. `Surface` avoided the question by defining its own small model (ADR 0013), because it draws a few fields. The views draw nearly all of them.

## Decision

`Features` may import `Contract`, for the generated value types in `Components.Schemas` only. It never imports `Client` and never touches the generated `Client` type or its operations. Every call to the server goes through `Store`: actions through `IanStore.run(actionID:on:until:note:)`, and the sign-in through `IanStore.signIn()`.

`Package.swift` adds `Contract` to the `Features` target. `Features` also draws with SwiftUI and holds its view state in `@Observable` classes, so it names SwiftUI and Observation, the same system frameworks `Surface` already uses (ADR 0013). The README import column is updated to match.

## Consequences

- Views read `Item`, `ItemAction`, `Today`, `Views` and their parts directly, so a contract change shows up as a compile error in the view that uses it.
- A view cannot make a request. The one write path stays in `Store`, where the pending mark and the `409` handling live (ADR 0001).
- Reviewers check that no `Features` file mentions `Client`, `Operations` or an HTTP type.

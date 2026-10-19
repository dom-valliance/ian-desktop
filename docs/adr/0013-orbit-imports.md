# 0013. System frameworks for the Orbit and suppression

Date: 2026-10-19
Status: Accepted

## Context

`Packages/IanKit/README.md` fixes the import graph of the shipped targets, and a change to it needs an ADR (ADR 0012 did the same for D3). D4 needs frameworks the graph does not list:

- `Attention` reads the camera through CoreMediaIO's "device is running somewhere" property (spec 6.5), logs a failed registration through `os.Logger` (AGENTS.md rule 5: ids only), and holds the user's pause and the camera state in an `@Observable` class so views update.
- `Surface` builds `NSPanel`s and `NSMenu`s (AppKit, ADR 0005), draws with SwiftUI `Canvas` and `TimelineView` (ADR 0004), and its controller is `@Observable`.

## Decision

Allow these system frameworks, which add no package:

- `Attention`: CoreMediaIO, `os` and Observation.
- `Surface`: AppKit, SwiftUI and Observation.

`Surface` still imports no `Contract` module. It reads the store's state by inference and defines its own `OrbitModel.Kind`, so the Store and Attention rows of the graph are unchanged. The README import column is updated to match.

## Consequences

- The graph stays explicit, and a later change to what `Attention` or `Surface` may import still needs an ADR.
- CoreMediaIO links only into `Attention`, so a target that needs no camera never loads it.
- No dependency is added and `Package.resolved` is unaffected by this decision.

# 0007. XcodeGen keeps the Xcode project

Date: 2026-10-17
Status: Accepted

## Context

AGENTS.md Q15 left open how the Xcode project is kept. A hand-edited `project.pbxproj` is a large generated plist: its merge conflicts are hard to resolve, and a setting changed in Xcode's editor is easy to miss in review. The app target is deliberately thin (`App/README.md`); every view and behaviour lives in the `IanKit` Swift package, so the project file has little to say. Acceptance (spec section 11) requires a fresh clone to build with no Apple setup, which rules out depending on a tool being installed before Xcode can open the project.

## Decision

`App/project.yml` is the source of the project. XcodeGen 2.46.0, pinned in the tools package `scripts/tools/Package.swift` and run with `scripts/generate-project.sh`, writes `App/Ian.xcodeproj`. The generated project is committed, so a fresh clone opens and builds in Xcode without XcodeGen. `scripts/check-generated.sh` regenerates it in the macOS workflow and fails when the result differs from the commit. The same tools package pins `swift-openapi-generator`, whose committed output is checked the same way.

## Consequences

- Targets, build settings, schemes and Info.plist keys change in `project.yml`, never in Xcode's editor. A change made in Xcode is lost on the next generation and fails CI until it is moved into `project.yml`.
- Adding a file under `Packages/IanKit` never touches the project, because the app links the package as a local reference.
- XcodeGen is built from source by SwiftPM, so the first run of a script takes about a minute and needs no Homebrew.
- Moving to a newer XcodeGen is a pin change in `scripts/tools/Package.swift` plus a regenerated project in the same commit.

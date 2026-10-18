# 0010. Build with Xcode 27.1

Date: 2026-10-18
Status: Accepted. Supersedes 0008.

## Context

ADR 0008 set Xcode 26 as the toolchain, with CI on Xcode 26.6, and said to revisit when GitHub published an image with Xcode 27. By 18 October 2026:

- The development Mac runs macOS 27.0.1. The Mac App Store offers only the latest Xcode, and Intune deployed Xcode 27.1, build 27A9275, with Swift 6.4.
- GitHub's `xcode-27` runner image (macOS 27.0.1, image of 12 October 2026) carries the same build, 27A9275, at `/Applications/Xcode_27.1.app`. GitHub announced the image generally available on 15 October 2026.
- Building locally with one Xcode and in CI with another lets Xcode pin packages that the older toolchain cannot read, and lets swift-format disagree between the two. The 6.4 swift-format refused the full `.swift-format` dumped by 6.3, because a nested key it now requires was missing.
- Xcode ignores a local package's `Package.resolved`. Xcode 27.1 wrote no pins for the app at all, since the project names no remote package directly. A probe showed that it does honour a `Package.resolved` placed in the project's workspace, with `-onlyUsePackageVersionsFromResolvedFile`.
- Under Xcode 27.1, plain `swift test` finds Swift Testing; the Command Line Tools flags in the D1 phase log are no longer needed.

## Decision

Ian builds with Xcode 27.1, build 27A9275. CI runs on the `xcode-27` image and selects `/Applications/Xcode_27.1.app`. Swift 6 language mode with complete strict concurrency is unchanged, the deployment target stays macOS 14 (spec Q1), and package manifests keep `swift-tools-version` 6.0.

Two build details change with it:

- `.swift-format` holds only the keys that differ from swift-format's defaults (`version` and `lineLength`), so a newer swift-format can read it.
- `scripts/generate-project.sh` copies `Packages/IanKit/Package.resolved` into `App/Ian.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`. The copy is committed and drift-checked by `scripts/check-generated.sh`, and CI builds the app with `-onlyUsePackageVersionsFromResolvedFile`. IanKit's file is the one source of pins for SwiftPM and Xcode alike.

## Consequences

- Local and CI builds use the same compiler, SDK and swift-format.
- A developer needs macOS 26.6 or later on Apple silicon, Xcode 27's minimum.
- A dependency change is resolved in `Packages/IanKit` and regenerated, never resolved in Xcode's editor.
- AGENTS.md, the workflow README and the scripts say Xcode 27. Spec section 2 is left as written; this ADR and ADR 0008 correct it.
- Moving to a newer Xcode means a new ADR, the same build installed locally and in CI, and the `xcode-select` path changed in `macos.yml` in one commit.

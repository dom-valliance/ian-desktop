# Architecture decision records

One file per decision, numbered, never edited after acceptance except to add a `Superseded by` line. Template in [0000-template.md](0000-template.md). Acceptance evidence for each work package is kept in [0000-phase-log.md](0000-phase-log.md).

Numbers here are this repository's own. Lance's ADRs are cited as "Lance ADR NNNN".

| # | Title | Status |
|---|---|---|
| 0001 | [The client is thin and holds no write power](0001-the-client-is-thin.md) | Accepted |
| 0002 | [The contract is owned here and versioned](0002-the-contract-is-owned-here.md) | Accepted |
| 0003 | [The mock server is the default environment](0003-the-mock-is-the-default-environment.md) | Accepted |
| 0004 | [Rendering stays in SwiftUI](0004-rendering-stays-in-swiftui.md) | Accepted, amended by 0017 and 0018 |
| 0005 | [Window model](0005-window-model.md) | Accepted |
| 0006 | [Privacy on screen](0006-privacy-on-screen.md) | Accepted |
| 0007 | [XcodeGen keeps the Xcode project](0007-xcodegen-keeps-the-project.md) | Accepted |
| 0008 | [Build with Xcode 26](0008-build-with-xcode-26.md) | Superseded by 0010 |
| 0009 | [Contract v1 fills gaps in spec section 5](0009-contract-v1-fills-gaps-in-the-spec.md) | Accepted |
| 0010 | [Build with Xcode 27.1](0010-build-with-xcode-27.md) | Accepted |
| 0012 | [Test support library and declared imports](0012-test-support-and-declared-imports.md) | Accepted |
| 0013 | [System frameworks for the Orbit and suppression](0013-orbit-imports.md) | Accepted |
| 0014 | [System windows are swept](0014-system-windows-are-swept.md) | Accepted |
| 0015 | [Features may import the generated contract types](0015-features-import-contract.md) | Accepted |
| 0016 | [The field's angle and the pane sizes are saved](0016-field-angle-and-pane-sizes-are-saved.md) | Accepted |
| 0017 | [The Orbit's motion runs in Core Animation](0017-orbit-motion-runs-in-core-animation.md) | Accepted |
| 0018 | [The field draws with Core Graphics on a display link](0018-the-field-draws-with-core-graphics-on-a-display-link.md) | Accepted |

Later numbers go to deviations as they arise.

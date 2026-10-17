# App

The Xcode project and the macOS app target `Ian`. Built in D1.

Keep this target thin: the `@main` entry point, `Info.plist`, entitlements and assets. Every view, model and behaviour lives in `Packages/IanKit`, so the project file changes rarely and tests run through SwiftPM.

| Setting | Value |
|---|---|
| Product name | `Ian` |
| Bundle identifier | `ai.valliance.ian.desktop`, `ai.valliance.ian.desktop.dev` for Debug |
| Minimum macOS | 14 |
| Signing in version 0 | Sign to Run Locally (ad hoc). No team, no provisioning profile |
| Build configurations | Debug carries the `mock` and `lance-dev` profiles. No production profile exists until the fast follow (ADR 0003) |

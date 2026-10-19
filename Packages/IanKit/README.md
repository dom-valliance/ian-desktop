# IanKit

All logic and views for Ian, as one Swift package. Swift 6 language mode with strict concurrency, macOS 14.

Each folder under `Sources/` is one SwiftPM target.

| Target | Holds | May import | Package |
|---|---|---|---|
| `Contract` | Types and client generated from `contract/ian-desktop.v1.yaml` by `swift-openapi-generator`. Nothing hand-written except the generator config | OpenAPIRuntime, HTTPTypes | D1, D3 |
| `Auth` | Token providers: `dev-local` bearer for the mock, PKCE loopback for `lance-dev`, Keychain storage | Foundation, Security, Network, CryptoKit | D3 |
| `Client` | HTTP through `swift-openapi-urlsession`, the SSE reader with `Last-Event-ID` replay and backoff, environment profiles | Contract, Auth, OpenAPIRuntime, OpenAPIURLSession, HTTPTypes, os | D3 |
| `Store` | Observable state, the reducer that applies a snapshot and each event, pending marks on actions | Contract, Client, Observation, os | D3 |
| `Attention` | Local notifications, the attention ladder, suppression (camera, external meeting, quiet hours, user pause), the session heartbeat | Store, CoreMediaIO, os, Observation | D4, D8 |
| `Surface` | Orbit and Pillars renderers (`Canvas` in `TimelineView`), the window model (`NSPanel`s, menu bar extra) | Store, Attention, AppKit, SwiftUI, Observation | D4, D5 |
| `Features` | The seven views | Store, Surface, Attention | D5 to D7 |

The import column is the intended dependency graph. D1 encodes it in `Package.swift`; a change to it needs an ADR (0012 and 0013 record the system frameworks).

Rules that apply here (ADR 0001):

- No target computes pressure, horizon, grouping, eligibility or a policy outcome. If a view seems to need one, the contract is missing a field.
- Buttons come from an item's `actions`, in the order sent. No view hard-codes an action.
- Nothing is written to disk except tokens in the Keychain and the client settings in `UserDefaults` listed in spec 6.4.

Tests live in `Tests/`, one test target per source target (`StoreTests`, `SurfaceTests` and so on). `Tests/TestSupport` is a library of test helpers shared by them (a stubbed `URLProtocol`, a manual clock, a scripted `DesktopService`, invented fixtures); no product depends on it. Snapshot tests use `swift-snapshot-testing`.

# Contract

`ian-desktop.v1.yaml` is the OpenAPI 3.1 document for `/desktop/v1` and the single source of truth for version 1 (ADR 0002). The first draft arrives in D1, from spec section 5.

- Swift types in `Packages/IanKit/Sources/Contract` are generated from it. The mock validates every response against it in tests.
- Lance pins a tag of this repository and runs a conformance test against it in CI (Lance package DL6).
- Tags take the form `contract-v1.MINOR.PATCH`. An additive change (a new optional field, a new endpoint, a new event type the client may ignore) raises MINOR. A fix to descriptions or examples raises PATCH.
- A breaking change never edits this file. It starts `ian-desktop.v2.yaml`, and the mock serves both versions during the switch (spec section 14).
- CI lints the document on every pull request.

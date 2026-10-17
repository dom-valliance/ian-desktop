# Contract

`ian-desktop.v1.yaml` is the OpenAPI 3.1 document for `/desktop/v1` and the single source of truth for version 1 (ADR 0002). It follows spec section 5, with the departures recorded in ADR 0009.

- Swift types in `Packages/IanKit/Sources/Contract/Generated` are generated from it by `scripts/generate-contract.sh` and committed. `scripts/check-generated.sh` fails CI when they drift. The mock validates every response against it in tests.
- Lance pins a tag of this repository and runs a conformance test against it in CI (Lance package DL6).
- Tags take the form `contract-v1.MINOR.PATCH`. An additive change (a new optional field, a new endpoint, a new event type the client may ignore) raises MINOR. A fix to descriptions or examples raises PATCH. A new enum value is breaking.
- A breaking change never edits this file. It starts `ian-desktop.v2.yaml`, and the mock serves both versions during the switch (spec section 14).

## Lint

```
pnpm --dir contract install --frozen-lockfile
pnpm --dir contract lint
```

Redocly CLI with `recommended-strict` (`redocly.yaml`), so a warning fails the lint. Examples are validated against their schemas. `.redocly.lint-ignore.yaml` exempts only `StreamEvent` from the unused-component rule, because event payloads travel inside the `text/event-stream` body. The `contract.yml` workflow runs the same two commands.

## Writing to it

- Examples use `[CLIENT]` and `[PERSON]` placeholders and `.invalid` hosts. No real data.
- Times are UTC with milliseconds. Reuse `DateTime`; a nullable time repeats its pattern inline. Quote every time in an example, and quote `yes`, `no`, `on` and `off`: the fixture extractor reads YAML 1.1, which would turn them into booleans.
- A property that may be missing a referenced value is optional, never `oneOf` a `$ref` and `null`: the Swift generator drops such a property without an error.
- Both `oneOf` unions (`ItemDetail`, `StreamEvent`) carry a discriminator `mapping`, which the Swift generator needs. Ajv rejects `mapping`; a validator in the mock must treat `discriminator` as an annotation. The members' single-value `kind` and `type` enums keep `oneOf` unambiguous without it.
- Nothing in the schema ties `item.kind` to `item.detail.kind`, or a field cell's `unitId` to `field.units`. The mock's tests assert both.

## What

One or two sentences on what this pull request changes.

## Why

The work package (D1 to D9), spec section or ADR it comes from.

## On screen

What a person sees that they did not before, and in which scenario of the mock. Say "nothing" for changes with no visible effect.

## Verification

Commands run and their results: `swift format lint`, `swift build`, `swift test`, `scripts/check-generated.sh`, `xcodebuild build`, the contract lint when `contract/` changed, and the mock's lint, typecheck and test when `mock/` changed.

## Checklist

- [ ] Conventional commit title, at most 72 characters
- [ ] No real data in code, fixtures, snapshots, screenshots or this description
- [ ] No computed pressure, horizon, grouping or eligibility in IanKit; buttons come from `actions`
- [ ] No em dashes in code, comments, copy or docs
- [ ] ADR added under `docs/adr/` if this deviates from the spec
- [ ] Phase log updated when a package's checks pass

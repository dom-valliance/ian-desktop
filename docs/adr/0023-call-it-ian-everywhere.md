# 0023. Call it Ian everywhere

Date: 2026-10-21
Status: Accepted, amends 0003

## Context

The principal sees Ian, but the environment profile, its launch argument, its build settings, the environment name in the header and Settings, and the card link still said Lance. Dom decided on 21 October 2026, during D9's hand check, that what the principal and the developer see says Ian, identifiers included. The server stays Lance wherever something describes the server (AGENTS.md, B1). Work package N1 carries the change out. It amends ADR 0003, whose Decision names `lance-dev` and `-IanEnvironment lance-dev`; read those as `ian-dev`.

## Decision

Dom decided this on 21 October 2026.

**What changed.**

- The profile id `lance-dev` is `ian-dev` in `EnvironmentProfile`, the `-IanEnvironment` launch argument, the saved `IanEnvironment` value, the store's profile switcher and the tests. The diagnostics report prints the profile id, so it now prints `ian-dev`. The Swift case and factory are `ianDev`.
- The environment reads "Ian dev" in Settings (picker and confirmation) and the header. The card link reads "Open in Ian". Sign-in messages say that the dev server's sign-in is not registered yet and name no product.
- The build settings are `IAN_DEV_TENANT_ID`, `IAN_DEV_CLIENT_ID` and `IAN_DEV_SCOPE` in `App/project.yml`, and the Info.plist keys are `IanDevTenantID`, `IanDevClientID` and `IanDevScope`. The generated project is regenerated.
- A saved `IanEnvironment` of `lance-dev` from an earlier build is read as `ian-dev` and rewritten once, so nobody falls back to the mock silently. A launch argument of `lance-dev` is read as `ian-dev` and is never saved. Only `requestedName` maps the old name, so the profile switcher refuses `lance-dev` and can never save it. Tests use scratch defaults.
- AGENTS.md follows (naming table, toolchain section, the profile gotcha) and gains erratum E7: the spec says `lance-dev`, "Lance dev" and "Open in Lance", and the profile is `ian-dev`, shown as "Ian dev", with the link "Open in Ian". The spec text is not edited. The `IAN_LANCE_*` settings came from D3, not the spec.

**The Keychain.** The token store keys its item by the profile, `<bundle id>.<profile id>`, so the Debug build's new item is `ai.valliance.ian.desktop.dev.ian-dev`, account `tokens`. An item under the old `ai.valliance.ian.desktop.dev.lance-dev` service exists only if a developer filled both sign-in build settings locally (they are empty in the repository, erratum E2) and signed in, because tokens are saved at the exchange. Nothing reads or clears such an item after N1. The impact is low: it stays in the developer's own login Keychain and its refresh token lapses. No migration is built. `docs/run-local.md` gives the command that deletes it. Nothing logs a token value.

**What stays Lance, and why.**

- **The contract's `links.lance` field.** Renaming a field breaks contract v1, and a breaking change is `v2` (non-negotiable 3). The client reads it as it is and shows the link as "Open in Ian". The contract's descriptions of the server stay as written.
- **The server's own names:** the Lance repository (`~/workspace/ian`), packages DL1 to DL6, the `Lance.User` app role, the `Lance (Valliance)` registration, the dev api host `ca-lance-api-dev...` and its resource group, the ledger marker `surface: 'desktop'` in Lance's ledger, and citations of Lance's ADRs. They are named by Lance and cannot be renamed from here.
- **The mock's model of the server.** `mock/src/domain/lance.ts`, its types and its tests. The mock simulates Lance, and the code says so.
- **Documents about the server:** `docs/companion/lance-track.md` and `docs/context/lance-context.md`, and comments and docs that describe what Lance does or decides. Where they named the profile they now say `ian-dev`.
- **Records:** the spec text (corrected by erratum E7), the phase log, ADRs 0001 to 0022 (0003 is marked amended), the work-package plan's entries for earlier packages (`lance-dev`, "Open in Lance" and "Lance dev" in D3, D5 and D9) and the design canvas, which is source material. Records are not rewritten.
- **Other repository references:** `.github/CODEOWNERS` and the workflows' README say where a rule was copied from Lance.

## Consequences

A search of `Packages`, `App`, `scripts`, the mock, the workflows and the current docs finds "Lance" only in the places above. Anyone who scripted `-IanEnvironment lance-dev` keeps working. A change to the contract's field name waits for a `v2`.

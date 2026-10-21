# 0023. Call it Ian everywhere

Date: 2026-10-21
Status: Accepted

## Context

The principal sees Ian, but the environment profile, its launch argument, its build settings, the environment name in the header and Settings, and the card link still said Lance. Dom decided on 21 October 2026, during D9's hand check, that what the principal and the developer see says Ian, identifiers included. The server stays Lance wherever something describes the server (AGENTS.md, B1). Work package N1 carries the change out.

## Decision

Dom decided this on 21 October 2026.

**What changed.**

- The profile id `lance-dev` is `ian-dev` in `EnvironmentProfile`, the `-IanEnvironment` launch argument, the saved `IanEnvironment` value, the store's profile switcher, the diagnostics report and the tests. The Swift case and factory are `ianDev`.
- The environment reads "Ian dev" in Settings (picker and confirmation), the header and the diagnostics report. The card link reads "Open in Ian". Sign-in messages say that the dev server's sign-in is not registered yet and name no product.
- The build settings are `IAN_DEV_TENANT_ID`, `IAN_DEV_CLIENT_ID` and `IAN_DEV_SCOPE` in `App/project.yml`, and the Info.plist keys are `IanDevTenantID`, `IanDevClientID` and `IanDevScope`. The generated project is regenerated.
- A saved `IanEnvironment` of `lance-dev` from an earlier build is read as `ian-dev` and rewritten once, so nobody falls back to the mock silently. A launch argument of `lance-dev` is read as `ian-dev` and is never saved. Tests use scratch defaults.
- AGENTS.md follows (naming table, toolchain section, the profile gotcha) and gains erratum E7: the spec says `lance-dev` and `IAN_LANCE_*`, and the profile is `ian-dev`. The spec text is not edited.

**The Keychain.** The token store keys its item by the profile, `<bundle id>.<profile id>`, so the new profile reads `ai.valliance.ian.desktop.ian-dev`. An item under the `.lance-dev` service cannot exist. Sign-in to the dev server cannot succeed before Lance package DL1 (erratum E2): with the client id and scope empty, sign-in fails before it opens a browser, and no token is ever stored. No migration or removal is needed. If an earlier build had stored one, it would stay unread under its old service; nothing logs a token value either way.

**What stays Lance, and why.**

- **The contract's `links.lance` field.** Renaming a field breaks contract v1, and a breaking change is `v2` (non-negotiable 3). The client reads it as it is and shows the link as "Open in Ian". The contract's descriptions of the server stay as written.
- **The server's own names:** the Lance repository (`~/workspace/ian`), packages DL1 to DL6, the `Lance.User` app role, the `Lance (Valliance)` registration, the dev api host `ca-lance-api-dev...` and its resource group, the ledger marker `surface: 'desktop'` in Lance's ledger, and citations of Lance's ADRs. They are named by Lance and cannot be renamed from here.
- **The mock's model of the server.** `mock/src/domain/lance.ts`, its types and its tests. The mock simulates Lance, and the code says so.
- **Documents about the server:** `docs/companion/lance-track.md` and `docs/context/lance-context.md`, and comments and docs that describe what Lance does or decides. Where they named the profile they now say `ian-dev`.
- **Records:** the spec text (corrected by erratum E7), the phase log, ADRs 0001 to 0022 and the design canvas, which is source material. Records are not rewritten.
- **Other repository references:** `.github/CODEOWNERS` and the workflows' README say where a rule was copied from Lance.

## Consequences

A search of `Packages`, `App`, `scripts`, the mock, the workflows and the current docs finds "Lance" only in the places above. Anyone who scripted `-IanEnvironment lance-dev` keeps working. A change to the contract's field name waits for a `v2`.

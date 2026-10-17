# Companion track in Lance

What Lance must build before the `lance-dev` profile works, from spec section 9, with the gaps found while preparing this repository. This work runs in a Lance session, on a Lance branch, under Lance's `AGENTS.md`; nothing here is changed from this repository. Lance's pointer back to this file is `docs/plans/desktop.md` in Lance.

Every package lands behind `FF_DESKTOP_API`, default off.

| # | Package | Depends on | Size |
|---|---|---|---|
| DL1 | `/desktop/v1` façade: bearer from the new public client, `Lance.User` role, principal from `oid`, `withPrincipal` on every call, problem+json errors, `minClientVersion` from config | Phase 5 | 1.5 days |
| DL2 | Today aggregation: pressure, horizon, interim unit grouping, Orbit selection, a nightly per-principal median job in the registry | DL1 | 1.5 days |
| DL3 | Desktop event stream: per-principal ids, 24-hour replay, whole-object payloads, heartbeat | DL1 | 1 day |
| DL4 | Action mapping: each offered action resolved to an existing procedure, task Done to a `complete_task` proposal, `surface: 'desktop'` on every ledger payload, no new ledger kinds | DL1 | 1 day |
| DL5 | Surface sessions under RLS, arbitration in the delivery path (desktop active wins, Slack after ten idle minutes or no session), one push budget across surfaces | DL3 | 1 day |
| DL6 | Conformance test in CI against the contract at a pinned `ian-desktop` tag | DL1 to DL4 | 0.5 days |

## Gaps to close in DL1

**The Lance api exposes no scope.** The `Lance (Valliance)` registration has web redirect URIs and Graph permissions only, and the api accepts bearer tokens whose audience is the Lance client id (`apps/api/src/auth/entra.ts`). The desktop client needs a delegated scope to request. DL1 adds one under Expose an API, then checks `requestedAccessTokenVersion` in the registration's manifest: at 2, a token for the new scope carries the Lance client id as its audience and the existing check accepts it; at 1 or unset, it carries the Application ID URI, and the api must accept that audience and the matching issuer as well. Record the scope string in Lance's Entra runbook and in this repository's `lance-dev` profile configuration.

**The public client does not exist.** Register `Ian Desktop (dev)`: single tenant, platform "Mobile and desktop applications", redirect `http://localhost` (Entra matches loopback redirects on any port for public clients), "Allow public client flows" off because device code is not used, delegated permission on the new Lance scope with admin consent. Users still need the `Lance.User` role on the Lance enterprise application, which the api already checks. Add both to Lance's `docs/runbooks/entra-setup.md` and its known-values table, and read the ids from the CLI rather than asking Dom (a Lance lesson).

**The dev host is not in the known-values table.** The spec points there; the table lists no hostname. The dev api host is `ca-lance-api-dev.graygrass-c682ce2c.uksouth.azurecontainerapps.io` (from Lance's Entra runbook). Add a row for it to the deploy runbook's table, with the command that reads it:

```
az containerapp show -g rg-lance-dev -n ca-lance-api-dev --query properties.configuration.ingress.fqdn -o tsv
```

## Notes for the other packages

- **DL2.** The field cell carries `kind`, the kind of its highest-pressure item (this repository's AGENTS.md Q16), so the client chooses no colour. Pressure is versioned in Lance; the version could travel in `/today` so a client can show which formula drew the field.
- **DL2.** The median job runs inside `withPrincipal` per principal, and goes in the job registry (Lance ADR 0025).
- **DL3.** Event ids are per principal and strictly increasing. Beyond 24 hours the stream answers `410` and the client refetches the snapshot.
- **DL4.** The client sends back whatever action id it was given. An id that no longer applies answers `409` with the current item, never a silent success.
- **DL4.** Confidence travels with its source: `lev_trusted`, `lev_untrusted` or `self_report`. The Lev briefing's "ADR 0037" needs a new number in Lance, since 0036 and 0037 are taken by the commitments ADRs.
- **DL6.** Pin a `contract-v1.MINOR.PATCH` tag. A Lance-side need for a new field starts as a pull request to `ian-desktop`, then a new tag, then the pin moves.

## Gaps found while writing contract v1

D1 read Lance on 17 October 2026 to match the contract's vocabulary (ADR 0009). These values are in the contract and not yet produced by Lance. File references are in Lance.

- **DL1.** Lance has no problem+json helper; 4xx bodies are `{ "error": "..." }` (`apps/api/src/server.ts`). The façade needs one, plus `426` from the `Desktop-Client-Version` header (a request without it is not checked). `Me.displayName` and `Me.contractVersion` are new; today's `me` returns the UPN. `POST /handoff` answers `404` while `capabilities.handoff` is false. Times leave the façade as UTC with milliseconds, as `toISOString` writes them.
- **DL2.** `/today` carries `lists` (the `now` ids in display order, then week and later groups keyed to field columns), `nowCount`, `urgentCount`, a `median` floored at 1, and each field cell's `working` beside `kind`. The snapshot carries `views`: sidebar counts and each view's ordered groups (Proposals by action class, soonest expiry first; Commitments in three tabs; Tasks by horizon then unit; Alerts by severity, P0 first).
- **DL2, attention.** Every item carries `attention` (`ambient`, `needs_you`, `urgent`, `stop`), the spec 6.6 rung decided in Lance. The item is sent again when its rung changes, for example a proposal 15 minutes from expiry.
- **DL3.** `item.removed` carries `outcome`, one line in the principal's voice. `agent.updated` carries today's cost with the agent. `views.updated` replaces the views whole. Item events precede the `today.updated` and `views.updated` that reflect them. `heartbeat` has no event id and is never replayed. A `Last-Event-ID` newer than the latest event, as well as one older than the window, answers `410`.
- **DL4, proposals.** `decisionTier` is computed by `evaluate()` (`packages/policy/src/evaluate.ts`) but not persisted; the façade needs it stored. Confidence lives in `policy_decisions.input.confidence`, not on the proposal. `actionClassLabel` and `targetSystemLabel` are display text the façade writes.
- **DL4, actions.** Every offered action carries `input` (`none`, `until`, `note`), and every item a `version` that the action call checks for `409`. Both `200` and `202` answer `{ correlationId }`, and at least one event on the item carries it. Alerts snooze as `mute` with whole hours, so the façade converts `until`. Commitments have no snooze today; offer it only once one exists.
- **DL4, commitments.** `chase.lastChasedAt` has no column (only `chaseCount` and `nextChaseAt`). The evidence source's `label` is display text. Direction maps `outbound` to `commitment_by` and `inbound` to `commitment_to`; "To confirm" is status `unconfirmed`.
- **DL4, tasks.** `project` is in the Notion payload (`projectIds`) but not in `TaskView`. `assignedToDom` becomes `assignee.isPrincipal`.
- **DL4, alerts.** `relatedItemIds` has no column; derive it from `dedupeKey` or provenance. `raisedAt` is `firstSeen`. `alertKindLabel` is display text. Lance uses P0 to P2; the contract's P3 stays unused until Lance raises one.
- **DL4, settings.** `liveEligible` and `liveOpensAt` exist only as the refusal in `assertLiveOpen` (`packages/ledger/src/control.ts`); the façade must expose them, and answer `422` to going live while not eligible.
- **DL4, agents.** Lance has no per-agent pause (only `jobs.enabled`, through Slack), no next run for agents and no last run for jobs. A pause or resume on an agent whose `pausable` is false answers `403`. The contract has one ceiling, the principal's `cost_ceiling_gbp`; Lance's agents view reads `config.cost.dailyCeilingGbp` instead, so the façade must use the principal's.
- **DL4, ledger.** No ledger payload carries `surface` today, and the decide path has no origin field (`packages/ledger/src/proposals.ts`). Adding `surface: 'desktop'` needs a place in each payload the façade writes.

## Fast-follow prerequisites (spec section 12)

None of these blocks version 0. Each should be checked before the fast follow is planned.

- **Conditional Access needs Entra ID P1.** Lance ADR 0020 found none in the tenant on 25 September 2026 (Microsoft 365 Business Standard). Requiring a compliant device for the Ian Desktop client depends on adding P1 or a plan that includes it.
- **`Lance Users` does not exist.** ADR 0020 assigns `Lance.User` to users directly, so the Intune assignment "Required for `Lance Users`" needs a group created for Intune targeting, kept in step with the app role list.
- **Intune and Platform SSO need Intune licences** for every targeted user and enrolled Macs.
- **Apple Developer Program, organisation type**, needs Valliance's D-U-N-S number and a person with authority to sign Apple's agreement.
- **A dedicated Key Vault** for the Developer ID certificates and the notary key, read by the release workflow through OIDC federation.

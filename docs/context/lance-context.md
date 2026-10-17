# Lance context the spec relies on

The spec cites items from three Lance planning briefings that are not in either repository. This file summarises the parts that shape the desktop client, as they stood on 17 October 2026. It is a snapshot: when it disagrees with Lance's own repository, Lance wins, and this file is corrected.

The full briefings live in the claude.ai project "Lance Personal Assistant" (`plans/Lance-Foundations-Backlog_Briefing_v1.md`, `plans/Lance-Playback-Changes_Briefing_v1.md`, `plans/Lance-Lev_Briefing_v1.md`) and in Dom's Cowork folder under `outputs/lance-assistant/`. They name clients and colleagues, which is why they stay out of this repository.

## Where Lance is

- The build order is Lance's [roadmap](../../../ian/docs/plans/roadmap.md): Phase 4 principal seam, Phase 5 multi-user, a pilot, then Phase 6 jobs, held until the orchestrator (F1) and the re-sequencing (A5) land.
- The desktop façade (DL1) depends on Phase 5 being accepted.
- On 13 October the team decided to build Ian and Val as a dedicated product, with two engineers and a product owner and an MVP six to eight weeks from team start. The desktop client is not in the proposed MVP cut. The spec places it in Should, beside G2 and G3; the product owner decides (M5), and it needs an entry in the decision register.

## Items the spec names

| Code | What it is | Status on 17 October | What it means for the client |
|---|---|---|---|
| B1 | The naming boundary. Ian and Val are internal names for the personal and team scopes of one agent; an external accelerator name is deferred | Open, recommendation recorded | User-facing copy says Ian. The API, roles and ledger keep Lance identifiers, and the code rename (B3) waits for the product name |
| C1 | One work item entity for tasks and commitments, superseding Lance ADR 0009's "no native tasks table" | Not built | The `Item` envelope abstracts over today's proposals, commitments, tasks and alerts, so the client does not change when `work_items` lands |
| C2 | Build `work_items` and migrate commitments | Not built | As C1 |
| C3 | Units of work: a principal's own groups of work items, lighter than a project, with the agent suggesting groups | Not built; the first candidate to drop to Should | Until it lands, Lance groups the field by project (`ABOUT` edge), then counterparty organisation, then Other (spec 5.4) |
| F1 | An orchestrator replaces the linear job runner; jobs become skills it invokes | Not built | `POST /handoff` stays unimplemented in Lance until F1 and F2 land; `capabilities.handoff` is false in `lance-dev` |
| F2 | Triggered execution is first class: one trigger routes to every job that applies | Not built | As F1 |
| G2 | Show every agent action, live and after the fact, for the person and the team | Not built | The Agents view shows runs, watchers, breakers and cost from `GET /agents`; a live action trail is G2's, not this client's |
| G3 | A sentence typed on a card fires the agent | Not built | "Hand to Ian" with an optional instruction is the desktop form of G3 |

## Lance decisions the client inherits

- **Non-negotiables 1 to 3** (Lance `AGENTS.md`): ledger first, models cannot write, policy is data and deletes are code. The client is one more surface that raises actions through existing procedures; it gains no write path of its own (ADR 0001, DL4).
- **Lance ADR 0009.** Tasks have one home, the Notion All Tasks database. A task's "Done" is a `complete_task` proposal; the policy engine decides whether it runs.
- **Lance ADR 0015.** Principals and row-level security. Every façade call runs inside `withPrincipal`.
- **Lance ADR 0020.** Access through the Entra app roles `Lance.User` and `Lance.Admin`, assigned to users directly because the tenant has no Entra ID P1. The groups `Lance Users` and `Lance Admins` were never created.
- **Lance ADR 0024.** Admins see health, never content. The Agents view shows the principal's own agents only.
- **Lance ADRs 0036 and 0037.** Commitments are edited, reopened and annotated by hand; inbound commitments need a definite recipient. These numbers are taken, which is why the Lev rule below needs a new one.

## Confidence sources (Lev)

The Lev briefing defines a proposal's confidence source as one of `lev_trusted`, `lev_untrusted` or `self_report`. The policy engine meets a `minConfidence` condition only when the source is `lev_trusted`. Proposals with no Lev decision keep their value, marked `self_report`. The briefing calls this ADR 0037; in Lance that number is taken (see the errata in AGENTS.md).

For the client, the Proposals card shows the value with its source label, as the Context artboard does ("Confidence 0.82, self-reported"). The client never treats one source as better than another; it shows what the server sends.

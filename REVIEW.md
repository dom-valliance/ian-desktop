# Code review rules

How to review changes in this repository. These rules apply to human reviewers and the automated reviewer alike.

- The standard is the [non-negotiables and conventions](AGENTS.md), the [spec](docs/spec.md) and the [ADRs](docs/adr/README.md). Every finding points to one of them or to a rule below.
- Label each finding with its severity. Give the file and line, what is wrong, and a concrete fix.

## Severity

| Severity | Meaning |
|---|---|
| **Blocking** | Must be fixed, or answered with a reason the human approver accepts |
| **Should fix** | Fix in this pull request unless the author gives a good reason not to |
| **Suggestion** | Optional improvement. The author decides |

## What to check, in priority order

1. **Real data and secrets** (Blocking, P0 for automated review)
   - Anything taken from the principal's mail, calendar, meetings, transcripts, tasks or Slack, in any file: Swift, mock fixtures, snapshot images, tests, logs, screenshots, docs or the pull request text. A fixture or snapshot that names a real client, counterparty, person or meeting is a leak.
   - Tokens, client secrets, signing material or notary keys anywhere. Version 0 has no secrets at all: the mock takes any `Bearer dev-...` token and the `lance-dev` client is public.
   - If found, say so plainly, and tell the author it must be removed from history, not only from the branch.
2. **Non-negotiables** (Blocking). What lint and tests can miss, by rule in [AGENTS.md](AGENTS.md#non-negotiables):
   - **Thin client:** arithmetic or sorting on `dueAt`, `severity`, `pressure` or counts that decides what the user sees; a hard-coded action id or label; a view choosing which buttons an item offers.
   - **Server settles state:** an item marked done, removed or moved before its event arrives; any queue of actions held for later.
   - **Contract:** hand edits to generated code; a field used that the contract does not define; a change to `v1` that breaks an existing client.
   - **Disk:** `FileManager` writes, `URLCache` or a non-ephemeral `URLSession`, `UserDefaults` keys outside spec 6.4 and ADR 0016, item text in `os.Logger` without `.private`, or in any log at all where an id would do.
   - **Screen:** a window or panel without `sharingType = .none`; item text visible on the Orbit, in a hover or in a notification while suppressed.
   - **Rendering:** a `TimelineView`, timer, display link or Core Animation animation that keeps running while hidden, occluded or suppressed; motion that ignores Reduce Motion; a rendering change without a `scripts/measure-cpu.sh` run.
   - **Accessibility:** an item or action reachable only through the field; a control without a VoiceOver label; urgency carried by colour alone.
3. **Spec and ADR drift** (Blocking)
   - An architectural deviation from the spec has an ADR in the same pull request. An accepted ADR is never edited, only superseded.
   - The work belongs to the package in hand, and its evidence is appended to [the phase log](docs/adr/0000-phase-log.md).
   - Docs, the plan and `AGENTS.md` agree with the code after the change.
4. **Concurrency and correctness** (Blocking)
   - Swift 6 strict concurrency holds. Every `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` carries a comment saying why it is safe. UI state is `@MainActor`.
   - Events apply in id order, a repeated id is ignored, and whole-object payloads replace the stored object.
   - Each error path in spec 6.7 is handled: offline, `401`, `409`, `410` on the stream, `426`.
   - The stream reconnects with backoff and `Last-Event-ID`; the 60-second snapshot poll starts after 60 seconds without the stream and stops when it returns.
5. **Pull request description** (Blocking for accuracy, Should fix for commits and template)
   - Everything described is in the diff, and everything significant in the diff is described.
   - Testing claims match commands that exist and results CI can reproduce.
6. **Tests** (Should fix)
   - New behaviour has tests named for the behaviour. Reducers and the event path have unit tests; Orbit and pillar states have snapshot tests from mock fixtures.
7. **Performance** (Should fix)
   - One SSE connection per app. No polling while the stream is up. Spec 6.9 budgets are measured, not assumed, when rendering code changes.
8. **Copy** (Should fix)
   - British English in UI copy, logs, comments and docs. No em dashes or en dashes. No emojis in UI copy.
9. **Simplicity** (Suggestion)
   - Is there a simpler way? Is a new dependency justified by an ADR?

## What not to comment on

- Anything a CI job already reports: swift-format, build, tests, the mock's lint, typecheck and tests, and the contract lint.
- Personal style preferences that no rule here, in `AGENTS.md` or in an ADR supports.

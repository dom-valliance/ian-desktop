# Mock server

Node 22, TypeScript, Fastify and Zod, managed with pnpm through corepack. Built in D2 to spec section 7.

- Serves `/desktop/v1` on port 4317, the default environment for the app (ADR 0003).
- Fixtures are invented. Use placeholders such as `[CLIENT]` and `[PERSON]`. No real names, mail, clients or meetings, ever.
- It holds a small in-memory Lance: it derives horizon, pressure, attention, the Orbit, the Pillars field, the lists and the views, so the client computes nothing (ADR 0001, 0009).
- Tests validate every response against `../contract/ian-desktop.v1.yaml`.

## Run

```
scripts/dev.sh                 # from any directory: installs, starts the mock, waits until it answers
pnpm --dir mock dev            # the mock alone, with reload, on 4317
pnpm --dir mock start          # the mock alone, without reload
```

Any `Authorization: Bearer dev-...` token is accepted; anything else answers `401`. Environment variables:

| Variable                     | Default             | Meaning                                               |
| ---------------------------- | ------------------- | ----------------------------------------------------- |
| `MOCK_PORT`, `MOCK_HOST`     | `4317`, `127.0.0.1` | Where it listens                                      |
| `MOCK_SCENARIO`              | `normal`            | The scenario at start                                 |
| `MOCK_START_AT`              | 09:30 UTC today     | The mock clock at start                               |
| `MOCK_HEARTBEAT_INTERVAL_MS` | `25000`             | The stream heartbeat                                  |
| `MOCK_ACTION_DELAY_MS`       | `250`               | The wait before the events an action causes           |
| `LOG_LEVEL`                  | `info`              | Fastify log level (requests only, never item content) |

## Checks

```
pnpm --dir mock lint        # ESLint (typescript-eslint strict) and Prettier
pnpm --dir mock typecheck
pnpm --dir mock test
pnpm --dir mock generate    # then: git diff --exit-code -- mock/src/generated
```

## Generated schemas

`src/generated/zod.gen.ts` holds Zod schemas generated from the contract by `@hey-api/openapi-ts` with its Zod plugin (`pnpm generate`). The output is committed and CI fails on drift. Request bodies, path and query parameters are parsed with them. Never edit it by hand.

`src/testing/contractValidator.ts` is separate: it loads the YAML and validates responses with Ajv 2020, with `discriminator` as an annotation. Tests use it for every response, so a generator defect cannot hide a response defect.

## Scenarios

`POST /__mock/scenario` with `{ "scenario": "<name>" }`. A switch replaces the world and sends the difference to open streams as events, so a connected client follows it. Event ids keep rising.

| Scenario           | What it holds                                                                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `quiet`            | 3 open items; the principal is eligible to go live                                                                                                                           |
| `normal`           | 18 open items (plus 2 awaiting confirmation), one urgent. The default                                                                                                        |
| `overloaded`       | 42 open items (plus 3 awaiting confirmation), above the median of 14, six units so the field folds the rest into Other                                                       |
| `incident`         | `normal` plus a P0 alert, the kill switch on (`settings.global.paused`), every agent paused                                                                                  |
| `offline`          | Closes every `/desktop/v1` connection without a response and drops open streams. `/__mock/*` still works, so switch back with it                                             |
| `stale-client`     | `minClientVersion` 99.0.0: a request that sends `Desktop-Client-Version` answers `426`, and a `client.deprecated` event is sent. A request without the header is not checked |
| `external-meeting` | `normal` with `today.context.inExternalMeeting` true                                                                                                                         |

Sidebar counts: Today is the open count; Proposals, Tasks and Alerts count their items; Commitments counts all three tabs; Agents counts the table rows.

## Time

The mock clock stands still until moved, starting at 09:30 UTC on the current date, so every derived value is repeatable. `POST /__mock/clock` takes `{ "set": "<UTC time with milliseconds>" }` or `{ "advanceSeconds": 900 }`. It expires proposals that have passed their expiry, re-rates horizon, pressure, attention and meta lines, and emits an `item.upserted` for each changed item (version raised), then `today.updated` and `views.updated`. Replay windows follow this clock.

Pressure, from 0 to 1 and rounded to two places:

- An alert carries its severity: P0 1, P1 0.9, P2 0.55, P3 0.25.
- An item with a deadline (a due time, or a proposal's expiry) is `0.9 / (1 + hoursLeft / 24)`.
- After the deadline it climbs from 0.9 to 1 over ten days.
- An item with no deadline is 0.1.
- A field cell is `1 - product(1 - pressure)` over its items.

## Events and the stream

`GET /desktop/v1/events` numbers events from 1001, replays 24 hours by the mock clock from `Last-Event-ID`, and answers `410` for an id older than the window, newer than the latest event, or not a number. `heartbeat` carries no id and is never stored.

`POST /__mock/emit` takes one of:

```
{ "recipe": "alert", "severity": "P1", "title": "optional" }     creates an alert and emits it
{ "recipe": "proposal", "expiresInMinutes": 10 }                 creates a proposal and emits it
{ "event": { "type": "client.deprecated", ... } }                sends a contract event as given, without changing state
```

## Actions

Every action answers `{ correlationId }`; the events it causes follow the response after `MOCK_ACTION_DELAY_MS` and at least one carries that id.

| Item       | Action                        | Answer | Events                                                                                       |
| ---------- | ----------------------------- | ------ | -------------------------------------------------------------------------------------------- |
| Proposal   | approve                       | `202`  | `item.upserted` (working), then `item.removed` with an outcome                               |
| Proposal   | reject                        | `200`  | `item.removed`; a `complete_task` proposal gives its task the Done action back               |
| Commitment | settle, dismiss               | `200`  | `item.removed` with an outcome                                                               |
| Commitment | snooze (`until`)              | `200`  | `item.upserted` with the new due date                                                        |
| Commitment | chase (`note`)                | `202`  | `item.upserted` (chase requested), then a draft proposal                                     |
| To confirm | confirm                       | `200`  | `item.upserted`; the commitment moves into its tab                                           |
| Task       | done                          | `202`  | `item.upserted` without Done, then a `complete_task` proposal; approving it removes the task |
| Alert      | acknowledge, snooze (`until`) | `200`  | `alert.cleared`                                                                              |

A stale `version`, or an action the item does not offer, answers `409` with the current item. `POST /handoff` marks the item working, then raises a proposal; both carry the correlation id. Agents pause and resume within scope (`403` when `pausable` is false) and emit `agent.updated`. `PATCH /settings` refuses `mode: live` with `422` unless `liveEligible`, and emits `settings.updated`.

## Sessions

`POST /desktop/v1/sessions` heartbeats are kept in memory. `GET /__mock/sessions` returns them with the mock time they arrived.

## CLI

`pnpm --dir mock mock <command>` calls the running mock (`MOCK_URL`, default `http://127.0.0.1:4317`):

```
pnpm --dir mock mock emit alert --severity P1
pnpm --dir mock mock emit proposal --expires-in 10
pnpm --dir mock mock emit event '{"type":"heartbeat","serverTime":"2026-10-16T09:00:00.000Z"}'
pnpm --dir mock mock scenario incident
pnpm --dir mock mock clock advance 15m
pnpm --dir mock mock clock set 2026-10-16T22:00:00.000Z
pnpm --dir mock mock sessions
pnpm --dir mock mock state
```

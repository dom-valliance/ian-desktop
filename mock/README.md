# Mock server

Node 22, TypeScript, Fastify and Zod, managed with pnpm through corepack. Built in D2 to spec section 7.

- Serves `/desktop/v1` on port 4317, the default environment for the app (ADR 0003).
- Fixtures are invented. Use placeholders such as `[CLIENT]` and `[PERSON]`. No real names, mail, clients or meetings, ever.
- Scenarios (`quiet`, `normal`, `overloaded`, `incident`, `offline`, `stale-client`, `external-meeting`) switch through `POST /__mock/scenario`.
- `POST /__mock/emit` and `POST /__mock/clock` drive events and time. `pnpm mock emit alert --severity P1` wraps the first.
- Tests validate every response against `../contract/ian-desktop.v1.yaml`.

Mirror Lance's toolchain where it applies: vitest, ESLint, Prettier, strict TypeScript with no `any`, Zod at every boundary.

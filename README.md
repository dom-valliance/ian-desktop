# Ian desktop

A native macOS client for Lance. At rest it is the Orbit avatar in a corner of the screen. Opened, it is the expanded client with seven views: Today, Proposals, Commitments, Tasks, Alerts, Agents and Settings. It is a thin client: Lance holds every rule, every computed value and every write.

The repository is `ian-desktop`. A local checkout may sit in a folder called `desktop-ian`; nothing depends on the folder name.

| Read | For |
|---|---|
| [docs/spec.md](docs/spec.md) | The specification. Read it before writing code |
| [AGENTS.md](AGENTS.md) | How to work here, for people and agents. `CLAUDE.md` imports it |
| [docs/plans/work-packages.md](docs/plans/work-packages.md) | D1 to D9 in order, with a kick-off prompt for each |
| [docs/adr/README.md](docs/adr/README.md) | Architecture decisions |
| [docs/design/README.md](docs/design/README.md) | The Orbit and Pillars encodings, taken from the design canvas |
| [docs/companion/lance-track.md](docs/companion/lance-track.md) | What Lance must build (DL1 to DL6) before the `lance-dev` profile works |

## Running it

Version 0 runs from Xcode, unsigned, against the mock server in `mock/`. `scripts/dev.sh` starts the mock and opens the app. Both arrive with work packages D1 to D3; until then this repository holds the plan, the ADRs and the design references.

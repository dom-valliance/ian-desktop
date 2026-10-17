---
description: Start or resume a work package (D1 to D9) from docs/plans/work-packages.md
argument-hint: 'D1 to D9'
---

Work package $ARGUMENTS.

1. Run `/recall`. Read the package's entry in [work-packages.md](../../docs/plans/work-packages.md), every spec section and ADR it names, and [AGENTS.md](../../AGENTS.md) including the errata.
2. Check that each dependency is recorded as done in [the phase log](../../docs/adr/0000-phase-log.md). If one is not, stop and say which.
3. Check the working tree. If it holds changes you did not make, ask Dom how to handle them (commit, stash, or a worktree) before switching branch. Otherwise create the package's branch from `main`, named in its entry.
4. Write a short plan: files to add, tests to write, ADRs needed, and anything in the entry you cannot do from this machine. Then build.
5. The package is done when every check in its "Done when" list passes by exit code, every command in `.github/workflows/` passes locally, and the evidence (commands, results, commit range) is appended to the phase log.
6. Hand over: branch and commit range, what changed on screen and in which mock scenario, then a numbered list of Dom's actions with exact commands, then what you will do next and what you are waiting on.

---
description: Review the current branch, or a named branch, against REVIEW.md before Dom opens a pull request
argument-hint: '[branch]'
---

Review $ARGUMENTS (default: the current branch against `main`, or `origin/main` once a remote exists) the way the automated reviewer does, so the author can fix findings before pushing.

1. Read [REVIEW.md](../../REVIEW.md) and the "Review guidelines" section of [AGENTS.md](../../AGENTS.md#review-guidelines). Every finding points to a rule in one of them, a non-negotiable or an ADR.
2. Read the full diff (`git diff main...HEAD`) and the pull request description if one exists. If there is none yet, say which template sections the change will need.
3. Work through REVIEW.md's "What to check" list in order. Skip anything a CI job already reports.
4. Report each finding with its severity and priority (Blocking P1, Should fix P2, Suggestion P3; P0 only for a secret or real data), the file and line, what is wrong, and a concrete fix.
5. Do not change files. End with the number of findings at each severity.

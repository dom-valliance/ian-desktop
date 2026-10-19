# Project learnings

Append-only. Lessons from corrections during the Ian desktop build. The first entries are carried from Lance's `.claude/notes/` because they are about how Dom works, not about Lance's code; each names its Lance date.

### [2026-09-19, carried from Lance] GitHub is Dom's, git is Claude's

**Context**: Phase 0 tooling in Lance; Claude started `brew install gh` to open pull requests from the terminal.
**Correction**: "No. just use git. I'll do the github stuff."
**Rule**: Plain git only for branches and commits. Never install or use the `gh` CLI, never open pull requests. Hand over branch names and commit ranges.
**Applies to**: global

### [2026-09-21, carried from Lance] Verification output is read by exit code, never by grep

**Context**: A lint run piped through `grep` printed "checks done" while the failure scrolled away, and CI failed.
**Correction**: Dom pasted the CI log.
**Rule**: Judge a verification command by its exit code, with its last lines shown unfiltered. Never print a success message after a pipeline whose exit status was not checked.
**Applies to**: global

### [2026-09-22, carried from Lance] The verification set is every CI step

**Context**: A branch passed lint, typecheck, test and build locally, then failed CI on formatting.
**Correction**: Dom pasted the CI log.
**Rule**: Before calling a branch done, run every command the workflows run, read from `.github/workflows/` rather than from memory. A subagent's "I formatted my files" is not evidence; the root command is.
**Applies to**: global

### [2026-09-23, carried from Lance] End a hand-over with numbered actions for Dom

**Context**: A hand-over described branch state and a suggestion instead of saying what Dom should do.
**Correction**: Dom said it was not clear what he was being asked to do.
**Rule**: Close any hand-over with a numbered list of Dom's actions, each with the exact command, then what Claude will do and what it waits on. Branch state goes above that list.
**Applies to**: global

### [2026-09-25, carried from Lance] Say where and how to run a step, not just its name

**Context**: A checklist step said "redeploy from the branch".
**Correction**: "It's not clear what redeploy means here."
**Rule**: A hand-over step names the directory, the branch and the exact commands, and what it does not involve.
**Applies to**: global

### [2026-09-23, carried from Lance] Describe a UI change by where it lives and what the eye will see

**Context**: Dom could not find a component or the paging Claude had described.
**Correction**: Dom asked whether the work had been lost.
**Rule**: When handing over a UI change, link the files and say what appears on screen: position, label, what it does when clicked, and which mock scenarios show nothing new.
**Applies to**: global

### [2026-09-22, carried from Lance] Name the principal, not Dom, in code

**Context**: A filter was named for Dom personally.
**Correction**: "It needs to be isPrincipalsLiveTask as this will probably become a multi user system very soon."
**Rule**: New identifiers name the role, `principal`, never the person.
**Applies to**: global

### [2026-09-24, carried from Lance] A failing target is fixed at the cause, not by loosening the target

**Context**: A load-test target failed and the first recommendation was to amend the target.
**Correction**: "Isn't that just making the NFRs more tolerant?"
**Rule**: When an acceptance target fails (spec 6.9 budgets included), recommend the change that fixes the cause. Propose changing a target only when it measures the wrong thing, and say plainly what the user would then experience.
**Applies to**: global

### [2026-10-18] Diagnose from the device's evidence before ranking a configuration fix

**Context**: Xcode would not install on Dom's Intune-managed Mac. Claude's checklist ranked switching the VPP assignment from user to device licensing as the most likely cause, without evidence for it.
**Correction**: "Already device licensing." The Mac's own `mdmclient` log showed the real state: Intune had never sent `InstallApplication` until the assignment was re-saved and synced, and then the download started.
**Rule**: Before recommending a configuration change, read the evidence the machine already holds (here `/usr/bin/log show` for `mdmclient` and `appstored`; note `log` is a zsh builtin) or ask for the current setting. Rank causes by what the evidence shows, not by how common they are.
**Applies to**: global

### [2026-10-18] Give Dom commands and screen positions, not Xcode vocabulary

**Context**: Asking Dom to try the D1 app, Claude wrote "choose the `Ian` scheme and My Mac, then press ⌘R" and "you should see Ian in the menu bar".
**Correction**: "I don't know what a scheme is and I can't see any menu bar showing." The app was running; its menu bar item was hidden from view, likely by a full menu bar on a notched MacBook or by being on another display.
**Rule**: For a step Dom runs, give a terminal command where one exists (build, then `open` the app) instead of IDE terms, and say exactly where on screen the result appears and what can hide it. Second occurrence of the 2026-09-25 lesson "Say where and how to run a step"; a third promotes it to the AGENTS.md Gotchas.
**Applies to**: global

### [2026-10-19] Clean up every process Claude starts, and check it is gone

**Context**: To mimic a slow CI machine, Claude started 14 `yes` load processes with `(yes > /dev/null) &` and later ran `kill $pids`.
**Correction**: "Are you still stress testing my CPU? I can see a bunch of YES processes still running." `$!` had held the subshells' ids, so the `yes` processes kept every core busy overnight.
**Rule**: Start a background process without a subshell wrapper so `$!` is its own id, or start it as a tracked background task and stop that task. After cleanup, confirm with `pgrep` that nothing is left, and say so. In zsh, pass a list of ids through `xargs kill`, since `$pids` is not word-split.
**Applies to**: global

### [2026-10-19] A GUI process Claude starts runs on Dom's screen

**Context**: A P1 agent measured CPU with a small GUI harness app. A recursion bug crashed it three times in two minutes, and it was relaunched each time.
**Correction**: Dom sent a screenshot of "Harness quit unexpectedly" and asked "Is this you?". Each crash put a macOS dialog in front of his work.
**Rule**: Any app Claude or its agents launch shows windows and crash dialogs on Dom's screen. Say so before running one. After every run, check its exit status and the newest report in `~/Library/Logs/DiagnosticReports`, and never relaunch after a crash without a fix and a test that reproduces it. This is the second lesson about Claude's processes affecting Dom's machine (see the `yes` entry above); a third promotes it to the AGENTS.md Gotchas.
**Applies to**: global

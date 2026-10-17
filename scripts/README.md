# Scripts

`dev.sh` starts the mock on port 4317, waits for it to answer, then builds and opens the app against it. Acceptance (spec section 11) requires a fresh clone to show the `normal` scenario within ten seconds of running it. Built across D2 and D3.

Scripts must work from a fresh clone with no Apple account, and must fail with a clear message when Xcode, Node 22 or pnpm is missing.

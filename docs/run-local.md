# Run Ian locally

From a fresh clone to the `normal` scenario on screen, on a new Mac. Everything here runs unsigned, with no Apple account and no Apple Developer membership. Ian runs against a mock server on your own machine, which holds invented data only.

All commands run in Terminal. Where a step opens something on screen, the step says where.

## What you need

| Need | Version | Why |
|---|---|---|
| macOS | 26.6 or later, Apple silicon | Xcode 27's minimum (ADR 0010). The app itself targets macOS 14 |
| Xcode | 27.1, build 27A9275 | The compiler, the SDK and `swift format` that CI uses (ADR 0010) |
| Node | 22, through nvm | `.nvmrc` pins it; the mock needs it |
| pnpm | Through corepack | Corepack ships with Node 22 |
| git | Any recent | The Command Line Tools provide it |

### Xcode 27.1

Install Xcode 27.1 from the Mac App Store, or from your company's software catalogue. Open it once so that it accepts its licence and installs its components. Then point the command line at it:

```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -version
```

The last command must print `Xcode 27.1` and `Build version 27A9275`. If it prints another version, the build can fail in ways that look unrelated, such as swift-format refusing the repository's configuration, or Swift packages that will not resolve. Fix the selection before going on. If Xcode sits elsewhere, for example `/Applications/Xcode_27.1.app`, use that path after `-s`.

You do not need to open Xcode again. Nothing in this guide uses its window.

### Node 22 and pnpm

If nvm is not installed, follow the instructions at https://github.com/nvm-sh/nvm, then open a new Terminal window. Then:

```
nvm install 22
corepack enable
```

`nvm install` in the repository folder reads `.nvmrc`, so you can also run it there without the number. `scripts/dev.sh` finds nvm by itself and uses the repository's Node, so a different default Node in your shell does not matter for it.

## Clone and run

```
git clone git@github.com:dom-valliance/ian-desktop.git
cd ian-desktop
scripts/dev.sh
```

Use the HTTPS address from the repository's GitHub page if you do not have an SSH key set up. A local folder called `desktop-ian` is the same repository; nothing depends on the folder name.

`scripts/dev.sh` does four things, in order:

1. Installs the mock's dependencies, if they are not there (`pnpm install --frozen-lockfile` in `mock/`).
2. Starts the mock on port 4317 and waits until it reports `Mock listening`.
3. Builds the app in Debug, unsigned, into `build/DerivedData`. The output of the build is hidden unless it fails.
4. Opens the app.

The first build compiles the Swift packages from nothing. On 20 October 2026, a fresh clone of `main` on an M4 Pro, with SwiftPM and Xcode's user-level caches already warm, took:

| Step | Time |
|---|---|
| `swift build --package-path Packages/IanKit --force-resolved-versions` | 33 seconds |
| `swift test --package-path Packages/IanKit --force-resolved-versions` | 29 seconds |
| `xcodebuild` Debug build of the app, unsigned | 45 seconds |
| `pnpm --dir mock install --frozen-lockfile` and `pnpm --dir mock test` | 9 seconds |

A Mac that has never built a Swift package also downloads the dependencies and builds Xcode's module caches, so allow several minutes for the first run there. Later runs build only what changed.

The script keeps running in the Terminal window after the app opens. That is the mock. Leave the window open while you use the app.

### What appears, and where

Ian is an accessory app. It has no Dock icon and no window until you open one.

| What | Where | What you see |
|---|---|---|
| The Orbit | The bottom right corner of the main display, 16 points in from each edge | A small round avatar, 96 points across: a grey core, a thin ring that shows how loaded the day is, and up to five coloured dots (satellites) for what needs you now. In `normal` there is one dot for each of the first five items and a "+n" chip for the rest |
| The menu bar entry | The right side of the menu bar, on every display | The word "Ian", followed by a number when something needs you now, such as "Ian 5". Click it for Open, Pause me, Settings and Quit Ian |

On a MacBook with a camera notch and many menu bar items, the entry can sit behind the notch, where nothing can click it. If you cannot see it, use the Orbit instead: click the Orbit to open the panel and right-click it for the same menu. You can also hold Command and drag menu bar items to the left to make room.

Click the Orbit to open the expanded client: a panel of 1,040 by 720 points above the Orbit's corner, with the sidebar on the left (Today, Proposals, Commitments, Tasks, Alerts, Agents, Settings) and, on Today, the Pillars field with the lists below it. Click the Orbit again to close it.

The panel's header names the environment only when it is not the mock, so against the mock the header shows no environment.

### Allow notifications

The first time the app asks to send notifications, macOS shows a prompt near the top right of the screen. Choose Allow. If you chose Don't Allow, or the prompt never appeared, open System Settings, then Notifications, then Ian, and switch Allow Notifications on. Without this, urgent items still whisper beside the Orbit, but no banner appears.

### Drive it

The mock starts in `normal`, with 18 open items and one urgent proposal. Switch scenarios and make things happen from a second Terminal window, in the repository folder:

```
pnpm --dir mock mock scenario quiet
pnpm --dir mock mock scenario normal
pnpm --dir mock mock scenario overloaded
pnpm --dir mock mock scenario incident
pnpm --dir mock mock scenario offline
pnpm --dir mock mock scenario stale-client
pnpm --dir mock mock scenario external-meeting
```

Open streams follow the change, so the app updates without a restart.

| Scenario | What it holds |
|---|---|
| `quiet` | Three open items. The principal is eligible to go live |
| `normal` | 18 open items, one urgent. The default |
| `overloaded` | 42 open items, so the field folds the smaller units into Other |
| `incident` | `normal` plus a P0 alert, the kill switch on, every agent paused |
| `offline` | The mock closes every connection. The app shows its offline banner and keeps its data. Switch back with another `scenario` command |
| `stale-client` | The mock demands a newer client version. The app shows its upgrade state |
| `external-meeting` | `normal` while the principal is in an external meeting, so item text is hidden |

More commands, each one a request to the running mock:

```
pnpm --dir mock mock emit alert --severity P1
pnpm --dir mock mock emit proposal --expires-in 10
pnpm --dir mock mock clock advance 15m
pnpm --dir mock mock capabilities handoff off
pnpm --dir mock mock sessions
pnpm --dir mock mock state
```

`mock/README.md` lists every command, the actions the mock accepts and how it derives pressure and attention.

### Stop

1. Quit the app: click "Ian" in the menu bar, or right-click the Orbit, and choose Quit Ian.
2. Press Control-C in the Terminal window that runs `scripts/dev.sh`. That stops the mock.
3. Check that nothing is left:

```
pgrep -fl "tsx src/main.ts"
pgrep -x Ian
```

Both commands should print nothing.

### Run the mock alone

To start only the mock, for example to run the integration tests:

```
scripts/dev.sh --mock-only
```

`MOCK_PORT` and `MOCK_HOST` change where it listens. The app's mock profile expects port 4317, so the app is opened only when the port is 4317.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `dev.sh: something already answers on 127.0.0.1:4317` | An earlier mock is still running. Find it with `lsof -nP -iTCP:4317 -sTCP:LISTEN`, then stop it with `kill <pid>` using the pid that command prints. Stop it before setting `MOCK_PORT` to another port, because the app expects 4317 |
| `dev.sh: Xcode 27 is needed to build the app` | Xcode is missing or the command line points at another one. Run `xcodebuild -version` and follow "Xcode 27.1" above |
| The build fails with an error about a package, a manifest or a Swift version | Almost always another Xcode selected. Run `xcodebuild -version`. It must say Xcode 27.1 |
| `dev.sh: Node 22 is required` | Run `nvm install` then `nvm use` in the repository folder, and run the script again |
| `dev.sh: pnpm is missing` | Run `corepack enable` once, then run the script again |
| The app opens but shows an old layout, or a build error that a recent pull should have fixed | A stale build. Delete the build folder and run again: `rm -rf build/DerivedData`. The next build takes the full several minutes |
| No Orbit anywhere | Check that the app runs with `pgrep -x Ian`. If it runs, the Orbit may be on another display or hidden behind a full-screen app. The Orbit sits on the main display, the one that holds the menu bar when "Displays have separate Spaces" is on |
| The Orbit is there but shows no dots | The mock may be in a scenario with no items, or stopped. Check the Terminal window that runs `scripts/dev.sh`, then run `pnpm --dir mock mock state` |
| The panel header says the data is old | The stream to the mock has dropped. Look in the `scripts/dev.sh` window for a crash, then run the script again |
| macOS says Ian cannot be opened because the developer cannot be verified | You opened a copy of the app that was downloaded or moved. Open it with `scripts/dev.sh`, which builds it on your machine, so it carries no quarantine flag |

## Switch to Lance dev

The `lance-dev` profile reads the real Lance dev environment for the signed-in principal. It cannot work until Lance has done its part. Until then the app says so and nothing breaks, and the mock stays the default.

### What it needs

Lance package DL1 (see [docs/companion/lance-track.md](companion/lance-track.md)) must have done these, in Lance, on a Lance branch:

- Exposed a delegated api scope on the `Lance (Valliance)` registration. Today the registration exposes none (erratum E2).
- Registered the public client `Ian Desktop (dev)`: single tenant, a loopback redirect, delegated permission on the new scope with admin consent.
- Given the principal the `Lance.User` role on the Lance enterprise application.
- Turned on `FF_DESKTOP_API` for the dev api.

DL2 to DL4 supply the data (Today, the event stream and the actions) and must be merged for anything beyond sign-in to show.

Then the build needs three values. They are build settings in `App/project.yml`, carried into the app through `App/Info.plist`:

| Setting | Holds |
|---|---|
| `IAN_LANCE_TENANT_ID` | The tenant id. Already set |
| `IAN_LANCE_CLIENT_ID` | The id of `Ian Desktop (dev)`. Empty until DL1 registers it |
| `IAN_LANCE_SCOPE` | The api scope string DL1 records in Lance's Entra runbook. Empty until DL1 |

Edit the empty values in `App/project.yml`, regenerate the project, then run a build:

```
scripts/generate-project.sh
```

The regenerated `App/Ian.xcodeproj` is committed, so commit both files together. `scripts/check-generated.sh` fails if they drift.

The base URL is built into the profile, from erratum E3:

```
https://ca-lance-api-dev.graygrass-c682ce2c.uksouth.azurecontainerapps.io/desktop/v1
```

Check the host is current with:

```
az containerapp show -g rg-lance-dev -n ca-lance-api-dev --query properties.configuration.ingress.fqdn -o tsv
```

### How to switch

Either way, no rebuild is needed beyond the settings above.

1. **From Settings.** Click the Orbit to open the panel, choose Settings in the sidebar, and use the Environment picker to choose "Lance dev". A confirmation asks "Switch environment?". Choose "Sign out and switch to Lance dev". Ian clears what it holds and starts again.
2. **From the launch argument.** Quit the app, then open it with the argument. This does not save the choice:

```
open build/DerivedData/Build/Products/Debug/Ian.app --args -IanEnvironment lance-dev
```

The mock does not need to run for `lance-dev`. To go back, choose "Mock" in the same picker, or open the app with `--args -IanEnvironment mock`.

### The browser sign-in

With `lance-dev` active the panel shows "Sign in to see your day." and a Sign in button. Click it. Ian opens your default browser at the Microsoft sign-in page and listens on `http://localhost` on a random port for the redirect. Sign in with your Valliance account. When the browser says you can close the tab, return to Ian: the panel loads your own items, and the header shows "Lance dev". Ian keeps its tokens in the login Keychain, so a relaunch signs in silently.

### What it shows until DL1 lands

- With `IAN_LANCE_CLIENT_ID` or `IAN_LANCE_SCOPE` empty, the panel shows a sign-in banner that names the empty settings and says that Lance package DL1 adds them. No browser opens.
- If the settings are filled in but Entra does not offer the scope, sign-in fails with a message that names the scope and says DL1 grants it.
- If sign-in works but DL2 to DL4 are not merged, the api has nothing to serve and the panel shows its offline or error state instead of data.

In every case, switch back to the mock with the picker or the launch argument.

### The data rule

`lance-dev` reads real data: mail, tasks, commitments and meeting names. Therefore:

- Never record a snapshot, take a screenshot, save a trace or run `scripts/measure-cpu.sh` against `lance-dev`, and never paste its output into a pull request, an issue or a document.
- Keep `lance-dev` out of every test.
- The diagnostics report in Settings copies ids, versions and timings only, and is safe to share.
- Keep the app on the mock when you demonstrate it to anyone. [docs/demo.md](demo.md) uses the mock for everything except its last section.

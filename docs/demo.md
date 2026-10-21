# Demo script

About ten minutes, against the mock. The data is invented, so any screen is safe to show. For setup, see [run-local.md](run-local.md).

Each step says what to do, where, and what the audience sees. Commands run in a second Terminal window, in the repository folder, called "the control window" below. The first Terminal window runs `scripts/dev.sh` and stays untouched.

## Before the audience arrives

1. In Terminal window one: `scripts/dev.sh`. Wait for the app to open.
2. Open a second Terminal window and keep it small, beside the screen the audience sees. Run `pnpm --dir mock mock scenario normal`.
3. Allow notifications for Ian if macOS asks (System Settings, Notifications, Ian).
4. Check that "Pause me" is not ticked: click "Ian" in the menu bar, or right-click the Orbit. If it is ticked, click it once.
5. Close the panel if it is open, so the audience sees only the Orbit.

## 1. The Orbit at rest (1 minute)

Where: the bottom right corner of the main display.

- **Say.** Ian is a client for Lance, the personal operating agent. At rest it is only this avatar.
- **Point at.** The grey core, which breathes blue only while Ian is working on something. The thin ring, which fills as the day's load approaches its usual size. In `normal` the ring is full and a short peach arc outside it shows load above the median. The coloured dots on the ring, called satellites, which are what needs you now: pink for proposals, peach and blue for commitments you owe and are owed, teal for tasks, red with a pulsing rim for alerts. A "+n" chip counts the items that do not fit.
- **Hover.** Move the pointer over the Orbit. A label beside it shows the top item's title, for example "Send the revised scope to [CLIENT A]".
- **Menu bar.** Show "Ian" followed by a number at the right of the menu bar, or the Orbit's right-click menu if the entry hides behind the camera notch. Say that both give the same menu: Open, Pause me, Settings and Quit Ian.

## 2. Open on Today (2 minutes)

- **Do.** Click the Orbit.
- **Audience sees.** A panel opens above the Orbit with the sidebar (Today, Proposals, Commitments, Tasks, Alerts, Agents, Settings, each with a count) and the Pillars field on Today.
- **Explain the field.** Columns are units of work. Rows are horizons, with Now at the front. A pillar's height is pressure, its colour is the kind of item, and rising light means Ian is working on it. Say that the server decided all of this; the app only draws it.
- **Do.** Drag across the field.
- **Audience sees.** The field turns with the pointer. Double-click the field to turn it back.
- **Do.** Click a tall pillar.
- **Audience sees.** Its row is selected in the Now list below, with the item's buttons. Click a row and its pillar is selected: the list is the accessible path, and everything in the field is reachable from it with VoiceOver and the keyboard.
- **Point at.** This week as grouped lines, and Later as counts that link to the relevant view.
- **Do.** Drag the divider between the field and the lists to show the panes resize. Mention that both sizes are remembered.

## 3. Settle a commitment (1 minute)

- **Do.** Click Commitments in the sidebar, then the tab "Owed by me".
- **Audience sees.** Cards with the counterparty, due date, evidence quote and chase state, for example "Send [PERSON A] the signed order form".
- **Do.** On a card, click Settle.
- **Audience sees.** The card shows a pending line at once and its buttons go quiet. About a quarter of a second later the server answers, the card dims with a one-line outcome in Ian's voice, and it leaves the list. Say: the app never completes anything itself. It marks the item pending and waits for the server's event.
- **Do.** Click Today.
- **Audience sees.** The pillar for that commitment sinks, and the counts in the sidebar drop by one.

## 4. Proposals, an urgent one, and a whisper (2 minutes)

- **Do.** Click Proposals.
- **Audience sees.** Pending proposals grouped by action class, soonest expiry first. The first, "Send the revised scope to [CLIENT A]", has an URGENT badge, because it expires within 15 minutes. Each card shows the target system, the decision tier, the confidence with its source label and the expiry.
- **Do.** Close the panel by clicking the Orbit. In the control window run:

```
pnpm --dir mock mock emit proposal --expires-in 10
```

- **Audience sees.** Within a second, a one-line whisper beside the Orbit, for about eight seconds, and a banner in the top right with Approve and Open. The Orbit grows a new pink satellite.
- **Do.** Click Approve on the banner, or click the banner to open the panel on Proposals.
- **Audience sees.** The card shows pending, then leaves with an outcome line.
- **Say.** Only the buttons the server sent appear, in the order it sent them. Reject is not on the banner, because it asks for confirmation.

## 5. The incident (2 minutes)

- **Do.** Close the panel if it is open. In the control window run:

```
pnpm --dir mock mock scenario incident
```

- **Audience sees.** The Orbit changes: a red alert satellite with a pulsing rim. A banner with a sound announces a P0 alert, the highest rung.
- **Do.** Move the mouse.
- **Audience sees.** The panel opens on its own, on Alerts, on the next pointer movement. It happens once. It does not open again if you close it.
- **Point at.** On Alerts, the P0 group is pinned at the top while the groups below it scroll.
- **Do.** Click Agents in the sidebar.
- **Audience sees.** A banner says the kill switch is on and no agent acts until it is released. Every agent in the table shows as paused. The banner is read-only, since only the server can release it.

## 6. Suppression (1 minute)

- **Do.** Click "Ian" in the menu bar, or right-click the Orbit, and choose Pause me. The entry gains a tick.
- **Audience sees.** The Orbit shows state with no text: the satellites stay, hovering shows no label, and the whisper stays quiet.
- **Do.** Close the panel, then in the control window run:

```
pnpm --dir mock mock emit alert --severity P1
pnpm --dir mock mock emit alert --severity P0
```

- **Audience sees.** Nothing for the P1. For the P0, a banner that reads "Ian" and "Something needs you now.", with only an Open button, and the panel does not open by itself.
- **Say.** Suppression hides all item text on the Orbit and in notifications. A P0 still notifies, but without a word of content. The same applies with the camera live, in an external meeting (`pnpm --dir mock mock scenario external-meeting`) and during quiet hours.
- **Do.** Choose Pause me again to untick it.

## 7. Settings, and going live (1 minute)

- **Do.** In the control window run `pnpm --dir mock mock scenario quiet`. Open the panel and click Settings.
- **Audience sees.** Two sections: client settings that stay on this Mac (corner, motion, notification level for each rung, suppression toggles, open at login, environment, sign out, diagnostics) and principal settings that live on the server (quiet hours, push budget, mode, own pause).
- **Do.** In Mode, click "Go live".
- **Audience sees.** A confirmation, "Go live?". The button is enabled because `quiet` is the one scenario where the server reports that the principal is eligible. Switch the scenario back to `normal` and the button is disabled. Say: eligibility is the server's decision, the client only reflects it.
- **Do.** Click Cancel, unless you want to change the mock's state.
- **Point at.** The Environment picker, which names Mock and Lance dev. Do not switch it here.

## 8. Hand to Ian (1 minute)

- **Do.** In the control window run `pnpm --dir mock mock scenario normal`. In the panel, click Tasks, then on a task card click "Hand to Ian".
- **Audience sees.** A field "Instruction for Ian (optional)" with Send and Cancel.
- **Do.** Type a short instruction, for example "Draft the agenda", and click Send.
- **Audience sees.** The card shows pending, and its pillar on Today shows rising light while Ian works. A moment later a new proposal appears on Proposals, titled "Ian's next step for: ..." with the instruction as its summary. Approve it to finish.
- **Say.** The button appears only because the server says it offers hand-off. To show it vanish, run `pnpm --dir mock mock capabilities handoff off` and look at any card, then `pnpm --dir mock mock capabilities handoff on`.

## Afterwards

Quit Ian from the menu, press Control-C in the first Terminal window, then run:

```
pgrep -fl "tsx src/main.ts"
pgrep -x Ian
```

Both must print nothing.

## Against Lance dev

This part waits on Lance packages DL1 to DL4 ([docs/companion/lance-track.md](companion/lance-track.md)). Until they are merged, `lance-dev` cannot sign in, and nothing here can be shown. Do not show it on a shared screen: it reads real data (the data rule in [run-local.md](run-local.md)).

Prepare once DL1 to DL4 are merged: fill `IAN_LANCE_CLIENT_ID` and `IAN_LANCE_SCOPE` in `App/project.yml`, run `scripts/generate-project.sh`, and build with `scripts/dev.sh`. Then, per spec section 11:

1. **Switch.** In Settings, choose "Lance dev" in the Environment picker and confirm. The header shows "Lance dev".
2. **Sign in through the browser.** Click Sign in. The default browser opens the Microsoft page. After signing in, the panel loads.
3. **See the principal's own items.** Today, Proposals, Commitments, Tasks and Alerts hold the signed-in principal's own items, with the same shapes as the mock.
4. **Settle a commitment.** Settle one of your own commitments. The card shows pending, then the server's event removes it, as in the mock.
5. **Check the ledger.** In Lance, the ledger shows the event with `surface: 'desktop'` in its payload. This is the evidence that the action came from this client.
6. **Arbitration (DL5).** With DL5 merged, an alert raised while the app is active reaches the desktop and not Slack; after ten idle minutes the next one reaches Slack.

Record the outcome in the phase log, with no item text, title or name in it.

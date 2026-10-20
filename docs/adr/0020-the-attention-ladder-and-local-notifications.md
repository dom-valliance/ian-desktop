# 0020. The attention ladder and local notifications

Date: 2026-10-20
Status: Accepted

## Context

D8 builds the behaviour of spec 6.6 and the local notifications of 6.5. The spec table names what each rung does, and leaves open:

- What counts as a moment to notify. Items arrive in a snapshot and are replaced whole by events, so "the item is urgent" holds on every event that carries it.
- What a notification says while suppressed, and which buttons it carries. Spec 6.6 gives Urgent "a banner with the item's actions", but some actions need a confirmation, a time or a note.
- How Stop's "next pointer movement" and the eight-second whisper reach the screen without a new window model.
- Which framework imports the work needs. `UserNotifications` is not in the import graph of `Packages/IanKit/README.md`.

The rung is the server's (`Item.attention`, ADR 0009, Q17). The levels are ADR 0019's: Ambient and Needs you default to Off, Urgent to Banner, Stop is fixed.

## Decision

- **One pure function maps a rung to a behaviour.** `AttentionLadder.behaviour(of:level:suppression:)` in `Attention` returns an Orbit cue, a notification (none, banner or always) and whether item text may be shown. Ambient is state only. Needs you grows and holds colour, which the Orbit already draws from the server's Orbit block. Urgent whispers whatever its level. Ambient, Needs you and Urgent notify with a banner only at the Banner level. Stop opens the panel on the next pointer movement and always notifies. While suppressed: no item text anywhere, only Stop notifies, nothing whispers, Stop does not open the panel, and the other notifications are dropped, never queued or replayed. The client counts no push budget; Lance applies it through the rung.
- **A notification is an escalation, decided by `EscalationPlanner`.** An item escalates when it first appears at a rung, or when its rung rises (ambient, needs you, urgent, stop). The ladder then says whether that escalation notifies. A fall is recorded without a sound and a later rise escalates again. A repeat with no change is silent. The first state after a launch or a reset (sign-out, profile switch) is a baseline in which only Stop items escalate, so a relaunch never floods. A reset starts a new baseline. An item that leaves the store has its delivered notification withdrawn.
- **Content.** Not suppressed: the title is the item's `title` and the body its `meta`. Suppressed: the title is "Ian" and the body "Something needs you now.", with no item text. The notification id is the item id, so a newer one replaces it, and `userInfo` holds the item id only. Stop plays the default sound; the other rungs are silent. Time-sensitive and critical delivery need entitlements and stay in the fast follow (spec 12).
- **Buttons.** A category per notification, named for the item's id and version, built from the item's `actions` in the order sent, using only actions with no `confirm` and no `input`, with their ids and labels as sent, then "Open". The others are reached through Open, where the expanded client asks for what they need. While suppressed there is only Open, under one shared category. The set registered with the system is exactly the categories of the notifications still held.
- **Responses.** An action button runs `IanStore.run(actionID:on:)` only when the store still holds the version the banner was delivered for, the action is still one a banner may run (no `confirm`, no `input`) and actions are enabled; otherwise it opens the item's view, so a banner never acts on state the principal did not see. A run marks the item pending and only the server's event moves it (AGENTS.md rule 2). The default tap and Open show the expanded panel on the view that holds the item's kind, or Today if the item has gone. Banners show even while Ian is frontmost.
- **The whisper** is the hover label's panel with the item's title for eight seconds, replaced and restarted by a newer urgent item, hidden at once when suppression starts. It has no motion, so Reduce Motion changes nothing about it.
- **A reset or sign-out** hides the whisper and disarms Stop, and removing the item that armed Stop disarms it.
- **Order within a batch.** Notifications go out from the least to the most urgent, so a Stop banner lands last and on top. The whisper and Stop arm take the most urgent escalation in the batch, the lowest id breaking a tie.
- **Stop arming** is a one-shot on the pointer monitors `SurfaceController` already installs. The first movement after arming opens the panel and disarms. It is not armed while suppressed or while the panel is open, and suppression starting disarms it.
- **Authorisation** for alerts and sound is requested once at start. The client always tries to deliver and the system drops what it may not show, so a permission granted later takes effect without a relaunch.
- **Where it lives.** The pure parts, the `NotificationDelivering` protocol and the real `UNUserNotificationCenter` adapter (`UserNotificationCentre`, with its delegate) are in `Attention`. The coordinator that watches the store is in `Surface`, which already holds suppression, the hover panel and the pointer monitors. `Features` stays out of `Surface`: `SurfaceController.onShowItem` and `ClientModel.show(_:)` meet in the app. Only the app target creates the real adapter, because `UNUserNotificationCenter.current()` raises in a process with no bundle; every test injects a fake.
- **Imports.** `Attention` may import `UserNotifications`. `Surface` and `Features` imports are unchanged. `Attention` reads `StoreState.Item` through `Store` and does not import `Contract`, as `Surface` already does.

## Consequences

- No new key reaches disk. The levels and toggles are ADR 0019's, the whisper and arming live in memory, and no notification is logged by title.
- A notification action that needs a confirmation, a time or a note takes one more step through Open. Quick actions never bypass a confirmation the server asked for.
- A principal who set Needs you to Banner sees a banner when an item first reaches that rung, not on each update.
- A suppressed Stop notification still sounds. That is P0 (AGENTS.md rule 6).
- Screen sharing has no signal, so a banner can reach a shared screen. Notification text on the shared screen is the same gap as spec 13 records for the Orbit.
- The system keeps delivered notifications, so item text could outlive its item. Withdrawal limits it: everything Ian delivered is removed at start, a notification is withdrawn when its item leaves the store or the store resets, and those that show item text are withdrawn when suppression starts. A Stop is the exception: it is replaced under the same id by the suppressed content, silently, so a P0 stays in Notification Centre (AGENTS.md rule 6); the system may show the replacement as a banner. The start-time withdrawal does remove an earlier launch's Stop until the first snapshot re-delivers it.
- The behaviour of real banners, buttons, the whisper and Stop's pointer opening is checked by hand, as the tests use a fake notification centre and no windows.

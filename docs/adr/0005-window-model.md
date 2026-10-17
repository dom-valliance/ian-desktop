# 0005. Window model

Date: 2026-10-17
Status: Accepted

## Context

The Orbit must stay visible across Spaces and over full-screen apps without stealing focus or clicks, and the expanded client must accept typing (spec 6.1, 6.2). There is no global shortcut in version 0, so Ian must stay reachable when the Orbit is hidden.

## Decision

The Orbit is a borderless, non-activating `NSPanel` at `.floating` level. It joins all Spaces and appears over full-screen apps as an auxiliary. It is click-through outside its hit area. The expanded client is a separate `NSPanel` that can become key, so text fields work. It is anchored above the Orbit's corner and closes on Escape. A `MenuBarExtra` mirrors the count and offers Open, Pause me, Settings and Quit.

## Consequences

- SwiftUI content sits in `NSHostingView`s inside AppKit panels; the window model lives in `Surface`.
- A borderless panel cannot become key by default, which is right for the Orbit; the expanded client's panel subclass overrides `canBecomeKey`.
- Click-through outside the hit area needs care: the simplest route is a panel sized to the avatar, grown only while a whisper shows. D4 records the route it takes in the phase log.
- The corner is stored locally (spec 6.4). Moving the Orbit moves the expanded client's anchor with it.
- Activation policy, Dock icon and app menu follow AGENTS.md Q14.

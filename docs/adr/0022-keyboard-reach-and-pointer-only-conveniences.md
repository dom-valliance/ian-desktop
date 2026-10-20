# 0022. How the keyboard reaches the expanded client

Date: 2026-10-20
Status: Accepted

## Context

Spec 6.2 gives the expanded client seven views, and spec 6.8 says every item and action is reachable by keyboard and with VoiceOver. D9's audit walked every view with the keyboard alone and found the platform's own conventions doing most of the work, with a few places where the app adds to them. This records which convention applies where, so a later change does not take it for a bug or quietly widen it.

## Decision

- **List rows move with the arrow keys, with no system setting.** The sidebar and Today's lists (Now, This week, Later) are `List`s bound to a selection, so the arrow keys move through their rows, and Today's selection drives the footer.
- **Buttons and other controls are reached with Tab through macOS's Keyboard navigation setting.** This covers the cards, the selection footer, Agents, Settings and the header. It is the platform's convention: with the setting off, Tab reaches text fields and lists only, and with it on, every control. Dom's keyboard passes ran with it on. The app does not force full keyboard access and does not add its own focus ring or key handling to imitate it.
- **The Commitments tabs also have Command-1, Command-2 and Command-3** while Commitments is shown, for Owed by me, Owed to me and To confirm, beside the segmented control.
- **One prompt is open per window.** Opening a note, time or confirm prompt, or a hand-off field, closes the one already open, so Return and Escape act on the prompt in front of the principal and no other.
- **Resizing the panes and turning the field are pointer-only conveniences.** They carry no information: the field's angle and the pane sizes change how Today is drawn and nothing it says, and every item and action stays reachable through the lists (non-negotiable 8, ADR 0016).

## Consequences

A keyboard user with Keyboard navigation off cannot Tab to a button. That is the system's choice and Settings says nothing about it. The one shortcut the app adds is the Commitments tabs, since a segmented control is slow to reach by arrows. No other shortcut is added in version 0.

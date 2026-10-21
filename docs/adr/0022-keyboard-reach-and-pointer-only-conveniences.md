# 0022. How the keyboard reaches the expanded client

Date: 2026-10-20
Status: Accepted

## Context

Spec 6.2 says "Every view works with the keyboard alone", spec 6.8 says "Full keyboard navigation works inside the expanded client", and AGENTS.md rule 8 says every item and action is reachable from a list row with VoiceOver and the keyboard. D9's audit walked every view with the keyboard alone.

On macOS, Tab moves focus between buttons, pickers and other controls only when the system setting Keyboard navigation (System Settings, Keyboard) is on. It is off by default. With it off, Tab reaches text fields and lists, and the arrow keys move through a list; a button cannot be reached. SwiftUI and AppKit follow this setting; an app that forced full keyboard access on its own would override a choice the principal made for the whole system.

## Decision

This narrows spec 6.2, spec 6.8 and rule 8, and Dom accepted the narrowing on 20 October 2026.

- **With Keyboard navigation off, the keyboard alone reaches lists and text fields, and not the buttons and other controls.** That covers the cards, the header, Agents and Settings. A principal who wants those controls from the keyboard turns the setting on, which is the platform's convention and the one Dom's keyboard passes used. The app does not force it, and adds no focus ring or key handling of its own to imitate it.
- **Today is the exception and works with the keyboard alone whatever the setting.** With a row selected in Today's list:
  - Return enters an action mode on the footer;
  - Left and Right move a visible highlight across the footer's targets in the order the server sent them: the item's actions, a week group's member items, or a later group's counts;
  - Return acts on the highlighted target through the shared action component, so a confirm, time or note prompt opens and takes focus as it does for a click;
  - Escape returns to the row.
  The keys are key equivalents, so they do not depend on focus or on the setting. Return is claimed only while a target exists and no prompt is open, and the arrows and Escape only inside the mode, so a prompt, a text field and the panel's own Escape keep their keys. VoiceOver is unchanged: the footer's own buttons stay its controls.
- **List rows move with the arrow keys, with no system setting.** The sidebar and Today's lists are `List`s bound to a selection.
- **The Commitments tabs also have Command-1, Command-2 and Command-3** while Commitments is shown.
- **One prompt is open per window.** Opening a note, time or confirm prompt, or a hand-off field, closes the one already open, so Return and Escape act on the prompt in front of the principal and no other.
- **Resizing the panes and turning the field are pointer-only conveniences.** They carry no information: the field's angle and the pane sizes change how Today is drawn and nothing it says, and every item and action stays reachable through the lists (non-negotiable 8, ADR 0016).

## Consequences

Outside Today, a keyboard-only principal must turn Keyboard navigation on to press a card's buttons. Spec 6.2 and 6.8 are met in full only with that setting on, and by Today's own path with it off. The Today path adds four keys that act without focus, and its logic is tested without a view. Whether the keys reach the window with the setting off is checked by hand.

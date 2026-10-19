# 0014. System windows are swept

Date: 2026-10-19
Status: Accepted

## Context

ADR 0006 says every window sets `sharingType = .none` and that every window is made through one factory in `Surface`. The factory covers the Orbit, its hover label and the expanded client. It cannot cover windows that AppKit and SwiftUI create themselves:

- The status item's window behind the `MenuBarExtra`, and the window of the menu it opens.
- The window of the Orbit's right-click `NSMenu`, which `NSMenu.popUpContextMenu` creates.

Their content is the menu's own text: "Open", "Pause me", "Settings", "Quit Ian", the count in the title and the temporary status lines, which carry counts, ages and connection states and no item text. Even so, a window the app owns that is capturable would break the rule's intent.

## Decision

`SurfaceController` sets `sharingType = .none` on every entry of `NSApplication.windows` that has another value, and it does so:

- in `start()`;
- when a menu begins tracking (`NSMenu.didBeginTrackingNotification`);
- when any window's occlusion state changes (`NSWindow.didChangeOcclusionStateNotification`, observed for all windows).

A window that is newly shown moves from no occlusion state to visible, so the occlusion notification fires for system windows as they appear, without polling. The sweep writes only when the value differs.

## Consequences

- ADR 0006 is met in two ways: the factory for windows Ian builds, and the sweep for windows the system builds. A test calls `start()` and asserts `NSApp.windows.allSatisfy { $0.sharingType == .none }`, and further tests post each notification with a window that is capturable.
- There is a short interval between a system window being created and the notification arriving. The menus carry no item text (a test asserts that for the menu model and the status lines), so the gap exposes nothing that suppression protects.
- Any later menu or status text that carries item text needs its own review under ADR 0006.
- A window created by a system framework and never shown does not trigger the sweep until it is shown, which is when capture could see it.

import Foundation
import UserNotifications
import os

/// `UNUserNotificationCenter` behind `NotificationDelivering`. Only the app target creates it.
/// `UNUserNotificationCenter.current()` raises an exception in a process with no bundle, so no
/// test reaches this type.
///
/// `@unchecked Sendable`: the protocol is `Sendable` and the delegate is an `NSObject`, so the
/// compiler cannot see that the only mutable state, the response handler, sits behind a lock.
public final class UserNotificationCentre: NSObject, NotificationDelivering,
  UNUserNotificationCenterDelegate, @unchecked Sendable
{
  private static let itemIDKey = "itemID"

  /// Read by the delegate on a system queue, so it is set once, under the lock.
  private let handler = OSAllocatedUnfairLock<
    (@MainActor @Sendable (NotificationResponse) -> Void)?
  >(
    initialState: nil)

  /// Looked up on first use, so building the adapter touches no bundle state.
  private var centre: UNUserNotificationCenter { .current() }

  public override init() {
    super.init()
  }

  /// The first handler stays; a later call (a restart of the coordinator) changes nothing, so the
  /// delegate never sees the handler replaced while it may be reading it.
  public func setResponseHandler(
    _ handler: @escaping @MainActor @Sendable (NotificationResponse) -> Void
  ) {
    self.handler.withLock { if $0 == nil { $0 = handler } }
    centre.delegate = self
  }

  public func requestAuthorisation() async {
    _ = try? await centre.requestAuthorization(options: [.alert, .sound])
  }

  /// Returns once the system reports the categories, so a banner is never shown before its
  /// buttons are known. The wait is bounded, and the banner goes out regardless.
  public func setCategories(_ categories: [NotificationCategory]) async {
    centre.setNotificationCategories(
      Set(
        categories.map { category in
          UNNotificationCategory(
            identifier: category.id,
            actions: category.buttons.map {
              UNNotificationAction(identifier: $0.identifier, title: $0.title, options: [])
            },
            intentIdentifiers: [])
        }))
    let wanted = Set(categories.map(\.id))
    for _ in 0..<20 {
      let known = await centre.notificationCategories().map(\.identifier)
      if wanted.isSubset(of: known) { return }
      try? await Task.sleep(for: .milliseconds(25))
    }
  }

  public func add(_ content: NotificationContent) async {
    let body = UNMutableNotificationContent()
    body.title = content.title
    body.body = content.body
    body.categoryIdentifier = content.category.id
    body.userInfo = [Self.itemIDKey: content.id]
    body.sound = content.playsSound ? .default : nil
    try? await centre.add(
      UNNotificationRequest(identifier: content.id, content: body, trigger: nil))
  }

  public func withdraw(ids: [String]) async {
    centre.removeDeliveredNotifications(withIdentifiers: ids)
    centre.removePendingNotificationRequests(withIdentifiers: ids)
  }

  public func withdrawAll() async {
    centre.removeAllDeliveredNotifications()
    centre.removeAllPendingNotificationRequests()
  }

  // MARK: UNUserNotificationCenterDelegate

  /// Banners show even while Ian is frontmost (the expanded client may be open).
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    notification.request.content.sound == nil ? [.banner, .list] : [.banner, .list, .sound]
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    guard let itemID = userInfo[Self.itemIDKey] as? String else { return }
    let choice: NotificationResponse.Choice =
      NotificationButton.actionID(forIdentifier: response.actionIdentifier).map { .action($0) }
      ?? .open
    let handler = handler.withLock { $0 }
    await MainActor.run { handler?(NotificationResponse(itemID: itemID, choice: choice)) }
  }
}

import Foundation
@preconcurrency import UserNotifications

/// `UNUserNotificationCenter` behind `NotificationDelivering`. Only the app target creates it.
/// `UNUserNotificationCenter.current()` raises an exception in a process with no bundle, so no
/// test reaches this type.
public final class UserNotificationCentre: NSObject, NotificationDelivering,
  UNUserNotificationCenterDelegate, @unchecked Sendable
{
  private static let itemIDKey = "itemID"

  /// Looked up on first use, so building the adapter touches no bundle state.
  private var centre: UNUserNotificationCenter { .current() }
  // Set once, before the delegate is installed, and read only after.
  private nonisolated(unsafe) var onResponse: (@MainActor @Sendable (NotificationResponse) -> Void)?

  public override init() {
    super.init()
  }

  public func setResponseHandler(
    _ handler: @escaping @MainActor @Sendable (NotificationResponse) -> Void
  ) {
    onResponse = handler
    centre.delegate = self
  }

  public func authorise() async -> Bool {
    (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
  }

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
    let button = response.actionIdentifier
    let choice: NotificationResponse.Choice
    if let actionID = NotificationButton.actionID(forIdentifier: button) {
      choice = .action(actionID)
    } else {
      choice = .open
    }
    let handler = onResponse
    await MainActor.run { handler?(NotificationResponse(itemID: itemID, choice: choice)) }
  }
}

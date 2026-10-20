/// The one-shot "open on the next pointer movement" of a Stop item (spec 6.6). The surface calls
/// `pointerMoved` from the pointer monitors it already installs.
@MainActor
public final class StopArming {
  public private(set) var destination: ItemDestination?
  /// The Stop item that armed it.
  public private(set) var itemID: String?

  public init() {}

  public var isArmed: Bool { destination != nil }

  /// Arms for the item's view. Nothing arms while suppressed or while the panel is open, and a
  /// newer Stop item takes over from an older one.
  public func arm(
    _ destination: ItemDestination, for itemID: String, isPanelOpen: Bool,
    suppression: Suppression
  ) {
    guard !isPanelOpen, !suppression.isActive else { return }
    self.destination = destination
    self.itemID = itemID
  }

  public func disarm() {
    destination = nil
    itemID = nil
  }

  /// Disarms when the item that armed it has gone.
  public func disarm(ifArmedFor itemID: String) {
    if self.itemID == itemID { disarm() }
  }

  /// Disarms on the first movement after arming and returns the view to open, which is nil while
  /// suppressed or when the principal has already opened the panel.
  public func pointerMoved(isPanelOpen: Bool, suppression: Suppression) -> ItemDestination? {
    guard let destination else { return nil }
    disarm()
    return isPanelOpen || suppression.isActive ? nil : destination
  }
}

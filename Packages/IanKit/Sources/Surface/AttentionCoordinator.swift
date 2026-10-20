import Attention
import Observation
import Store

/// Turns what the store holds into what the principal sees and hears (spec 6.6, ADR 0020). It
/// watches the store's items and the suppression, asks the planner which items escalated and the
/// ladder what each rung does, then delivers notifications, shows the whisper and arms Stop.
///
/// It decides no rung and holds no state beyond the planner's memory and what it delivered.
/// Delivery calls run one after another, in the order they were made, across restarts.
@MainActor
public final class AttentionCoordinator {
  private let store: IanStore
  private let settings: ClientSettings
  private let suppression: @MainActor () -> Suppression
  private let delivery: any NotificationDelivering
  private let whisper: Whisper
  private let stopArming: StopArming
  private let isPanelOpen: @MainActor () -> Bool
  private let showItem: @MainActor (ItemDestination) -> Void

  /// What the coordinator knows of a notification it delivered and the system may still hold.
  private struct Delivered {
    let category: NotificationCategory
    let rung: NotificationRung
    /// The item's version when delivered, so a button never acts on a newer one.
    let version: Int
    /// False for a notification that was delivered while suppressed.
    let showsItemText: Bool
  }

  private var planner = EscalationPlanner()
  private var delivered: [String: Delivered] = [:]
  private var isRunning = false
  /// Raised by each start, so a stale observation or delivery of an earlier run does nothing.
  private var run = 0
  private var queue: Task<Void, Never>?

  public init(
    store: IanStore, settings: ClientSettings,
    suppression: @escaping @MainActor () -> Suppression, delivery: any NotificationDelivering,
    whisper: Whisper, stopArming: StopArming, isPanelOpen: @escaping @MainActor () -> Bool,
    showItem: @escaping @MainActor (ItemDestination) -> Void
  ) {
    self.store = store
    self.settings = settings
    self.suppression = suppression
    self.delivery = delivery
    self.whisper = whisper
    self.stopArming = stopArming
    self.isPanelOpen = isPanelOpen
    self.showItem = showItem
  }

  public convenience init(
    store: IanStore, controller: SurfaceController, delivery: any NotificationDelivering
  ) {
    self.init(
      store: store, settings: controller.settings, suppression: { controller.suppression },
      delivery: delivery, whisper: controller.whisper, stopArming: controller.stopArming,
      isPanelOpen: { controller.isExpandedVisible },
      showItem: { controller.showItem($0) })
  }

  /// Clears what an earlier launch left in Notification Centre, asks for permission once, then
  /// watches the store. Starting again after `stop()` begins afresh.
  public func start() {
    guard !isRunning else { return }
    isRunning = true
    run += 1
    planner = EscalationPlanner()
    delivered = [:]
    delivery.setResponseHandler { [weak self] response in self?.handle(response) }
    enqueue { [delivery] in
      await delivery.withdrawAll()
      await delivery.requestAuthorisation()
    }
    observe(run: run)
  }

  /// Stops watching. The delivery queue stays chained, so a call already in flight finishes
  /// before a later start clears the centre; the run counter makes the rest inert.
  public func stop() {
    isRunning = false
  }

  /// Resolves once every delivery call made so far has finished.
  func settled() async {
    await queue?.value
  }

  // MARK: Watching

  private func observe(run: Int) {
    guard isRunning, run == self.run else { return }
    withObservationTracking {
      reconcile()
    } onChange: { [weak self] in
      Task { @MainActor in self?.observe(run: run) }
    }
  }

  private func reconcile() {
    let state = store.state
    let current = suppression()
    let hasSnapshot = state.today != nil
    if current.isActive || !hasSnapshot {
      whisper.hide()
      stopArming.disarm()
    }
    if current.isActive { holdBackText(state: state) }
    let plan = planner.observe(state.items.values.map(ObservedItem.init), hasSnapshot: hasSnapshot)
    for id in plan.removed { stopArming.disarm(ifArmedFor: id) }
    withdraw(plan.removed)

    // The plan lists the most urgent first, then by id. The whisper and Stop take the first that
    // asks for them, so the most urgent wins and the lowest id breaks a tie.
    let batch: [(item: StoreState.Item, rung: NotificationRung, behaviour: AttentionBehaviour)] =
      plan.escalations.compactMap { escalation in
        guard let item = state.items[escalation.id] else { return nil }
        let level = settings.level(for: escalation.rung)
        return (
          item, escalation.rung,
          AttentionLadder.behaviour(of: escalation.rung, level: level, suppression: current)
        )
      }
    if let urgent = batch.first(where: { $0.behaviour.orbit == .whisper }) {
      whisper.show(urgent.item.title)
    }
    if let stop = batch.first(where: { $0.behaviour.orbit == .opensOnPointerMovement }) {
      stopArming.arm(
        ItemDestination(item: stop.item), for: stop.item.id, isPanelOpen: isPanelOpen(),
        suppression: current)
    }
    // Least urgent first, so a Stop banner lands last and on top.
    for entry in batch.reversed() where entry.behaviour.notification != .none {
      deliver(
        NotificationContent(
          item: entry.item, rung: entry.rung, showsItemText: entry.behaviour.showsItemText),
        rung: entry.rung, version: entry.item.version,
        showsItemText: entry.behaviour.showsItemText)
    }
  }

  /// Suppression has started. A notification that shows item text is withdrawn, except a Stop
  /// (P0, AGENTS.md rule 6): that stays in Notification Centre, replaced by the suppressed
  /// content under the same id, silently. The system may show the replacement as a banner.
  private func holdBackText(state: StoreState) {
    var withdrawn: [String] = []
    for (id, entry) in delivered.sorted(by: { $0.key < $1.key }) where entry.showsItemText {
      if entry.rung == .stop, let item = state.items[id] {
        deliver(
          NotificationContent(item: item, rung: .stop, showsItemText: false, playsSound: false),
          rung: .stop, version: item.version, showsItemText: false)
      } else {
        withdrawn.append(id)
      }
    }
    withdraw(withdrawn)
  }

  // MARK: Delivering

  private func deliver(
    _ content: NotificationContent, rung: NotificationRung, version: Int, showsItemText: Bool
  ) {
    delivered[content.id] = Delivered(
      category: content.category, rung: rung, version: version, showsItemText: showsItemText)
    let categories = registeredCategories
    enqueue { [delivery] in
      await delivery.setCategories(categories)
      await delivery.add(content)
    }
  }

  private func withdraw(_ ids: [String]) {
    let held = ids.filter { delivered[$0] != nil }
    guard !held.isEmpty else { return }
    for id in held { delivered[id] = nil }
    let categories = registeredCategories
    enqueue { [delivery] in
      await delivery.withdraw(ids: held)
      await delivery.setCategories(categories)
    }
  }

  /// Exactly the categories the held notifications use.
  private var registeredCategories: [NotificationCategory] {
    Dictionary(grouping: delivered.values.map(\.category), by: \.id).values.compactMap(\.first)
      .sorted { $0.id < $1.id }
  }

  private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
    let previous = queue
    let mine = run
    queue = Task { @MainActor in
      await previous?.value
      guard isRunning, mine == run else { return }
      await operation()
    }
  }

  // MARK: Responses

  /// Runs what the principal chose on a notification. An action goes through the store only when
  /// the item is still the version the banner showed, nothing is pending on it and the action is still one a banner may
  /// run; otherwise the view opens, so the principal sees what changed. The store marks the item
  /// pending and leaves the server to move it (AGENTS.md rule 2). Open, and the notification
  /// itself, bring up the view that holds the item, or Today if it has gone.
  @discardableResult
  func handle(_ response: NotificationResponse) -> Task<Void, Never> {
    if case .action(let actionID) = response.choice, canRun(actionID, on: response.itemID) {
      return Task { await store.run(actionID: actionID, on: response.itemID) }
    }
    showItem(store.state.items[response.itemID].map { ItemDestination(item: $0) } ?? .today)
    return Task {}
  }

  private func canRun(_ actionID: String, on itemID: String) -> Bool {
    guard let held = delivered[itemID], let item = store.state.items[itemID],
      item.version == held.version, store.pending[itemID] == nil, store.actionsEnabled
    else { return false }
    return NotificationCategory.quickActionIDs(of: item).contains(actionID)
  }
}

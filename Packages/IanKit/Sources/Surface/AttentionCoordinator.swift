import Attention
import Observation
import Store

/// Turns what the store holds into what the principal sees and hears (spec 6.6, ADR 0020). It
/// watches the store's items and the suppression, asks the planner which items escalated and the
/// ladder what each rung does, then delivers notifications, shows the whisper and arms Stop.
///
/// It decides no rung and holds no state beyond the planner's memory. Delivery calls run one
/// after another, in the order they were made.
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

  private var planner = EscalationPlanner()
  /// The category of each notification the system may still hold, so the registered set stays to
  /// what those notifications need.
  private var delivered: [String: NotificationCategory] = [:]
  private var isAuthorised = false
  private var isRunning = false
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

  /// Asks for permission once, then watches the store.
  public func start() {
    guard !isRunning else { return }
    isRunning = true
    delivery.setResponseHandler { [weak self] response in self?.handle(response) }
    enqueue { [self] in isAuthorised = await delivery.authorise() }
    observe()
  }

  public func stop() {
    isRunning = false
  }

  /// Resolves once every delivery call made so far has finished.
  func settled() async {
    await queue?.value
  }

  // MARK: Watching

  private func observe() {
    guard isRunning else { return }
    withObservationTracking {
      reconcile()
    } onChange: { [weak self] in
      Task { @MainActor in self?.observe() }
    }
  }

  func reconcile() {
    let state = store.state
    let current = suppression()
    if current.isActive {
      whisper.hide()
      stopArming.disarm()
    }
    let plan = planner.observe(
      state.items.values.map(ObservedItem.init), hasSnapshot: state.today != nil)
    withdraw(plan.removed)
    for escalation in plan.escalations {
      guard let item = state.items[escalation.id] else { continue }
      let behaviour = AttentionLadder.behaviour(
        of: escalation.rung, level: settings.level(for: escalation.rung), suppression: current)
      apply(behaviour, to: item, rung: escalation.rung, suppression: current)
    }
  }

  private func apply(
    _ behaviour: AttentionBehaviour, to item: StoreState.Item, rung: NotificationRung,
    suppression current: Suppression
  ) {
    switch behaviour.orbit {
    case .whisper:
      whisper.show(item.title)
    case .opensOnPointerMovement:
      stopArming.arm(
        ItemDestination(item: item), isPanelOpen: isPanelOpen(), suppression: current)
    case .stateOnly, .growsAndHoldsColour:
      break
    }
    guard behaviour.notification != .none else { return }
    deliver(NotificationContent(item: item, rung: rung, showsItemText: behaviour.showsItemText))
  }

  // MARK: Delivering

  private func deliver(_ content: NotificationContent) {
    delivered[content.id] = content.category
    let categories = registeredCategories
    enqueue { [self] in
      guard isAuthorised else { return }
      await delivery.setCategories(categories)
      await delivery.add(content)
    }
  }

  private func withdraw(_ ids: [String]) {
    let held = ids.filter { delivered[$0] != nil }
    guard !held.isEmpty else { return }
    for id in held { delivered[id] = nil }
    let categories = registeredCategories
    enqueue { [self] in
      await delivery.withdraw(ids: held)
      await delivery.setCategories(categories)
    }
  }

  private var registeredCategories: [NotificationCategory] {
    Dictionary(grouping: delivered.values, by: \.id).values.compactMap(\.first).sorted {
      $0.id < $1.id
    }
  }

  private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
    let previous = queue
    queue = Task { @MainActor in
      await previous?.value
      await operation()
    }
  }

  // MARK: Responses

  /// Runs what the principal chose on a notification. An action goes through the store, which
  /// marks the item pending and leaves the server to move it (AGENTS.md rule 2). Open, and the
  /// notification itself, bring up the view that holds the item, or Today if it has gone.
  @discardableResult
  func handle(_ response: NotificationResponse) -> Task<Void, Never> {
    switch response.choice {
    case .open:
      showItem(store.state.items[response.itemID].map { ItemDestination(item: $0) } ?? .today)
      return Task {}
    case .action(let actionID):
      return Task { await store.run(actionID: actionID, on: response.itemID) }
    }
  }
}

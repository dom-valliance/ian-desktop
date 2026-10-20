import Attention
import Client
import Contract
import Foundation
import Store
import TestSupport
import Testing

@testable import Surface

/// A notification centre that records what it is asked. It never touches the system.
private final class FakeDelivery: NotificationDelivering, @unchecked Sendable {
  private let lock = NSLock()
  private let grants: Bool
  private var _added: [NotificationContent] = []
  private var _withdrawn: [[String]] = []
  private var _categories: [[NotificationCategory]] = []

  init(grants: Bool = true) { self.grants = grants }

  var added: [NotificationContent] { lock.withLock { _added } }
  var withdrawn: [[String]] { lock.withLock { _withdrawn } }
  var lastCategories: [NotificationCategory]? { lock.withLock { _categories.last } }

  func authorise() async -> Bool { grants }
  func setCategories(_ categories: [NotificationCategory]) async {
    lock.withLock { _categories.append(categories) }
  }
  func add(_ content: NotificationContent) async { lock.withLock { _added.append(content) } }
  func withdraw(ids: [String]) async { lock.withLock { _withdrawn.append(ids) } }
  func setResponseHandler(
    _ handler: @escaping @MainActor @Sendable (NotificationResponse) -> Void
  ) {}
}

private let paused = Suppression(
  cameraLive: false, externalMeeting: false, quietHours: false, userPaused: true)

/// What the surface would say, set by the test.
@MainActor
private final class Controls {
  var suppression = Suppression.none
  var isPanelOpen = false
  var shown: [ItemDestination] = []
}

@MainActor
private final class Harness {
  let store: IanStore
  let service: ScriptedService
  let feed: AsyncThrowingStream<StreamMessage, any Error>.Continuation
  let delivery: FakeDelivery
  let whisper = Whisper(sleep: { _ in try await Task.sleep(for: .seconds(600)) })
  let stopArming = StopArming()
  let settings: ClientSettings
  let coordinator: AttentionCoordinator
  let controls = Controls()
  private var lastEvent = 10

  /// A started store holding `items`, with the coordinator started and settled on them.
  init(
    items: [String], defaults: UserDefaults, grants: Bool = true
  ) async {
    service = ScriptedService(
      snapshots: [.success(Fixtures.snapshot(cursor: "10", items: items))])
    feed = service.planStream()
    store = IanStore(
      service: service, profile: .mock,
      appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    delivery = FakeDelivery(grants: grants)
    settings = ClientSettings(defaults: defaults)
    let controls = controls
    coordinator = AttentionCoordinator(
      store: store, settings: settings, suppression: { controls.suppression },
      delivery: delivery, whisper: whisper, stopArming: stopArming,
      isPanelOpen: { controls.isPanelOpen }, showItem: { controls.shown.append($0) })
    store.start()
    _ = await eventually { await MainActor.run { self.store.connection == .live } }
    coordinator.start()
    await sync()
  }

  func finish() {
    coordinator.stop()
    store.stop()
  }

  func sync() async {
    coordinator.reconcile()
    await coordinator.settled()
  }

  func upsert(_ item: String) async {
    await send(Fixtures.upsertedJSON(item))
  }

  func remove(_ id: String) async {
    await send(Fixtures.removedJSON(id))
  }

  private func send(_ json: String) async {
    lastEvent += 1
    let id = lastEvent
    feed.yield(.event(id: String(id), Fixtures.event(json)))
    _ = await eventually { await MainActor.run { self.store.state.lastEventID == UInt64(id) } }
    await sync()
  }
}

private func urgent(
  _ id: String = "task_1", attention: String = "urgent",
  actions: [Fixtures.ActionSpec] = [Fixtures.ActionSpec("done")], version: Int = 1
) -> String {
  Fixtures.itemJSON(
    id: id, version: version, title: "Reply to [PERSON] about [CLIENT]", actions: actions,
    attention: attention, meta: "[CLIENT] steering group")
}

@Suite("The attention coordinator")
@MainActor
struct AttentionCoordinatorTests {
  @Test("a new urgent item shows a banner with its actions and whispers its title")
  func newUrgent() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults)
      defer { harness.finish() }

      await harness.upsert(urgent(actions: [Fixtures.ActionSpec("approve")]))

      let added = harness.delivery.added
      #expect(added.map(\.id) == ["task_1"])
      #expect(added.first?.title == "Reply to [PERSON] about [CLIENT]")
      #expect(added.first?.body == "[CLIENT] steering group")
      #expect(added.first?.category.buttons.map(\.title) == ["Approve", "Open"])
      #expect(added.first?.playsSound == false)
      #expect(harness.whisper.title == "Reply to [PERSON] about [CLIENT]")
      #expect(!harness.stopArming.isArmed)
    }
  }

  @Test("the first snapshot notifies only for stop items and arms Stop")
  func baseline() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(
        items: [
          urgent("task_1"), urgent("task_2", attention: "stop"),
          urgent("task_3", attention: "needs_you"),
        ], defaults: defaults)
      defer { harness.finish() }

      #expect(harness.delivery.added.map(\.id) == ["task_2"])
      #expect(harness.delivery.added.first?.playsSound == true)
      #expect(harness.whisper.title == nil)
      #expect(harness.stopArming.destination == .tasks)
    }
  }

  @Test("a rise notifies, a repeat does not, and a fall then a rise notifies again")
  func riseRepeatFall() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(
        items: [urgent(attention: "needs_you")], defaults: defaults)
      defer { harness.finish() }
      #expect(harness.delivery.added.isEmpty)

      await harness.upsert(urgent(attention: "urgent", version: 2))
      #expect(harness.delivery.added.count == 1)
      await harness.upsert(urgent(attention: "urgent", version: 3))
      #expect(harness.delivery.added.count == 1)
      await harness.upsert(urgent(attention: "needs_you", version: 4))
      #expect(harness.delivery.added.count == 1)
      await harness.upsert(urgent(attention: "urgent", version: 5))
      #expect(harness.delivery.added.count == 2)
    }
  }

  @Test("an urgent item whose level is Off whispers and sends no notification")
  func levelOff() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults)
      defer { harness.finish() }
      harness.settings.setLevel(.off, for: .urgent)

      await harness.upsert(urgent())

      #expect(harness.delivery.added.isEmpty)
      #expect(harness.whisper.title != nil)
    }
  }

  @Test("a needs you item notifies when its level is Banner")
  func needsYouBanner() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults)
      defer { harness.finish() }
      harness.settings.setLevel(.banner, for: .needsYou)

      await harness.upsert(urgent(attention: "needs_you"))

      #expect(harness.delivery.added.count == 1)
      #expect(harness.whisper.title == nil)
    }
  }

  @Test("while suppressed a stop item is still delivered and its notification names no item")
  func stopDeliveredWhileSuppressed() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults)
      defer { harness.finish() }
      harness.controls.suppression = paused

      await harness.upsert(
        urgent(attention: "stop", actions: [Fixtures.ActionSpec("approve")]))

      let added = harness.delivery.added
      #expect(added.count == 1)
      #expect(added.first?.title == "Ian")
      #expect(added.first?.body == NotificationContent.suppressedBody)
      #expect(added.first?.category.buttons.map(\.title) == ["Open"])
      for text in [added.first?.title, added.first?.body, added.first?.id] {
        #expect(text?.contains("[PERSON]") != true)
        #expect(text?.contains("steering") != true)
      }
      #expect(!harness.stopArming.isArmed)
    }
  }

  @Test("while suppressed an urgent item sends nothing and does not whisper, and is not replayed")
  func urgentDroppedWhileSuppressed() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults)
      defer { harness.finish() }
      harness.controls.suppression = paused

      await harness.upsert(urgent())
      #expect(harness.delivery.added.isEmpty)
      #expect(harness.whisper.title == nil)

      harness.controls.suppression = .none
      await harness.sync()
      #expect(harness.delivery.added.isEmpty)
      #expect(harness.whisper.title == nil)
    }
  }

  @Test("suppression starting hides the whisper at once and disarms Stop")
  func suppressionHides() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults)
      defer { harness.finish() }
      await harness.upsert(urgent())
      await harness.upsert(urgent("task_2", attention: "stop"))
      #expect(harness.whisper.title != nil)
      #expect(harness.stopArming.isArmed)

      harness.controls.suppression = paused
      await harness.sync()

      #expect(harness.whisper.title == nil)
      #expect(!harness.stopArming.isArmed)
    }
  }

  @Test("a stop item does not arm when the panel is already open")
  func stopWithPanelOpen() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults)
      defer { harness.finish() }
      harness.controls.isPanelOpen = true

      await harness.upsert(urgent(attention: "stop"))

      #expect(harness.delivery.added.count == 1)
      #expect(!harness.stopArming.isArmed)
    }
  }

  @Test("a newer urgent item replaces the whisper")
  func whisperReplaced() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults)
      defer { harness.finish() }
      await harness.upsert(
        Fixtures.itemJSON(id: "task_1", title: "First", attention: "urgent"))
      await harness.upsert(
        Fixtures.itemJSON(id: "task_2", title: "Second", attention: "urgent"))
      #expect(harness.whisper.title == "Second")
    }
  }

  @Test("an item that leaves the store has its notification withdrawn and its category dropped")
  func removalWithdraws() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults)
      defer { harness.finish() }
      await harness.upsert(urgent("task_1", actions: [Fixtures.ActionSpec("approve")]))
      await harness.upsert(urgent("task_2", actions: [Fixtures.ActionSpec("later")]))
      #expect(harness.delivery.lastCategories?.count == 2)

      await harness.remove("task_1")

      #expect(harness.delivery.withdrawn == [["task_1"]])
      #expect(harness.delivery.lastCategories?.map(\.id) == ["ian.item.later"])
    }
  }

  @Test("a sign-out withdraws what was delivered")
  func signOutWithdraws() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults)
      defer { harness.finish() }
      await harness.upsert(urgent())

      await harness.store.signOut()
      await harness.sync()

      #expect(harness.delivery.withdrawn == [["task_1"]])
    }
  }

  @Test("nothing is delivered when permission is refused, and the whisper still shows")
  func refused() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(items: [], defaults: defaults, grants: false)
      defer { harness.finish() }

      await harness.upsert(urgent())

      #expect(harness.delivery.added.isEmpty)
      #expect(harness.whisper.title != nil)
    }
  }

  @Test("an action button runs the item's action and leaves the item pending, not moved")
  func actionButton() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(
        items: [urgent(actions: [Fixtures.ActionSpec("approve")])], defaults: defaults)
      defer { harness.finish() }

      await harness.coordinator.handle(
        NotificationResponse(itemID: "task_1", choice: .action("approve"))
      ).value

      #expect(harness.service.actionCalls.map(\.actionID) == ["approve"])
      #expect(harness.service.actionCalls.map(\.itemID) == ["task_1"])
      #expect(harness.store.pending["task_1"] != nil)
      #expect(harness.store.state.items["task_1"] != nil)
    }
  }

  @Test("Open shows the view that holds the item, and Today when the item has gone")
  func open() async {
    await withScratchDefaultsAsync { defaults in
      let harness = await Harness(
        items: [urgent("task_1"), Fixtures.itemJSON(id: "alert_1", alert: true)],
        defaults: defaults)
      defer { harness.finish() }

      harness.coordinator.handle(NotificationResponse(itemID: "task_1", choice: .open))
      harness.coordinator.handle(NotificationResponse(itemID: "alert_1", choice: .open))
      harness.coordinator.handle(NotificationResponse(itemID: "gone", choice: .open))

      #expect(harness.controls.shown == [.tasks, .alerts, .today])
    }
  }
}

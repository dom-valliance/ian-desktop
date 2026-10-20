import Contract
import Store

/// Puts an item the server has just removed back where its view had it, for as long as the store
/// keeps its removal record (the ten seconds the store's clock allows), the way Today keeps a
/// leaving row at its last place. The server sends `item.removed` and then a `views.updated`
/// without the id, so without this the card would last a frame.
///
/// The place is the group and index the removal recorded from the views of that moment. When the
/// server's own `views` still name the id, that position wins and nothing is put back.
enum LeavingItems {
  typealias Group = Components.Schemas.ViewGroup
  typealias Section = Components.Schemas.TaskSection

  static func proposals(
    _ views: Components.Schemas.Views, removals: [String: IanStore.Removal]
  ) -> [Group] {
    restoring(views.proposals, removals: removals, named: named(in: views)) { $0.proposals }
  }

  static func alerts(
    _ views: Components.Schemas.Views, removals: [String: IanStore.Removal]
  ) -> [Group] {
    restoring(views.alerts, removals: removals, named: named(in: views)) { $0.alerts }
  }

  static func commitments(
    _ views: Components.Schemas.Views, removals: [String: IanStore.Removal]
  ) -> Components.Schemas.CommitmentTabs {
    var tabs = views.commitments
    let named = named(in: views)
    for removal in leaving(removals, notIn: named) {
      guard let old = removal.viewsWhenRemoved?.commitments else { continue }
      let id = removal.item.id
      if let index = old.owedByMe.firstIndex(of: id) {
        tabs.owedByMe.insert(id, at: min(index, tabs.owedByMe.count))
      } else if let index = old.owedToMe.firstIndex(of: id) {
        tabs.owedToMe.insert(id, at: min(index, tabs.owedToMe.count))
      } else if let index = old.toConfirm.firstIndex(of: id) {
        tabs.toConfirm.insert(id, at: min(index, tabs.toConfirm.count))
      }
    }
    return tabs
  }

  static func tasks(
    _ views: Components.Schemas.Views, removals: [String: IanStore.Removal]
  ) -> [Section] {
    var sections = views.tasks
    for removal in leaving(removals, notIn: named(in: views)) {
      guard let old = removal.viewsWhenRemoved?.tasks,
        let oldSectionIndex = old.firstIndex(where: { section in
          section.groups.contains { $0.itemIds.contains(removal.item.id) }
        })
      else { continue }
      let oldSection = old[oldSectionIndex]
      if let index = sections.firstIndex(where: { $0.horizon == oldSection.horizon }) {
        sections[index].groups = restoring(
          sections[index].groups, removals: [removal.item.id: removal], named: []
        ) { views in views.tasks.first { $0.horizon == oldSection.horizon }?.groups ?? [] }
      } else {
        var restored = oldSection
        restored.groups = restoring([], removals: [removal.item.id: removal], named: []) { views in
          views.tasks.first { $0.horizon == oldSection.horizon }?.groups ?? []
        }
        sections.insert(restored, at: min(oldSectionIndex, sections.count))
      }
    }
    return sections
  }

  /// Every id the current views name, which keep their own place.
  private static func named(in views: Components.Schemas.Views) -> Set<String> {
    var ids = Set(views.proposals.flatMap(\.itemIds))
    ids.formUnion(views.alerts.flatMap(\.itemIds))
    ids.formUnion(
      views.commitments.owedByMe + views.commitments.owedToMe + views.commitments.toConfirm)
    ids.formUnion(views.tasks.flatMap(\.groups).flatMap(\.itemIds))
    return ids
  }

  /// The removals the views no longer name, oldest first so the result does not depend on the
  /// dictionary's order.
  private static func leaving(_ removals: [String: IanStore.Removal], notIn named: Set<String>)
    -> [IanStore.Removal]
  {
    removals.values.filter { !named.contains($0.item.id) }
      .sorted { ($0.removedAt, $0.item.id) < ($1.removedAt, $1.item.id) }
  }

  private static func restoring(
    _ groups: [Group], removals: [String: IanStore.Removal], named: Set<String>,
    oldGroups: (Components.Schemas.Views) -> [Group]
  ) -> [Group] {
    var result = groups
    for removal in leaving(removals, notIn: named) {
      let id = removal.item.id
      guard let views = removal.viewsWhenRemoved else { continue }
      let old = oldGroups(views)
      guard let oldIndex = old.firstIndex(where: { $0.itemIds.contains(id) }),
        let position = old[oldIndex].itemIds.firstIndex(of: id)
      else { continue }
      if let index = result.firstIndex(where: { $0.id == old[oldIndex].id }) {
        result[index].itemIds.insert(id, at: min(position, result[index].itemIds.count))
      } else {
        var restored = old[oldIndex]
        restored.itemIds = [id]
        result.insert(restored, at: min(oldIndex, result.count))
      }
    }
    return result
  }
}

import Contract

@testable import Features

extension ListedGroup {
  /// The items of the group, for tests that compare ids.
  var items: [Components.Schemas.Item] { entries.map(\.item) }
}

extension CommitmentsListModel {
  func items(in tab: Tab) -> [Components.Schemas.Item] { entries(in: tab).map(\.item) }
}

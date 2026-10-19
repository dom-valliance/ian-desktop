import Client
import Foundation

extension IanStore {
  /// The longest instruction the contract accepts.
  public static let handoffInstructionLimit = 2000

  /// Whether the server offers "Hand to Ian" to this client (`Me.capabilities.handoff`).
  public var offersHandoff: Bool { state.me?.capabilities.handoff ?? false }

  /// Hands the item to Ian. Like an action, it marks the item pending and nothing more: the event
  /// that carries the returned correlation id moves the item and clears the mark. A blank
  /// instruction is sent as none.
  public func handOff(itemID: String, instruction: String? = nil) async {
    guard let item = state.items[itemID], offersHandoff, pending[itemID] == nil else { return }
    guard actionsEnabled else {
      notices[itemID] = .failed(DesktopError.offline.localizedDescription)
      return
    }
    let trimmed = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = trimmed?.isEmpty == false ? trimmed : nil
    guard (text?.count ?? 0) <= Self.handoffInstructionLimit else {
      notices[itemID] = .failed(
        "Shorten the instruction to \(Self.handoffInstructionLimit) characters or fewer.")
      return
    }
    await markPendingAndSend(actionID: "handoff", item: item) {
      try await service.handOff(itemID: itemID, instruction: text)
    }
  }
}

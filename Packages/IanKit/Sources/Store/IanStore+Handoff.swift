import Client
import Foundation

extension IanStore {
  /// The longest instruction the contract accepts.
  public static let handoffInstructionLimit = 2000

  /// An instruction as it is sent: trimmed, and nil when nothing is left.
  public static func normalisedInstruction(_ text: String?) -> String? {
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == false ? trimmed : nil
  }

  /// Whether the instruction, as it would be sent, is within the contract's limit. The limit
  /// counts Unicode scalars, as the contract's schema does.
  public static func instructionFits(_ text: String?) -> Bool {
    (normalisedInstruction(text)?.unicodeScalars.count ?? 0) <= handoffInstructionLimit
  }

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
    let text = Self.normalisedInstruction(instruction)
    guard Self.instructionFits(text) else {
      notices[itemID] = .failed(
        "Shorten the instruction to \(Self.handoffInstructionLimit) characters or fewer.")
      return
    }
    await markPendingAndSend(actionID: "handoff", item: item) {
      try await service.handOff(itemID: itemID, instruction: text)
    }
  }
}

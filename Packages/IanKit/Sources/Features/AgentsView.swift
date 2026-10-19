import Contract
import Store
import SwiftUI

/// The Agents view (spec 6.3): today's cost, a table of every watcher, agent and job in the
/// server's order, and the read-only banner while the kill switch is on.
struct AgentsView: View {
  let store: IanStore

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let global = store.state.settings?.global, let notice = KillSwitchNotice(global: global) {
        KillSwitchBanner(notice: notice)
      }
      CostHeader(cost: store.state.costToday)
      if store.state.agents.isEmpty {
        Text("No agents are running for you yet.")
          .foregroundStyle(ClientPalette.secondary())
      } else {
        AgentTable(store: store)
      }
      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Agents")
  }
}

private struct KillSwitchBanner: View {
  let notice: KillSwitchNotice

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(notice.title)
        .font(.system(size: 14, weight: .medium))
      Text(notice.message)
        .font(.system(size: 13))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.3), lineWidth: 1))
    .accessibilityElement(children: .combine)
  }
}

private struct CostHeader: View {
  let cost: Components.Schemas.CostToday?

  var body: some View {
    if let cost {
      let text =
        "Cost today \(AgentRow.money(cost.costGbp)) of a \(AgentRow.money(cost.ceilingGbp)) "
        + "ceiling (\(AgentRow.percent(cost.fraction)))"
      Text(text)
        .font(.system(size: 15, weight: .medium))
        .accessibilityLabel(text)
    }
  }
}

private struct AgentTable: View {
  let store: IanStore

  private enum Column: String, CaseIterable {
    case name = "Name"
    case kind = "Kind"
    case state = "State"
    case lastRun = "Last run"
    case nextRun = "Next run"
    case cost = "Cost today"
    case share = "Of ceiling"

    var width: CGFloat? {
      switch self {
      case .name: nil
      case .kind: 70
      case .state: 110
      case .lastRun, .nextRun: 130
      case .cost: 80
      case .share: 80
      }
    }
  }

  private static let commandWidth: CGFloat = 96

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 12) {
          ForEach(Column.allCases, id: \.self) { column in
            Text(column.rawValue.uppercased())
              .font(ClientPalette.label)
              .tracking(ClientPalette.labelTracking)
              .foregroundStyle(ClientPalette.secondary(0.7))
              .frame(
                minWidth: column.width, maxWidth: column.width ?? .infinity, alignment: .leading)
          }
          Color.clear.frame(width: Self.commandWidth, height: 1)
        }
        .padding(.vertical, 8)
        .accessibilityHidden(true)
        Divider().overlay(ClientPalette.line)
        ForEach(store.state.agents, id: \.id) { agent in
          AgentRowView(store: store, row: AgentRow(agent: agent), commandWidth: Self.commandWidth)
          Divider().overlay(ClientPalette.line)
        }
      }
    }
  }

  private struct AgentRowView: View {
    let store: IanStore
    let row: AgentRow
    let commandWidth: CGFloat

    private var isPending: Bool { store.agentPending.contains(row.id) }

    var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 12) {
          cell(.name, row.name)
          cell(.kind, row.kind)
          cell(.state, row.state + (row.breaker.map { ", \($0.lowercased())" } ?? ""))
          cell(.lastRun, row.lastRun)
          cell(.nextRun, row.nextRun)
          cell(.cost, row.cost)
          cell(.share, row.share)
          command.frame(width: commandWidth, alignment: .trailing)
        }
        if let notice = store.agentNotices[row.id] {
          Text(notice)
            .font(.system(size: 12))
            .foregroundStyle(ClientPalette.secondary())
            .accessibilityLabel("\(row.name): \(notice)")
        }
      }
      .padding(.vertical, 8)
      .accessibilityElement(children: .contain)
    }

    private func cell(_ column: Column, _ value: String) -> some View {
      Text(value)
        .font(.system(size: 13))
        .frame(minWidth: column.width, maxWidth: column.width ?? .infinity, alignment: .leading)
        .accessibilityLabel("\(row.name), \(column.rawValue): \(value)")
    }

    @ViewBuilder private var command: some View {
      if isPending {
        Text("Pending")
          .font(.system(size: 12))
          .foregroundStyle(ClientPalette.secondary())
          .accessibilityLabel("\(row.name): waiting for Lance")
      } else if let command = row.command {
        let title = command == .pause ? "Pause" : "Resume"
        Button(title) {
          Task {
            if command == .pause {
              await store.pause(agent: row.id)
            } else {
              await store.resume(agent: row.id)
            }
          }
        }
        .buttonStyle(ActionButtonStyle(style: .secondary))
        .disabled(!store.actionsEnabled)
        .accessibilityLabel("\(title) \(row.name)")
      }
    }
  }
}

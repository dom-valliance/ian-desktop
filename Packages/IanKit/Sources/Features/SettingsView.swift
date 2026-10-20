import Attention
import Store
import Surface
import SwiftUI

/// The Settings view (spec 6.4): the principal's settings, which Lance holds, then the client's
/// own, which live on this Mac.
struct SettingsView: View {
  let store: IanStore
  // Weak, as in ExpandedClientView: the controller owns the panel that owns this view.
  private weak var controller: SurfaceController?
  let model: SettingsModel

  init(store: IanStore, controller: SurfaceController?, model: SettingsModel) {
    self.store = store
    self.controller = controller
    self.model = model
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        PrincipalSettingsSection(store: store, model: model.principal(for: store))
        if let controller {
          ClientSettingsSection(store: store, controller: controller, model: model)
        }
      }
      .padding(20)
      .frame(maxWidth: 640, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Settings")
    .onDisappear { model.clearCopied() }
  }
}

/// A titled group of rows.
struct SettingsGroup<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title.uppercased())
        .font(ClientPalette.label)
        .tracking(ClientPalette.labelTracking)
        .foregroundStyle(ClientPalette.secondary(0.7))
        .accessibilityAddTraits(.isHeader)
      content
    }
  }
}

/// A label, an explanation and the control that changes it.
struct SettingRow<Control: View>: View {
  let title: String
  var detail: String?
  @ViewBuilder let control: Control

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 14))
        if let detail {
          Text(detail)
            .font(.system(size: 12))
            .foregroundStyle(ClientPalette.secondary())
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 16)
      control
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
  }
}

// MARK: Principal settings

private struct PrincipalSettingsSection: View {
  let store: IanStore
  @Bindable var model: PrincipalSettingsModel

  var body: some View {
    SettingsGroup(title: "Your settings") {
      if model.settings == nil {
        Text("Ian has not received your settings yet.")
          .foregroundStyle(ClientPalette.secondary())
      } else {
        content
      }
    }
  }

  @ViewBuilder private var content: some View {
    if let notice = model.notice {
      NoticeRow(text: notice, dismiss: store.dismissSettingsNotice)
    }
    if model.isPending {
      Text("Waiting for Ian to confirm the change.")
        .font(.system(size: 12))
        .foregroundStyle(ClientPalette.secondary())
    }
    quietHours
    pushBudget
    ownPause
    mode
    readOnly
  }

  private var quietHours: some View {
    SettingRow(
      title: "Quiet hours",
      detail: "Ian stays quiet in this window, in your time zone."
    ) {
      HStack(spacing: 8) {
        timePicker("Quiet hours start", time: $model.quietStart)
        Text("to")
        timePicker("Quiet hours end", time: $model.quietEnd)
        Button("Apply") { Task { await model.applyQuietHours() } }
          .buttonStyle(ActionButtonStyle(style: .secondary))
          .disabled(!model.canSend || !model.quietHoursChanged)
          .accessibilityLabel("Apply quiet hours")
      }
    }
  }

  private func timePicker(_ label: String, time: Binding<String>) -> some View {
    DatePicker(
      label,
      selection: Binding(
        get: { PrincipalSettingsModel.date(fromTime: time.wrappedValue) },
        set: { time.wrappedValue = PrincipalSettingsModel.time(from: $0) }),
      displayedComponents: .hourAndMinute
    )
    .labelsHidden()
    // Every time Ian writes is 24-hour British, whatever the Mac's region.
    .environment(\.locale, Locale(identifier: "en_GB"))
  }

  private var pushBudget: some View {
    SettingRow(
      title: "Push budget",
      detail: "The most unsolicited notifications in an hour, across every surface."
    ) {
      HStack(spacing: 8) {
        Stepper(value: $model.pushBudget, in: 0...50) {
          Text("\(model.pushBudget) an hour")
        }
        .accessibilityLabel("Push budget per hour")
        .accessibilityValue("\(model.pushBudget)")
        Button("Apply") { Task { await model.applyPushBudget() } }
          .buttonStyle(ActionButtonStyle(style: .secondary))
          .disabled(!model.canSend || !model.pushBudgetChanged)
          .accessibilityLabel("Apply push budget")
      }
    }
  }

  private var ownPause: some View {
    let paused = model.settings?.paused ?? false
    return SettingRow(
      title: paused ? "Paused everywhere" : "Pause Ian everywhere",
      detail: "Ian stops acting for you on every device and in Slack. This is separate from "
        + "\"Pause me\" in the menu, which only silences this Mac."
    ) {
      HStack(spacing: 8) {
        if !paused {
          TextField("Reason (optional)", text: $model.pauseReason)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
            .accessibilityLabel("Reason for pausing")
        } else if let reason = model.settings?.pausedReason {
          Text(reason).font(.system(size: 12)).foregroundStyle(ClientPalette.secondary())
        }
        Button(paused ? "Resume" : "Pause") { Task { await model.setOwnPause(!paused) } }
          .buttonStyle(ActionButtonStyle(style: .secondary))
          .disabled(!model.canSend)
          .accessibilityLabel(paused ? "Resume Ian everywhere" : "Pause Ian everywhere")
      }
    }
  }

  private var mode: some View {
    let isLive = model.settings?.mode == .live
    return SettingRow(
      title: "Mode",
      detail: model.liveUnavailableReason
        ?? (isLive
          ? "Ian is live: approved proposals take effect."
          : "Ian is in dry run: nothing takes effect.")
    ) {
      HStack(spacing: 8) {
        Text(isLive ? "Live" : "Dry run").font(.system(size: 13, weight: .medium))
        if isLive {
          Button("Return to dry run") { Task { await model.returnToDryRun() } }
            .buttonStyle(ActionButtonStyle(style: .secondary))
            .disabled(!model.canSend)
        } else {
          Button("Go live") { model.requestLive() }
            .buttonStyle(ActionButtonStyle(style: .secondary))
            .disabled(!model.canGoLive)
        }
      }
    }
    .confirmationDialog(
      "Go live?",
      isPresented: Binding(get: { model.isConfirmingLive }, set: { if !$0 { model.cancelLive() } }),
      titleVisibility: .visible
    ) {
      Button("Go live") { Task { await model.confirmLive() } }
      Button("Stay in dry run", role: .cancel) { model.cancelLive() }
    } message: {
      Text("Approved proposals will take effect. You can return to dry run at any time.")
    }
  }

  @ViewBuilder private var readOnly: some View {
    if let settings = model.settings {
      SettingRow(title: "Time zone", detail: "Set for your account. Read-only here.") {
        Text(settings.timeZone)
      }
      SettingRow(title: "Daily cost ceiling", detail: "Set for your account. Read-only here.") {
        Text(AgentRow.money(settings.costCeilingGbp))
      }
      SettingRow(
        title: "Global state",
        detail: settings.global.pausedReason.map { "Reason: \($0)" } ?? "Set by an administrator."
      ) {
        Text(settings.global.paused ? "Paused for everyone" : "Running")
      }
    }
  }
}

private struct NoticeRow: View {
  let text: String
  let dismiss: () -> Void

  var body: some View {
    HStack {
      Text(text).font(.system(size: 13))
      Spacer()
      Button("Dismiss", action: dismiss).buttonStyle(ActionButtonStyle(style: .secondary))
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
    .accessibilityElement(children: .contain)
  }
}

// MARK: Client settings

private struct ClientSettingsSection: View {
  let store: IanStore
  let controller: SurfaceController
  let model: SettingsModel
  @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
  @Environment(\.reduceMotionReading) private var reduceMotionReading

  var body: some View {
    SettingsGroup(title: "This Mac") {
      corner
      motion
      notifications
      suppression
      launchAtLogin
      environment
      account
      diagnostics
    }
  }

  private var settings: ClientSettings { controller.settings }

  private var corner: some View {
    SettingRow(title: "Orbit corner") {
      Picker(
        "Orbit corner",
        selection: Binding(get: { controller.corner }, set: { controller.setCorner($0) })
      ) {
        ForEach(Corner.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .labelsHidden()
      .frame(width: 160)
    }
  }

  private var motion: some View {
    SettingRow(
      title: "Motion",
      detail: reduceMotionReading ?? systemReducesMotion
        ? "The system's Reduce Motion setting is on, so motion is reduced whatever you choose."
        : "The system's Reduce Motion setting always forces reduced."
    ) {
      Picker(
        "Motion",
        selection: Binding(
          get: { settings.reducedMotion }, set: { settings.setReducedMotion($0) })
      ) {
        Text("On").tag(false)
        Text("Reduced").tag(true)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
    }
  }

  private var notifications: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Notification level").font(.system(size: 14))
      ForEach(NotificationRung.allCases, id: \.self) { rung in
        SettingRow(title: rung.title, detail: rung.detail) {
          if rung.isConfigurable {
            Picker(
              "\(rung.title) notifications",
              selection: Binding(
                get: { settings.level(for: rung) }, set: { settings.setLevel($0, for: rung) })
            ) {
              ForEach(NotificationLevel.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
          } else {
            Text("Always").font(.system(size: 13))
          }
        }
      }
    }
  }

  private var suppression: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(
        "Hide item text and hold notifications while a camera is live",
        isOn: Binding(
          get: { settings.suppressOnCamera }, set: { settings.setSuppressOnCamera($0) }))
      Toggle(
        "Hide item text and hold notifications during external meetings",
        isOn: Binding(
          get: { settings.suppressInExternalMeeting },
          set: { settings.setSuppressInExternalMeeting($0) }))
      Text("Quiet hours and \"Pause me\" always do the same. P0 alerts still notify.")
        .font(.system(size: 12))
        .foregroundStyle(ClientPalette.secondary())
    }
  }

  private var launchAtLogin: some View {
    let login = model.launchAtLogin
    return VStack(alignment: .leading, spacing: 4) {
      Toggle(
        "Open Ian at login",
        isOn: Binding(get: { login.isOn }, set: { login.set(enabled: $0) }))
      Text(login.message)
        .font(.system(size: 12))
        .foregroundStyle(ClientPalette.secondary())
        .fixedSize(horizontal: false, vertical: true)
    }
    .onAppear { login.refresh() }
  }

  private var environment: some View {
    SettingRow(
      title: "Environment",
      detail: "Changing it signs you out and clears what Ian holds."
    ) {
      Picker(
        "Environment",
        selection: Binding(
          get: { store.profileID }, set: { model.requestProfile($0, in: store) })
      ) {
        ForEach(store.availableProfiles) { Text($0.displayName).tag($0.id) }
      }
      .labelsHidden()
      .frame(width: 160)
    }
    .confirmationDialog(
      "Switch environment?",
      isPresented: Binding(
        get: { model.pendingProfile != nil }, set: { if !$0 { model.cancelProfile() } }),
      titleVisibility: .visible,
      presenting: model.pendingProfile
    ) { choice in
      Button("Sign out and switch to \(choice.displayName)") {
        Task { await model.confirmProfile(choice, in: store) }
      }
      Button("Cancel", role: .cancel) { model.cancelProfile() }
    } message: { choice in
      Text(
        "Ian signs out, clears its data and syncs again from \(choice.displayName)."
      )
    }
  }

  private var account: some View {
    SettingRow(title: "Account") {
      Button("Sign out") { Task { await store.signOut() } }
        .buttonStyle(ActionButtonStyle(style: .secondary))
    }
  }

  private var diagnostics: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Diagnostics").font(.system(size: 14))
      ForEach(DiagnosticsReport.lines(for: store), id: \.label) { line in
        HStack {
          Text(line.label).foregroundStyle(ClientPalette.secondary())
          Spacer()
          Text(line.value)
        }
        .font(.system(size: 12, design: .monospaced))
        .accessibilityElement(children: .combine)
      }
      HStack {
        Button("Copy report") { model.copyReport(from: store) }
          .buttonStyle(ActionButtonStyle(style: .secondary))
        if model.didCopyReport {
          Text("Copied. The report holds ids, versions and timings only.")
            .font(.system(size: 12))
            .foregroundStyle(ClientPalette.secondary())
        }
      }
    }
  }
}

extension Corner {
  fileprivate var title: String {
    switch self {
    case .topLeft: "Top left"
    case .topRight: "Top right"
    case .bottomLeft: "Bottom left"
    case .bottomRight: "Bottom right"
    }
  }
}

extension NotificationRung {
  fileprivate var title: String {
    switch self {
    case .ambient: "Ambient"
    case .needsYou: "Needs you"
    case .urgent: "Urgent"
    case .stop: "Stop"
    }
  }

  fileprivate var detail: String {
    switch self {
    case .ambient: "Agent runs and P3 items."
    case .needsYou: "Pending proposals, commitments due today and P2 items."
    case .urgent: "P1 items, risk language and proposals expiring within 15 minutes."
    case .stop: "P0 items, the kill switch, the budget ceiling and a foreign decision attempt."
    }
  }
}

extension NotificationLevel {
  fileprivate var title: String {
    switch self {
    case .off: "Off"
    case .banner: "Banner"
    }
  }
}

extension EnvironmentValues {
  /// The app reads the system's Reduce Motion and leaves this nil. A snapshot sets it, so a
  /// machine's accessibility settings cannot change what the Motion row draws.
  @Entry var reduceMotionReading: Bool?
}

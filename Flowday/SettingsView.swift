import SwiftUI

struct SettingsView: View {
  @Bindable var store: TaskStore
  @Bindable var reminders: ReminderService
  @State private var requestingPermission = false

  var body: some View {
    Form {
      Section("外观") {
        Picker(
          "主题",
          selection: Binding(
            get: { store.settings.theme },
            set: { value in
              store.updateSettings { $0.theme = value }
            })
        ) {
          ForEach(AppTheme.allCases) { theme in Text(theme.label).tag(theme) }
        }.pickerStyle(.segmented).accessibilityIdentifier("theme-picker")
      }
      Section("截止提醒") {
        Picker(
          "提前提醒",
          selection: Binding(
            get: { store.settings.reminderHours },
            set: { value in
              store.updateSettings { $0.reminderHours = value }
            })
        ) {
          ForEach([2, 24, 48], id: \.self) { Text("\($0) 小时").tag($0) }
        }.accessibilityIdentifier("reminder-hours")
        Toggle(
          "系统通知", isOn: Binding(get: { store.settings.notificationsEnabled }, set: setNotifications)
        )
        .disabled(requestingPermission || store.readOnly).accessibilityIdentifier(
          "notifications-toggle")
        LabeledContent("通知权限", value: reminders.status)
        if let error = reminders.errorMessage {
          Text(error).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled)
        }
        Text("开启后，Flowday 会将截止提醒安排到 macOS 通知中心。通知显示受系统权限与专注模式影响。")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Section("桌面小组件") {
        LabeledContent("任务同步", value: store.widgetSyncStatus)
        Text("右键点击桌面，选择「编辑小组件」，搜索「Flowday」，添加今日待办、每日任务或完成日历。")
          .font(.system(size: 11)).foregroundStyle(.secondary)
        Text("小组件展示同步后的任务；点击可打开 Flowday。刷新时机由 macOS 调度。")
          .font(.system(size: 11)).foregroundStyle(.secondary)
        Button("重新同步小组件") { store.synchronizeWidget() }.disabled(store.readOnly)
          .accessibilityIdentifier("sync-widgets")
        if let error = store.widgetSyncError {
          Text(error).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
        }
      }
      Section("数据") {
        HStack(spacing: 14) {
          Button("导入任务…") { store.chooseImport() }.disabled(store.readOnly)
            .accessibilityIdentifier("import-tasks")
          Button("导出备份…") { store.exportBackup() }.accessibilityIdentifier("export-backup")
          Spacer()
        }
        Button("在 Finder 中显示数据") { store.revealData() }
        Text("任务保存在这台 Mac 上。导入支持旧版任务 JSON 和 Flowday 备份；同标识任务会跳过。")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Section {
        HStack {
          Text("Flowday").fontWeight(.medium)
          Spacer()
          Text("原生 macOS 版").foregroundStyle(.secondary)
        }.font(.system(size: 12))
      }
    }
    .formStyle(.grouped)
    .frame(width: 510, height: 590)
    .task { await reminders.refresh() }
    .alert(
      "操作未完成",
      isPresented: Binding(
        get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    ) {
      Button("知道了", role: .cancel) { store.errorMessage = nil }
    } message: {
      Text(store.errorMessage ?? "")
    }
    .overlay(alignment: .bottom) {
      if let notice = store.notice {
        Text(notice).font(.system(size: 11)).padding(12)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9)).padding(15)
      }
    }
  }

  private func setNotifications(_ enabled: Bool) {
    if !enabled {
      store.updateSettings { $0.notificationsEnabled = false }
      Task {
        await reminders.synchronize(tasks: store.tasks, settings: store.settings, now: store.now)
      }
      return
    }
    requestingPermission = true
    reminders.errorMessage = nil
    Task {
      let allowed = await reminders.requestPermission()
      store.updateSettings { $0.notificationsEnabled = allowed }
      await reminders.synchronize(tasks: store.tasks, settings: store.settings, now: store.now)
      requestingPermission = false
    }
  }
}

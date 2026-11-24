import SwiftUI

enum LaunchConfiguration {
  static let arguments = ProcessInfo.processInfo.arguments
  static let isTesting =
    arguments.contains("--ui-testing")
    || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil

  static func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  static var dataURL: URL {
    if let directory = value(after: "--data-directory") {
      return URL(fileURLWithPath: directory, isDirectory: true).appending(path: "tasks.json")
    }
    if isTesting {
      return FileManager.default.temporaryDirectory.appending(
        path: "FlowdayTestHost-\(ProcessInfo.processInfo.processIdentifier)/tasks.json")
    }
    return TaskPersistence.defaultURL
  }
}

@main
struct FlowdayApp: App {
  @State private var store: TaskStore
  @State private var reminders = ReminderService(disabled: LaunchConfiguration.isTesting)

  init() {
    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: iconURL)
    {
      NSApplication.shared.applicationIconImage = icon
    }
    let store = TaskStore(url: LaunchConfiguration.dataURL)
    if LaunchConfiguration.arguments.contains("--sample-data"), LaunchConfiguration.isTesting,
      store.tasks.isEmpty
    {
      if let data = try? TaskPersistence.encoded(TaskDocument(tasks: PreviewData.tasks())) {
        store.importTasks(data)
      }
      store.notice = nil
    }
    if let path = LaunchConfiguration.value(after: "--import-tasks") {
      do { store.importTasks(try Data(contentsOf: URL(fileURLWithPath: path))) } catch {
        store.errorMessage = "无法打开导入文件：" + error.localizedDescription
      }
    }
    _store = State(initialValue: store)
  }

  var body: some Scene {
    WindowGroup("Flowday", id: "main") {
      ContentView(store: store, reminders: reminders)
        .preferredColorScheme(store.settings.theme.scheme)
        .tint(FlowdayStyle.accent)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .frame(minWidth: 860, minHeight: 640)
        .onOpenURL { url in
          guard store.openWidgetURL(url) else { return }
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }
    .defaultSize(width: 1220, height: 760)
    .windowToolbarStyle(.unified)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("新建任务") { store.newTask(completed: store.selectedView == .completed) }
          .keyboardShortcut("n")
        Button("记录今日完成项") { store.newTask(completed: true) }
          .keyboardShortcut("n", modifiers: [.command, .shift])
        Divider()
        Button("导入任务…") { store.chooseImport() }
        Button("导出备份…") { store.exportBackup() }.keyboardShortcut(
          "e", modifiers: [.command, .shift])
      }
      CommandMenu("清单") {
        ForEach(Array(TaskView.allCases.enumerated()), id: \.element.id) { index, view in
          Button(view.title) { store.selectedView = view }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        }
        Divider()
        Button("搜索任务") {
          store.searchFocusToken = UUID()
        }.keyboardShortcut("k")
        Button("清除筛选") { store.filter = TaskFilter() }
      }
    }

    Settings {
      SettingsView(store: store, reminders: reminders)
        .preferredColorScheme(store.settings.theme.scheme)
        .tint(FlowdayStyle.accent)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }
  }
}

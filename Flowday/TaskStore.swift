import AppKit
import Observation
import UniformTypeIdentifiers
import WidgetKit

@MainActor @Observable
final class TaskStore {
  private(set) var document = TaskDocument()
  private(set) var readOnly = false
  let persistence: TaskPersistence
  var selectedView: TaskView = .today
  var filter = TaskFilter()
  var editor: EditorDraft?
  var errorMessage: String?
  var notice: String?
  var now = Date()
  var searchFocusToken = UUID()
  private(set) var widgetNavigationToken = UUID()
  private(set) var widgetSyncStatus = "尚未同步"
  private(set) var widgetSyncError: String?

  var tasks: [TaskItem] { document.tasks }
  var settings: AppSettings { document.settings }
  var visibleTasks: [TaskItem] {
    TaskLogic.sorted(
      TaskLogic.filtered(
        tasks, view: selectedView, filter: filter,
        hours: settings.reminderHours, now: now), by: settings.sort)
  }
  var reminders: [TaskItem] {
    TaskLogic.sorted(
      tasks.filter { $0.isReminder(at: now, hours: settings.reminderHours) }, by: .dueDate)
  }
  var completedToday: [TaskItem] {
    tasks.filter {
      $0.completed && $0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: now) } == true
    }
  }
  var allTags: [(name: String, count: Int)] {
    let counts = tasks.flatMap(\.tagList).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
    return counts.map { (name: $0.key, count: $0.value) }.sorted {
      $0.count == $1.count
        ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.count > $1.count
    }
  }

  init(url: URL = TaskPersistence.defaultURL) {
    persistence = TaskPersistence(url: url)
    do { document = try persistence.load() } catch {
      readOnly = true
      errorMessage = "无法读取本地数据，已保留原文件并暂停写入。\n" + error.localizedDescription
    }
    synchronizeWidget()
  }

  func synchronizeWidget() {
    // Test stores must never publish sample data into the user's desktop widgets.
    guard persistence.url == TaskPersistence.defaultURL, !LaunchConfiguration.isTesting else {
      return
    }
    guard !readOnly else {
      widgetSyncError = "本地数据读取失败，小组件保留上次同步内容。"
      return
    }
    do {
      try WidgetSharedStore.publish(
        WidgetSnapshot(generatedAt: now, tasks: tasks, reminderHours: settings.reminderHours))
      widgetSyncStatus = "已同步"
      widgetSyncError = nil
      WidgetCenter.shared.reloadTimelines(ofKind: "DaylightTasks")
      WidgetCenter.shared.reloadTimelines(ofKind: "DaylightCompletionCalendar")
      WidgetCenter.shared.reloadTimelines(ofKind: "DaylightDailyTasks")
    } catch {
      widgetSyncStatus = "同步未完成"
      widgetSyncError = error.localizedDescription
    }
  }

  @discardableResult
  func openWidgetURL(_ url: URL) -> Bool {
    guard let destination = WidgetDestination.destination(for: url) else { return false }
    filter = TaskFilter()
    now = Date()
    widgetNavigationToken = UUID()
    switch destination {
    case .today:
      selectedView = .today
    case .completed:
      selectedView = .completed
    case .newTask:
      selectedView = .today
      newTask()
    }
    return true
  }

  func count(for view: TaskView) -> Int {
    TaskLogic.filtered(tasks, view: view, hours: settings.reminderHours, now: now)
      .filter { view == .completed ? $0.completed : !$0.completed }.count
  }

  @discardableResult
  private func commit(_ change: (inout TaskDocument) -> Void) -> Bool {
    guard !readOnly else {
      errorMessage = "当前数据文件无法读取。请先在 Finder 中备份并检查原文件，重启后再试。"
      return false
    }
    var next = document
    change(&next)
    do {
      try persistence.save(next)
      document = next
      synchronizeWidget()
      if let tag = filter.tag, !allTags.contains(where: { $0.name == tag }) { filter.tag = nil }
      return true
    } catch {
      errorMessage = "保存失败，本次修改尚未生效。\n" + error.localizedDescription
      return false
    }
  }

  func newTask(completed: Bool = false) {
    let time = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
    editor = EditorDraft(
      task: TaskItem(
        title: "", category: filter.category ?? .work,
        dueDate: TaskDates.day(now), dueTime: TaskDates.time(time),
        completed: completed), isNew: true)
  }

  func edit(_ task: TaskItem) { editor = EditorDraft(task: task, isNew: false) }

  @discardableResult
  func saveTask(_ input: TaskItem) -> Bool {
    var task = input
    task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
    task.note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines)
    if task.note?.isEmpty == true { task.note = nil }
    task.tags = TaskLogic.tags(from: task.tagList.joined(separator: ","))
    if task.dueDate == nil { task.dueTime = nil }
    let old = tasks.first { $0.id == task.id }
    if task.completed {
      task.completedAt = old?.completed == true ? old?.completedAt ?? now : now
    } else {
      task.completedAt = nil
    }
    if old?.dueDate != task.dueDate || old?.dueTime != task.dueTime || task.completed {
      task.snoozedUntil = nil
    }
    return commit { document in
      if let index = document.tasks.firstIndex(where: { $0.id == task.id }) {
        document.tasks[index] = task
      } else {
        task.order = (document.tasks.compactMap(\.order).min() ?? 0) - 1
        document.tasks.insert(task, at: 0)
      }
    }
  }

  func toggle(_ id: String) {
    commit { document in
      guard let i = document.tasks.firstIndex(where: { $0.id == id }) else { return }
      document.tasks[i].completed.toggle()
      document.tasks[i].completedAt = document.tasks[i].completed ? now : nil
      document.tasks[i].snoozedUntil = nil
    }
  }

  func delete(_ id: String) { commit { $0.tasks.removeAll { $0.id == id } } }

  func snooze(_ id: String) {
    commit { document in
      guard let i = document.tasks.firstIndex(where: { $0.id == id && !$0.completed }) else {
        return
      }
      document.tasks[i].snoozedUntil = now.addingTimeInterval(3600)
    }
    notice = "已延后 1 小时提醒"
  }

  @discardableResult
  func reorder(_ sourceID: String, before targetID: String, after: Bool = false) -> Bool {
    guard sourceID != targetID else { return false }
    var pending = TaskLogic.sorted(tasks.filter { !$0.completed }, by: settings.sort)
    guard let source = pending.firstIndex(where: { $0.id == sourceID }),
      pending.contains(where: { $0.id == targetID })
    else { return false }
    let moved = pending.remove(at: source)
    guard let target = pending.firstIndex(where: { $0.id == targetID }) else { return false }
    pending.insert(moved, at: target + (after ? 1 : 0))
    let orders = Dictionary(uniqueKeysWithValues: pending.enumerated().map { ($1.id, $0) })
    return commit { document in
      for i in document.tasks.indices {
        if let order = orders[document.tasks[i].id] { document.tasks[i].order = order }
      }
      document.settings.sort = .manual
    }
  }

  func updateSettings(_ change: (inout AppSettings) -> Void) { commit { change(&$0.settings) } }

  @discardableResult
  func importTasks(_ data: Data) -> Bool {
    do {
      let imported = try TaskPersistence.importedTasks(from: data)
      let known = Set(tasks.map(\.id))
      let additions = imported.filter { !known.contains($0.id) }
      if commit({ $0.tasks.append(contentsOf: additions) }) {
        notice = "已导入 \(additions.count) 项任务，跳过 \(imported.count - additions.count) 项重复记录"
        return true
      }
    } catch { errorMessage = "导入失败，现有任务未被修改。\n" + error.localizedDescription }
    return false
  }

  func chooseImport() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.message = "导入 Flowday 备份或旧版任务 JSON；同标识任务会跳过，现有任务会保留。"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { importTasks(try Data(contentsOf: url)) } catch {
      errorMessage = "无法打开所选文件。\n" + error.localizedDescription
    }
  }

  func exportBackup() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Flowday-\(TaskDates.day(now)).json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try TaskPersistence.encoded(document).write(to: url, options: .atomic)
      notice = "备份已导出"
    } catch { errorMessage = "导出失败。\n" + error.localizedDescription }
  }

  func revealData() {
    if FileManager.default.fileExists(atPath: persistence.url.path) {
      NSWorkspace.shared.activateFileViewerSelecting([persistence.url])
    } else {
      NSWorkspace.shared.open(
        persistence.url.deletingLastPathComponent().deletingLastPathComponent())
    }
  }
}

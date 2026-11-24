import Foundation

struct WidgetSnapshot: Codable, Equatable {
  var version = 1
  var generatedAt: Date
  var tasks: [TaskItem]
  var reminderHours: Int

  static let empty = WidgetSnapshot(generatedAt: .distantPast, tasks: [], reminderHours: 24)
}

enum WidgetSharedStore {
  static var groupIdentifier: String {
    Bundle.main.object(forInfoDictionaryKey: "DaylightAppGroup") as? String
      ?? "group.local.daylight.native"
  }

  private static func snapshotURL() throws -> URL {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: groupIdentifier)
    else {
      throw DataError.invalid("小组件共享空间不可用，请检查主应用与小组件的 App Groups 和签名团队。")
    }
    return container.appendingPathComponent("widget-snapshot.json")
  }

  static func load() throws -> WidgetSnapshot {
    try read(from: snapshotURL())
  }

  static func publish(_ snapshot: WidgetSnapshot) throws {
    try write(snapshot, to: snapshotURL())
  }

  static func read(from url: URL) throws -> WidgetSnapshot {
    let snapshot = try TaskPersistence.decoder().decode(
      WidgetSnapshot.self, from: Data(contentsOf: url))
    try validate(snapshot)
    return snapshot
  }

  static func write(_ snapshot: WidgetSnapshot, to url: URL) throws {
    try validate(snapshot)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(snapshot)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  private static func validate(_ snapshot: WidgetSnapshot) throws {
    guard snapshot.version == 1 else { throw DataError.invalid("此小组件数据版本暂不支持。") }
    var settings = AppSettings()
    settings.reminderHours = snapshot.reminderHours
    try TaskPersistence.validate(TaskDocument(tasks: snapshot.tasks, settings: settings))
  }
}

enum WidgetDestination: Equatable {
  case today, completed, newTask

  static func destination(for url: URL) -> Self? {
    guard url.scheme?.lowercased() == "daylight", url.path.isEmpty,
      url.query == nil, url.fragment == nil, url.user == nil, url.password == nil, url.port == nil
    else { return nil }
    switch url.host?.lowercased() {
    case "today": return .today
    case "completed": return .completed
    case "new-task": return .newTask
    default: return nil
    }
  }
}

struct DailyWidgetSummary {
  let pendingTasks: [TaskItem]
  let completedTasks: [TaskItem]

  init(snapshot: WidgetSnapshot, now: Date, calendar: Calendar = .current) {
    let tasks = TaskLogic.sorted(
      TaskLogic.filtered(
        snapshot.tasks, view: .today, hours: snapshot.reminderHours, now: now, calendar: calendar),
      by: .dueDate, calendar: calendar)
    pendingTasks = tasks.filter { !$0.completed }
    completedTasks = tasks.filter(\.completed)
  }

  var pendingCount: Int { pendingTasks.count }
  var completedCount: Int { completedTasks.count }
  var totalCount: Int { pendingCount + completedCount }
  var progress: Double { totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount) }
  var displayedTasks: [TaskItem] { Array((pendingTasks + completedTasks).prefix(4)) }
  var remainingCount: Int { totalCount - displayedTasks.count }
}

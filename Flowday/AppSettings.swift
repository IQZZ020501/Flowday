import Foundation

enum AppTheme: String, Codable, CaseIterable, Identifiable {
  case system, light, dark
  var id: Self { self }
  var label: String { self == .system ? "跟随系统" : self == .light ? "浅色" : "深色" }
}

struct AppSettings: Codable, Equatable {
  var theme: AppTheme = .system
  var sort: TaskSort = .dueDate
  var reminderHours = 24
  var notificationsEnabled = false

  init() {}

  /// Missing or unknown preferences fall back to defaults instead of making the file unreadable.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    theme = (try? c.decodeIfPresent(AppTheme.self, forKey: .theme)) ?? .system
    sort = (try? c.decodeIfPresent(TaskSort.self, forKey: .sort)) ?? .dueDate
    reminderHours = try c.decodeIfPresent(Int.self, forKey: .reminderHours) ?? 24
    notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
  }
}

struct TaskDocument: Codable, Equatable {
  var version = 1
  var tasks: [TaskItem] = []
  var settings = AppSettings()

  init(version: Int = 1, tasks: [TaskItem] = [], settings: AppSettings = AppSettings()) {
    self.version = version
    self.tasks = tasks
    self.settings = settings
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
    settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
  }
}

struct EditorDraft: Identifiable {
  let id = UUID()
  var task: TaskItem
  var isNew: Bool
}

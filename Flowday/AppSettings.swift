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
}

struct TaskDocument: Codable, Equatable {
  var version = 1
  var tasks: [TaskItem] = []
  var settings = AppSettings()
}

struct EditorDraft: Identifiable {
  let id = UUID()
  var task: TaskItem
  var isNew: Bool
}

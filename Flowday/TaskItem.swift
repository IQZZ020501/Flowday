import Foundation

enum Priority: String, Codable, CaseIterable, Identifiable {
  case high, medium, low
  var id: Self { self }
  var label: String { self == .high ? "高优先" : self == .medium ? "中优先" : "低优先" }
  var rank: Int { self == .high ? 3 : self == .medium ? 2 : 1 }
}

enum TaskCategory: String, Codable, CaseIterable, Identifiable {
  case work = "工作"
  case personal = "个人"
  case study = "学习"
  case life = "生活"
  var id: Self { self }
  var symbol: String {
    switch self {
    case .work: "briefcase"
    case .personal: "person"
    case .study: "book"
    case .life: "leaf"
    }
  }
}

enum TaskSort: String, Codable, CaseIterable, Identifiable {
  case dueDate, priority, createdAt, manual
  var id: Self { self }
  var label: String {
    switch self {
    case .dueDate: "截止日期"
    case .priority: "优先级"
    case .createdAt: "创建时间"
    case .manual: "自定义顺序"
    }
  }
}

enum TaskView: String, CaseIterable, Identifiable {
  case today, reminders, all, completed
  var id: Self { self }
  var title: String {
    switch self {
    case .today: "今日聚焦"
    case .reminders: "临近提醒"
    case .all: "全部清单"
    case .completed: "已完成归档"
    }
  }
  var symbol: String {
    switch self {
    case .today: "calendar"
    case .reminders: "bell.badge"
    case .all: "tray"
    case .completed: "checkmark.circle"
    }
  }
}

enum DeadlineUrgency { case overdue, soon, upcoming, none, completed }

struct TaskItem: Codable, Identifiable, Equatable {
  var id = UUID().uuidString
  var title: String
  var note: String?
  var priority: Priority = .medium
  var category: TaskCategory = .work
  var dueDate: String?
  var dueTime: String?
  var completed = false
  var createdAt = Date()
  var completedAt: Date?
  var snoozedUntil: Date?
  var order: Int?
  var tags: [String]?

  var tagList: [String] { tags ?? [] }

  func deadline(calendar: Calendar = .current) -> Date? {
    guard let dueDate, let day = TaskDates.date(dueDate, calendar: calendar) else { return nil }
    let time = dueTime?.split(separator: ":").compactMap { Int($0) }
    let hour = time?.first ?? 23
    let minute = time?.last ?? 59
    return calendar.date(
      bySettingHour: hour, minute: minute, second: dueTime == nil ? 59 : 0, of: day)
  }

  func urgency(at now: Date, hours: Int, calendar: Calendar = .current) -> DeadlineUrgency {
    if completed { return .completed }
    guard let due = deadline(calendar: calendar) else { return .none }
    if due < now { return .overdue }
    return due.timeIntervalSince(now) <= Double(hours) * 3600 ? .soon : .upcoming
  }

  func isReminder(at now: Date, hours: Int, calendar: Calendar = .current) -> Bool {
    if let snoozedUntil, snoozedUntil > now { return false }
    let urgency = urgency(at: now, hours: hours, calendar: calendar)
    return urgency == .overdue || urgency == .soon
  }
}

enum TaskDates {
  static func day(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  static func time(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
  }

  static func date(_ text: String, calendar: Calendar = .current) -> Date? {
    let fields = text.split(separator: "-").compactMap { Int($0) }
    guard fields.count == 3, text.count == 10,
      let result = calendar.date(
        from: DateComponents(year: fields[0], month: fields[1], day: fields[2])),
      day(result, calendar: calendar) == text
    else { return nil }
    return result
  }

  static func heading(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "M月d日 EEEE"
    let prefix = calendar.isDate(date, inSameDayAs: now) ? "今天 · " : ""
    return prefix + formatter.string(from: date)
  }

  static func dueLabel(_ task: TaskItem, now: Date, calendar: Calendar = .current) -> String {
    guard let due = task.deadline(calendar: calendar), let day = task.dueDate else {
      return "无截止日期"
    }
    let minutes = Int(ceil(due.timeIntervalSince(now) / 60))
    if !task.completed && due < now {
      let elapsed = max(1, Int(ceil(now.timeIntervalSince(due) / 60)))
      if elapsed < 60 { return "已逾期 \(elapsed) 分钟" }
      if elapsed < 1440 { return "已逾期 \(elapsed / 60) 小时" }
      return "已逾期 \(elapsed / 1440) 天"
    }
    if !task.completed && minutes <= 60 { return "\(max(1, minutes)) 分钟后截止" }
    let suffix = task.dueTime.map { " " + $0 } ?? ""
    if day == self.day(now, calendar: calendar) { return "今天" + suffix }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
      day == self.day(tomorrow, calendar: calendar)
    {
      return "明天" + suffix
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "M月d日"
    return formatter.string(from: due) + suffix
  }
}

struct TaskFilter {
  var category: TaskCategory?
  var priority: Priority?
  var tag: String?
  var search = ""
  var isActive: Bool { category != nil || priority != nil || tag != nil || !search.isEmpty }
}

enum TaskLogic {
  static func tags(from text: String) -> [String] {
    let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，、;；"))
    var seen = Set<String>()
    return text.components(separatedBy: separators).compactMap { value in
      let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        .drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespacesAndNewlines)
      return !tag.isEmpty && seen.insert(tag).inserted ? tag : nil
    }
  }

  static func sorted(_ tasks: [TaskItem], by mode: TaskSort, calendar: Calendar = .current)
    -> [TaskItem]
  {
    tasks.sorted { a, b in
      if a.completed != b.completed { return !a.completed }
      if a.completed {
        let ad = a.completedAt ?? .distantPast
        let bd = b.completedAt ?? .distantPast
        return ad == bd ? a.id < b.id : ad > bd
      }
      let ad = a.deadline(calendar: calendar) ?? .distantFuture
      let bd = b.deadline(calendar: calendar) ?? .distantFuture
      if mode == .manual, (a.order ?? .max) != (b.order ?? .max) {
        return (a.order ?? .max) < (b.order ?? .max)
      }
      if mode == .priority, a.priority.rank != b.priority.rank {
        return a.priority.rank > b.priority.rank
      }
      if mode != .createdAt, ad != bd { return ad < bd }
      if mode == .dueDate, a.priority.rank != b.priority.rank {
        return a.priority.rank > b.priority.rank
      }
      return a.createdAt == b.createdAt ? a.id < b.id : a.createdAt > b.createdAt
    }
  }

  static func filtered(
    _ tasks: [TaskItem], view: TaskView, filter: TaskFilter = TaskFilter(),
    hours: Int = 24, now: Date = Date(), calendar: Calendar = .current
  ) -> [TaskItem] {
    let today = TaskDates.day(now, calendar: calendar)
    let query = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
    return tasks.filter { task in
      if let category = filter.category, task.category != category { return false }
      if let priority = filter.priority, task.priority != priority { return false }
      if let tag = filter.tag, !task.tagList.contains(tag) { return false }
      if !query.isEmpty {
        let text = ([task.title, task.note ?? "", task.category.rawValue] + task.tagList).joined(
          separator: " ")
        if !text.localizedStandardContains(query) { return false }
      }
      switch view {
      case .today:
        if task.completed {
          return task.completedAt.map { TaskDates.day($0, calendar: calendar) == today } ?? false
        }
        let urgency = task.urgency(at: now, hours: hours, calendar: calendar)
        return urgency == .overdue || urgency == .soon || task.dueDate == nil
          || task.dueDate == today
      case .reminders: return task.isReminder(at: now, hours: hours, calendar: calendar)
      case .completed: return task.completed
      case .all: return true
      }
    }
  }

  static func completionCounts(_ tasks: [TaskItem], calendar: Calendar = .current) -> [String: Int]
  {
    tasks.reduce(into: [:]) { counts, task in
      if task.completed, let date = task.completedAt {
        counts[TaskDates.day(date, calendar: calendar), default: 0] += 1
      }
    }
  }

  static func streak(_ tasks: [TaskItem], now: Date = Date(), calendar: Calendar = .current) -> Int
  {
    let counts = completionCounts(tasks, calendar: calendar)
    var cursor = calendar.startOfDay(for: now)
    var result = 0
    if counts[TaskDates.day(cursor, calendar: calendar)] == nil {
      cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
    }
    while counts[TaskDates.day(cursor, calendar: calendar)] != nil {
      result += 1
      guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
      cursor = previous
    }
    return result
  }
}

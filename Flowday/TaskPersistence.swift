import Foundation

enum DataError: LocalizedError {
  case invalid(String)
  var errorDescription: String? {
    switch self {
    case .invalid(let message): message
    }
  }
}

struct TaskPersistence {
  let url: URL

  static var defaultURL: URL {
    URL.applicationSupportDirectory.appending(path: "DaylightNative", directoryHint: .isDirectory)
      .appending(path: "tasks.json")
  }

  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { input in
      let text = try input.singleValueContainer().decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: text) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      guard let date = formatter.date(from: text) else {
        throw DataError.invalid("日期格式无效：需要 ISO 8601 时间。")
      }
      return date
    }
    return decoder
  }

  static func encoded(_ document: TaskDocument) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(document)
  }

  func load() throws -> TaskDocument {
    guard FileManager.default.fileExists(atPath: url.path) else { return TaskDocument() }
    let document = try Self.decoder().decode(TaskDocument.self, from: Data(contentsOf: url))
    try Self.validate(document)
    return document
  }

  func save(_ document: TaskDocument) throws {
    try Self.validate(document)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Self.encoded(document).write(to: url, options: .atomic)
  }

  static func importedTasks(from data: Data) throws -> [TaskItem] {
    let object = try JSONSerialization.jsonObject(with: data)
    let tasks: [TaskItem]
    if object is [Any] {
      tasks = try decoder().decode([TaskItem].self, from: data)
    } else if let dictionary = object as? [String: Any],
      let rawTasks = dictionary["tasks"] as? [Any]
    {
      if let version = dictionary["version"] as? Int, version != 1 {
        throw DataError.invalid("此备份的版本暂不支持。")
      }
      tasks = try decoder().decode(
        [TaskItem].self, from: JSONSerialization.data(withJSONObject: rawTasks))
    } else {
      throw DataError.invalid("请选择 Flowday JSON 备份或旧版任务数组。")
    }
    try validate(TaskDocument(tasks: tasks))
    return tasks
  }

  static func validate(_ document: TaskDocument) throws {
    guard document.version == 1 else { throw DataError.invalid("数据文件版本暂不支持，原文件未被修改。") }
    var ids = Set<String>()
    for task in document.tasks {
      guard !task.id.isEmpty, ids.insert(task.id).inserted else {
        throw DataError.invalid("任务标识为空或重复。")
      }
      guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DataError.invalid("任务标题不能为空。")
      }
      if let date = task.dueDate, TaskDates.date(date) == nil {
        throw DataError.invalid("任务截止日期无效。")
      }
      if let time = task.dueTime {
        let fields = time.split(separator: ":").compactMap { Int($0) }
        guard task.dueDate != nil, time.count == 5, fields.count == 2,
          (0...23).contains(fields[0]), (0...59).contains(fields[1])
        else {
          throw DataError.invalid("任务截止时间无效。")
        }
      }
    }
    guard [2, 24, 48].contains(document.settings.reminderHours) else {
      throw DataError.invalid("提醒范围必须为 2、24 或 48 小时。")
    }
  }
}

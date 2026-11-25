import XCTest

@testable import Flowday

final class FlowdayTests: XCTestCase {
  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return value
  }

  private var now: Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))!
  }

  private func temporaryURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FlowdayTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory.appendingPathComponent("tasks.json")
  }

  @MainActor
  private func freeze(_ store: TaskStore, at date: Date) {
    store.clock = { date }
    store.now = date
  }

  private func task(
    _ id: String, dueDate: String? = nil, dueTime: String? = nil,
    priority: Priority = .medium, completed: Bool = false, completedAt: Date? = nil
  ) -> TaskItem {
    TaskItem(
      id: id, title: id, priority: priority, dueDate: dueDate, dueTime: dueTime,
      completed: completed, createdAt: now, completedAt: completedAt)
  }

  func testWidgetBundleMetadataUsesFlowdayBrandingAndCurrentAppIcon() throws {
    let app = Bundle.main
    let plugins = try XCTUnwrap(app.builtInPlugInsURL)
    let widget = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("FlowdayWidgets.appex")))
    for bundle in [app, widget] {
      XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, "Flowday")
      XCTAssertEqual(
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Flowday")
      XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String, "AppIcon")
    }
    let appIcon = try XCTUnwrap(app.url(forResource: "AppIcon", withExtension: "icns"))
    let widgetIcon = try XCTUnwrap(widget.url(forResource: "AppIcon", withExtension: "icns"))
    XCTAssertEqual(try Data(contentsOf: appIcon), try Data(contentsOf: widgetIcon))
    XCTAssertEqual(
      app.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      widget.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
  }

  @MainActor
  func testCreateEditCompleteRestoreDeleteAndReload() async throws {
    let url = try temporaryURL()
    let store = TaskStore(url: url)
    freeze(store, at: now)
    XCTAssertTrue(store.tasks.isEmpty)
    var item = task("one", dueDate: "2026-11-24", dueTime: "18:00")
    item.title = "  整理笔记  "
    item.note = "   "
    item.tags = ["#学习", "学习", "Swift"]
    XCTAssertTrue(store.saveTask(item))
    XCTAssertEqual(store.tasks[0].title, "整理笔记")
    XCTAssertNil(store.tasks[0].note)
    XCTAssertEqual(store.tasks[0].tags, ["学习", "Swift"])

    item = store.tasks[0]
    item.title = "整理 Swift 笔记"
    item.category = .study
    XCTAssertTrue(store.saveTask(item))
    XCTAssertEqual(store.tasks.count, 1)
    store.toggle(item.id)
    XCTAssertTrue(store.tasks[0].completed)
    XCTAssertEqual(store.tasks[0].completedAt, now)
    XCTAssertEqual(store.completedToday.count, 1)
    XCTAssertEqual(TaskStore(url: url).tasks, store.tasks)

    store.toggle(item.id)
    XCTAssertFalse(store.tasks[0].completed)
    XCTAssertNil(store.tasks[0].completedAt)
    store.delete(item.id)
    XCTAssertTrue(store.tasks.isEmpty)
    XCTAssertTrue(
      TaskStore(url: url).tasks.isEmpty, "An explicitly empty list must remain empty after restart."
    )
  }

  @MainActor
  func testEditingCompletedTaskPreservesCompletionTimestamp() async throws {
    let store = TaskStore(url: try temporaryURL())
    freeze(store, at: now)
    XCTAssertTrue(store.saveTask(task("done", completed: true)))
    var edited = store.tasks[0]
    freeze(store, at: now.addingTimeInterval(3600))
    edited.title = "补充记录"
    XCTAssertTrue(store.saveTask(edited))
    XCTAssertEqual(store.tasks[0].completedAt, now)
  }

  @MainActor
  func testSnoozeHidesReminderUntilExpiryAndCompletionClearsSnooze() async throws {
    let store = TaskStore(url: try temporaryURL())
    freeze(store, at: Date(timeIntervalSince1970: 1_800_000_000))
    let due = store.now.addingTimeInterval(-3600)
    let item = task("overdue", dueDate: TaskDates.day(due), dueTime: TaskDates.time(due))
    XCTAssertTrue(store.saveTask(item))
    XCTAssertEqual(store.reminders.count, 1)
    store.snooze(item.id)
    XCTAssertEqual(store.tasks[0].snoozedUntil, store.now.addingTimeInterval(3600))
    XCTAssertTrue(store.reminders.isEmpty)
    store.selectedView = .reminders
    XCTAssertTrue(store.visibleTasks.isEmpty)
    XCTAssertEqual(store.count(for: .reminders), 0)
    store.now = store.now.addingTimeInterval(3601)
    XCTAssertEqual(store.reminders.count, 1)
    store.toggle(item.id)
    XCTAssertNil(store.tasks[0].snoozedUntil)
    XCTAssertTrue(store.reminders.isEmpty)
  }

  @MainActor
  func testManualReorderIncludesHiddenItemsAndPersists() async throws {
    let url = try temporaryURL()
    let store = TaskStore(url: url)
    for (id, day) in [("a", "2026-11-24"), ("b", "2026-11-25"), ("c", "2026-11-26")] {
      XCTAssertTrue(store.saveTask(task(id, dueDate: day)))
    }
    store.filter.search = "c"
    XCTAssertTrue(store.reorder("c", before: "a"))
    XCTAssertEqual(store.settings.sort, .manual)
    XCTAssertEqual(TaskLogic.sorted(store.tasks, by: .manual).map(\.id), ["c", "a", "b"])
    XCTAssertTrue(store.reorder("c", before: "b", after: true))
    XCTAssertEqual(TaskLogic.sorted(store.tasks, by: .manual).map(\.id), ["a", "b", "c"])
    XCTAssertEqual(
      TaskLogic.sorted(TaskStore(url: url).tasks, by: .manual).map(\.id), ["a", "b", "c"])
    XCTAssertFalse(store.reorder("missing", before: "b"))
    XCTAssertFalse(store.reorder("a", before: "a"))
  }

  @MainActor
  func testReorderDoesNotMoveCompletedTasks() async throws {
    let store = TaskStore(url: try temporaryURL())
    XCTAssertTrue(store.saveTask(task("pending")))
    XCTAssertTrue(store.saveTask(task("done", completed: true)))
    XCTAssertFalse(store.reorder("done", before: "pending"))
    XCTAssertFalse(store.reorder("pending", before: "done"))
  }

  @MainActor
  func testImportMergesWithoutOverwritingExistingIDs() async throws {
    let store = TaskStore(url: try temporaryURL())
    var original = task("existing")
    original.title = "本地内容"
    XCTAssertTrue(store.saveTask(original))
    var duplicate = original
    duplicate.title = "导入内容"
    let input = try TaskPersistence.encoded(TaskDocument(tasks: [duplicate, task("new")]))
    XCTAssertTrue(store.importTasks(input))
    XCTAssertEqual(store.tasks.count, 2)
    XCTAssertEqual(store.tasks.first(where: { $0.id == "existing" })?.title, "本地内容")
    XCTAssertTrue(store.importTasks(input))
    XCTAssertEqual(store.tasks.count, 2)
    XCTAssertEqual(TaskStore(url: store.persistence.url).tasks.count, 2)
  }

  @MainActor
  func testInvalidImportDoesNotChangeMemoryOrDisk() async throws {
    let url = try temporaryURL()
    let store = TaskStore(url: url)
    XCTAssertTrue(store.saveTask(task("safe")))
    let previous = store.document
    let bytes = try Data(contentsOf: url)
    var invalid = task("invalid")
    invalid.title = " \n "
    XCTAssertFalse(store.importTasks(try TaskPersistence.encoded(TaskDocument(tasks: [invalid]))))
    XCTAssertEqual(store.document, previous)
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertNotNil(store.errorMessage)
  }

  @MainActor
  func testCorruptFileIsPreservedAndWritesAreBlocked() async throws {
    let url = try temporaryURL()
    let badData = Data("{broken-data".utf8)
    try badData.write(to: url)
    let store = TaskStore(url: url)
    XCTAssertTrue(store.readOnly)
    XCTAssertNotNil(store.errorMessage)
    XCTAssertFalse(store.saveTask(task("must-not-overwrite")))
    XCTAssertEqual(try Data(contentsOf: url), badData)
  }

  @MainActor
  func testFailedWriteDoesNotCommitChangesInMemory() async throws {
    let blocker = try temporaryURL()
    try Data("not-a-directory".utf8).write(to: blocker)
    let store = TaskStore(url: blocker.appendingPathComponent("tasks.json"))
    XCTAssertFalse(store.saveTask(task("unsaved")))
    XCTAssertTrue(store.tasks.isEmpty)
    XCTAssertNotNil(store.errorMessage)
    XCTAssertEqual(try Data(contentsOf: blocker), Data("not-a-directory".utf8))
  }

  @MainActor
  func testSettingsSurviveRestart() async throws {
    let url = try temporaryURL()
    let store = TaskStore(url: url)
    store.updateSettings {
      $0.theme = .dark
      $0.sort = .priority
      $0.reminderHours = 48
    }
    XCTAssertEqual(TaskStore(url: url).settings, store.settings)
    store.updateSettings { $0.reminderHours = -1 }
    XCTAssertEqual(store.settings.reminderHours, 48)
  }

  @MainActor
  func testDeletingLastTaggedTaskClearsActiveTagFilter() async throws {
    let store = TaskStore(url: try temporaryURL())
    var item = task("tagged")
    item.tags = ["论文"]
    XCTAssertTrue(store.saveTask(item))
    store.filter.tag = "论文"
    store.delete(item.id)
    XCTAssertNil(store.filter.tag)
    XCTAssertTrue(store.allTags.isEmpty)
  }

  func testLegacyTaskArrayImportsOptionalFieldsAndFractionalDates() throws {
    let json = """
      [{"id":"legacy-1","title":"旧版待办","priority":"high","category":"工作","completed":false,
        "createdAt":"2026-11-24T02:00:00.123Z","dueDate":"2026-11-25","dueTime":"10:30"},
       {"id":"legacy-2","title":"旧版完成记录","priority":"low","category":"学习","completed":true,
        "createdAt":"2026-11-23T02:00:00Z","completedAt":"2026-11-23T03:00:00Z","tags":["Swift"]}]
      """
    let imported = try TaskPersistence.importedTasks(from: Data(json.utf8))
    XCTAssertEqual(imported.count, 2)
    XCTAssertEqual(imported[0].id, "legacy-1")
    XCTAssertNil(imported[0].note)
    XCTAssertEqual(imported[0].tagList, [])
    XCTAssertNotNil(imported[1].completedAt)
    XCTAssertEqual(imported[1].tagList, ["Swift"])
    XCTAssertEqual(
      imported[0].createdAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.123,
      accuracy: 0.001)
  }

  func testImportRejectsDuplicateIDsUnknownVersionAndMalformedValues() throws {
    let duplicate = TaskDocument(tasks: [task("same"), task("same")])
    XCTAssertThrowsError(
      try TaskPersistence.importedTasks(from: TaskPersistence.encoded(duplicate)))
    var document = TaskDocument(tasks: [task("a")])
    document.version = 2
    XCTAssertThrowsError(try TaskPersistence.importedTasks(from: TaskPersistence.encoded(document)))
    for (date, time) in [("2026-02-30", "09:00"), ("2026-11-24", "25:00"), ("2026-11-24", "10:99")]
    {
      XCTAssertThrowsError(
        try TaskPersistence.validate(
          TaskDocument(tasks: [task("invalid", dueDate: date, dueTime: time)])))
    }
    XCTAssertThrowsError(
      try TaskPersistence.validate(TaskDocument(tasks: [task("missing-date", dueTime: "10:00")])))
  }

  func testWidgetSnapshotRoundTripKeepsTasksAndReminderRangeWithoutAppSettings() throws {
    let url = try temporaryURL().deletingLastPathComponent()
      .appendingPathComponent("WidgetCache/snapshot.json")
    var pending = task("pending", dueDate: "2026-11-24", dueTime: "18:00", priority: .high)
    pending.category = .study
    pending.tags = ["Swift"]
    let completed = task("completed", completed: true, completedAt: now.addingTimeInterval(-60))
    let snapshot = WidgetSnapshot(
      generatedAt: now, tasks: [pending, completed], reminderHours: 48)

    try WidgetSharedStore.write(snapshot, to: url)
    XCTAssertEqual(try WidgetSharedStore.read(from: url), snapshot)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    XCTAssertEqual(json["version"] as? Int, 1)
    XCTAssertEqual(json["reminderHours"] as? Int, 48)
    XCTAssertNil(json["settings"])
    XCTAssertNil(json["theme"])
  }

  func testWidgetSnapshotReplacingWithEmptyTasksDoesNotResurrectOldData() throws {
    let url = try temporaryURL()
    try WidgetSharedStore.write(
      WidgetSnapshot(generatedAt: now, tasks: [task("old")], reminderHours: 24), to: url)
    let cleared = WidgetSnapshot(
      generatedAt: now.addingTimeInterval(60), tasks: [], reminderHours: 2)
    try WidgetSharedStore.write(cleared, to: url)
    XCTAssertEqual(try WidgetSharedStore.read(from: url), cleared)
    XCTAssertTrue(try WidgetSharedStore.read(from: url).tasks.isEmpty)
  }

  func testWidgetSnapshotInvalidWritePreservesLastValidSnapshot() throws {
    let url = try temporaryURL()
    let valid = WidgetSnapshot(generatedAt: now, tasks: [task("valid")], reminderHours: 24)
    try WidgetSharedStore.write(valid, to: url)
    let original = try Data(contentsOf: url)
    var unsupported = valid
    unsupported.version = 2
    let invalidSnapshots = [
      unsupported,
      WidgetSnapshot(generatedAt: now, tasks: [task("same"), task("same")], reminderHours: 24),
      WidgetSnapshot(
        generatedAt: now, tasks: [task("invalid-date", dueDate: "2026-02-30")], reminderHours: 24),
      WidgetSnapshot(generatedAt: now, tasks: valid.tasks, reminderHours: 1),
    ]
    for snapshot in invalidSnapshots {
      XCTAssertThrowsError(try WidgetSharedStore.write(snapshot, to: url))
      XCTAssertEqual(try Data(contentsOf: url), original)
      XCTAssertEqual(try WidgetSharedStore.read(from: url), valid)
    }
  }

  func testWidgetSnapshotMissingCorruptAndUnsupportedDataAreErrorsRatherThanEmptyLists() throws {
    let url = try temporaryURL()
    XCTAssertThrowsError(try WidgetSharedStore.read(from: url))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var unsupported = WidgetSnapshot(generatedAt: now, tasks: [], reminderHours: 24)
    unsupported.version = 2
    let duplicate = WidgetSnapshot(
      generatedAt: now, tasks: [task("duplicate"), task("duplicate")], reminderHours: 24)
    for data in [
      Data("not-json".utf8), try encoder.encode(unsupported), try encoder.encode(duplicate),
    ] {
      try data.write(to: url)
      XCTAssertThrowsError(try WidgetSharedStore.read(from: url))
      XCTAssertEqual(try Data(contentsOf: url), data, "Reading must preserve the invalid snapshot.")
    }
  }

  func testWidgetDestinationOnlyAcceptsKnownViewLinks() throws {
    for (text, expected) in [
      ("daylight://today", WidgetDestination.today),
      ("daylight://completed", WidgetDestination.completed),
      ("daylight://new-task", WidgetDestination.newTask),
      ("DAYLIGHT://TODAY", WidgetDestination.today),
    ] {
      XCTAssertEqual(WidgetDestination.destination(for: try XCTUnwrap(URL(string: text))), expected)
    }
    for text in [
      "https://today", "daylight://unknown", "daylight://all", "daylight:///today",
      "daylight://today/", "daylight://today/task", "daylight://today?task=one",
      "daylight://completed#day", "daylight://user@today", "daylight://today:1234",
      "daylight://new-task?title=example", "daylight://new-task/task", "daylight://new-task#title",
    ] {
      XCTAssertNil(WidgetDestination.destination(for: try XCTUnwrap(URL(string: text))), text)
    }
  }

  @MainActor
  func testWidgetRoutesResetFiltersAndOpenNewDraftWithoutWritingTasks() async throws {
    let url = try temporaryURL()
    let store = TaskStore(url: url)
    XCTAssertTrue(store.saveTask(task("existing")))
    let original = try Data(contentsOf: url)
    store.selectedView = .completed
    store.filter = TaskFilter(category: .study, priority: .high, tag: "Swift", search: "notes")
    store.newTask()
    let draft = try XCTUnwrap(store.editor)
    let token = store.widgetNavigationToken

    XCTAssertFalse(store.openWidgetURL(try XCTUnwrap(URL(string: "daylight://new-task?title=bad"))))
    XCTAssertEqual(store.selectedView, .completed)
    XCTAssertEqual(store.filter.category, .study)
    XCTAssertEqual(store.filter.priority, .high)
    XCTAssertEqual(store.filter.tag, "Swift")
    XCTAssertEqual(store.filter.search, "notes")
    XCTAssertEqual(store.editor?.id, draft.id)
    XCTAssertEqual(store.editor?.task, draft.task)
    XCTAssertEqual(store.widgetNavigationToken, token)

    XCTAssertTrue(store.openWidgetURL(try XCTUnwrap(URL(string: "daylight://today"))))
    XCTAssertEqual(store.selectedView, .today)
    XCTAssertFalse(store.filter.isActive)
    XCTAssertNotEqual(store.widgetNavigationToken, token)

    XCTAssertTrue(store.openWidgetURL(try XCTUnwrap(URL(string: "daylight://completed"))))
    XCTAssertEqual(store.selectedView, .completed)
    let completedToken = store.widgetNavigationToken
    XCTAssertTrue(store.openWidgetURL(try XCTUnwrap(URL(string: "daylight://completed"))))
    XCTAssertNotEqual(store.widgetNavigationToken, completedToken)

    store.filter.category = .study
    XCTAssertTrue(store.openWidgetURL(try XCTUnwrap(URL(string: "daylight://new-task"))))
    XCTAssertEqual(store.selectedView, .today)
    XCTAssertFalse(store.filter.isActive)
    let newDraft = try XCTUnwrap(store.editor)
    XCTAssertTrue(newDraft.isNew)
    XCTAssertEqual(newDraft.task.title, "")
    XCTAssertFalse(newDraft.task.completed)
    XCTAssertNotEqual(newDraft.id, draft.id)
    XCTAssertEqual(store.tasks.map(\.id), ["existing"])
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  func testDailyWidgetEmptySnapshotHasZeroCountsAndProgress() {
    let summary = DailyWidgetSummary(snapshot: .empty, now: now, calendar: calendar)
    XCTAssertEqual(summary.pendingCount, 0)
    XCTAssertEqual(summary.completedCount, 0)
    XCTAssertEqual(summary.totalCount, 0)
    XCTAssertEqual(summary.progress, 0)
    XCTAssertTrue(summary.displayedTasks.isEmpty)
    XCTAssertEqual(summary.remainingCount, 0)
  }

  func testDailyWidgetPendingTasksRespectTodayAndSnapshotReminderRange() {
    let items = [
      task("overdue", dueDate: "2026-11-23"),
      task("today", dueDate: "2026-11-24", dueTime: "23:00"),
      task("tomorrow-soon", dueDate: "2026-11-25", dueTime: "10:00"),
      task("tomorrow-late", dueDate: "2026-11-25", dueTime: "18:00"),
      task("undated"), task("future", dueDate: "2026-11-28"),
      task("completed-yesterday", completed: true, completedAt: now.addingTimeInterval(-86400)),
    ]
    let snapshot = WidgetSnapshot(generatedAt: now, tasks: items, reminderHours: 24)
    let summary = DailyWidgetSummary(snapshot: snapshot, now: now, calendar: calendar)
    XCTAssertEqual(
      summary.pendingTasks.map(\.id), ["overdue", "today", "tomorrow-soon", "undated"])
    XCTAssertEqual(summary.pendingCount, 4)
    XCTAssertEqual(summary.completedCount, 0)
    XCTAssertEqual(summary.progress, 0)

    var narrower = snapshot
    narrower.reminderHours = 2
    XCTAssertEqual(
      DailyWidgetSummary(snapshot: narrower, now: now, calendar: calendar).pendingTasks.map(\.id),
      ["overdue", "today", "undated"])
  }

  func testDailyWidgetCompletedTasksUseLocalCompletionDateRegardlessOfDeadline() throws {
    let start = calendar.startOfDay(for: now)
    let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
    let items = [
      task("earliest", dueDate: "2026-11-28", completed: true, completedAt: start),
      task(
        "latest", dueDate: "2026-11-20", completed: true,
        completedAt: tomorrow.addingTimeInterval(-1)),
      task("previous", completed: true, completedAt: start.addingTimeInterval(-1)),
      task("next", completed: true, completedAt: tomorrow),
      task("undated-completion", completed: true),
      task("pending-with-old-timestamp", dueDate: "2026-12-01", completedAt: now),
    ]
    let summary = DailyWidgetSummary(
      snapshot: WidgetSnapshot(generatedAt: now, tasks: items, reminderHours: 24),
      now: now, calendar: calendar)
    XCTAssertEqual(summary.completedTasks.map(\.id), ["latest", "earliest"])
    XCTAssertEqual(summary.displayedTasks.map(\.id), ["latest", "earliest"])
    XCTAssertEqual(summary.pendingCount, 0)
    XCTAssertEqual(summary.completedCount, 2)
    XCTAssertEqual(summary.progress, 1)
    XCTAssertEqual(summary.remainingCount, 0)
  }

  func testDailyWidgetRowsPutPendingFirstAndKeepFullCountsAfterTruncation() {
    let items = [
      task("done-old", completed: true, completedAt: now.addingTimeInterval(-120)),
      task("undated"),
      task("done-new", completed: true, completedAt: now),
      task("overdue", dueDate: "2026-11-23"),
      task("done-middle", completed: true, completedAt: now.addingTimeInterval(-60)),
    ]
    let summary = DailyWidgetSummary(
      snapshot: WidgetSnapshot(generatedAt: now, tasks: items, reminderHours: 24),
      now: now, calendar: calendar)
    XCTAssertEqual(
      summary.displayedTasks.map(\.id), ["overdue", "undated", "done-new", "done-middle"])
    XCTAssertEqual(summary.pendingCount, 2)
    XCTAssertEqual(summary.completedCount, 3)
    XCTAssertEqual(summary.totalCount, 5)
    XCTAssertEqual(summary.progress, 0.6, accuracy: 0.0001)
    XCTAssertEqual(summary.remainingCount, 1)
  }

  func testDailyWidgetDoesNotDisplacePendingTasksWithCompletedRows() {
    let items =
      (1...5).map { task("pending-\($0)") }
      + [task("done", completed: true, completedAt: now)]
    let summary = DailyWidgetSummary(
      snapshot: WidgetSnapshot(generatedAt: now, tasks: items.reversed(), reminderHours: 24),
      now: now, calendar: calendar)
    XCTAssertEqual(
      summary.displayedTasks.map(\.id), ["pending-1", "pending-2", "pending-3", "pending-4"])
    XCTAssertEqual(summary.pendingCount, 5)
    XCTAssertEqual(summary.completedCount, 1)
    XCTAssertEqual(summary.remainingCount, 2)
    XCTAssertEqual(summary.progress, 1.0 / 6.0, accuracy: 0.0001)
  }

  func testDateOnlyDeadlineUsesEndOfLocalDay() throws {
    let item = task("all-day", dueDate: "2026-11-24")
    let deadline = try XCTUnwrap(item.deadline(calendar: calendar))
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: deadline)
    XCTAssertEqual(components.day, 24)
    XCTAssertEqual(components.hour, 23)
    XCTAssertEqual(components.minute, 59)
    XCTAssertEqual(components.second, 59)
    XCTAssertEqual(item.urgency(at: now, hours: 2, calendar: calendar), .upcoming)
  }

  func testDeadlineBoundaryAndOverdueLabelForFirstMinute() throws {
    let item = task("timed", dueDate: "2026-11-24", dueTime: "12:00")
    XCTAssertEqual(item.urgency(at: now, hours: 2, calendar: calendar), .soon)
    XCTAssertEqual(
      item.urgency(at: now.addingTimeInterval(1), hours: 2, calendar: calendar), .overdue)
    XCTAssertTrue(
      TaskDates.dueLabel(item, now: now.addingTimeInterval(1), calendar: calendar).contains("逾期"))
    XCTAssertEqual(
      TaskDates.dueLabel(item, now: now.addingTimeInterval(61), calendar: calendar), "已逾期 2 分钟")
  }

  func testTodayAndReminderViewsRespectDatesCompletionAndSnooze() {
    var snoozed = task("snoozed", dueDate: "2026-11-24", dueTime: "11:00")
    snoozed.snoozedUntil = now.addingTimeInterval(3600)
    let tasks = [
      task("overdue", dueDate: "2026-11-23"),
      task("soon", dueDate: "2026-11-24", dueTime: "13:00"),
      task("undated"), task("future", dueDate: "2026-11-28"),
      task("done-today", completed: true, completedAt: now),
      task("done-yesterday", completed: true, completedAt: now.addingTimeInterval(-86400)),
      snoozed,
    ]
    let today = TaskLogic.filtered(tasks, view: .today, hours: 24, now: now, calendar: calendar)
    XCTAssertEqual(Set(today.map(\.id)), ["overdue", "soon", "undated", "done-today", "snoozed"])
    let reminders = TaskLogic.filtered(
      tasks, view: .reminders, hours: 24, now: now, calendar: calendar)
    XCTAssertEqual(Set(reminders.map(\.id)), ["overdue", "soon"])
    XCTAssertEqual(
      TaskLogic.filtered(tasks, view: .completed, now: now, calendar: calendar).count, 2)
  }

  func testSearchCombinesCategoryPriorityTagAndNote() {
    var match = task("match", priority: .high)
    match.category = .study
    match.note = "Review SwiftUI notes"
    match.tags = ["复盘", "Swift"]
    var different = match
    different.id = "other"
    different.category = .work
    let filter = TaskFilter(category: .study, priority: .high, tag: "Swift", search: "swiftui")
    XCTAssertEqual(
      TaskLogic.filtered([match, different], view: .all, filter: filter, now: now).map(\.id),
      ["match"])
    XCTAssertEqual(
      TaskLogic.tags(from: " #Swift,复盘，Swift 、 ##笔记; 学习； \n"), ["Swift", "复盘", "笔记", "学习"])
  }

  func testSortingUsesDeadlinePriorityCreationAndCompletedTimestamp() {
    var a = task("a", dueDate: "2026-11-24", dueTime: "10:00", priority: .low)
    var b = task("b", dueDate: "2026-11-24", dueTime: "10:00", priority: .high)
    var c = task("c", priority: .high)
    a.createdAt = now.addingTimeInterval(-60)
    b.createdAt = now.addingTimeInterval(-120)
    c.createdAt = now
    let done1 = task("done1", completed: true, completedAt: now.addingTimeInterval(-60))
    let done2 = task("done2", completed: true, completedAt: now)
    let items = [done1, c, a, done2, b]
    XCTAssertEqual(
      TaskLogic.sorted(items, by: .dueDate, calendar: calendar).map(\.id),
      ["b", "a", "c", "done2", "done1"])
    XCTAssertEqual(
      TaskLogic.sorted(items, by: .priority, calendar: calendar).map(\.id),
      ["b", "c", "a", "done2", "done1"])
    XCTAssertEqual(
      TaskLogic.sorted(items, by: .createdAt, calendar: calendar).map(\.id),
      ["c", "a", "b", "done2", "done1"])
  }

  func testCompletionHeatmapAndStreakUseLocalDates() {
    let tasks = [
      task("yesterday1", completed: true, completedAt: now.addingTimeInterval(-86400)),
      task("yesterday2", completed: true, completedAt: now.addingTimeInterval(-86400 + 60)),
      task("two-days", completed: true, completedAt: now.addingTimeInterval(-172800)),
      task("old", completed: true, completedAt: now.addingTimeInterval(-345600)),
      task("incomplete", completedAt: now),
    ]
    XCTAssertEqual(TaskLogic.completionCounts(tasks, calendar: calendar)["2026-11-23"], 2)
    XCTAssertNil(TaskLogic.completionCounts(tasks, calendar: calendar)["2026-11-24"])
    XCTAssertEqual(TaskLogic.streak(tasks, now: now, calendar: calendar), 2)
    XCTAssertEqual(
      TaskLogic.streak(
        tasks + [task("today", completed: true, completedAt: now)], now: now, calendar: calendar), 3
    )
  }

  func testCompletionCalendarMonthGridHandlesLeapYearsAndMondayAlignment() throws {
    for (year, month, count, leading, cells) in [
      (2024, 2, 29, 3, 35), (2025, 2, 28, 5, 35), (2026, 3, 31, 6, 42),
    ] {
      let date = try XCTUnwrap(
        calendar.date(from: DateComponents(year: year, month: month, day: 15, hour: 12)))
      let grid = CompletionCalendarLogic.days(in: date, calendar: calendar)
      let dates = grid.compactMap { $0 }
      XCTAssertEqual(grid.count, cells)
      XCTAssertEqual(grid.prefix(while: { $0 == nil }).count, leading)
      XCTAssertEqual(dates.count, count)
      XCTAssertEqual(dates.map { calendar.component(.day, from: $0) }, Array(1...count))
      XCTAssertTrue(dates.allSatisfy { calendar.component(.month, from: $0) == month })
      XCTAssertTrue(grid.dropFirst(leading + count).allSatisfy { $0 == nil })
    }
  }

  func testCompletionCalendarMonthNavigationNormalizesMonthEndAndYearBoundary() throws {
    let januaryEnd = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 23)))
    let start = CompletionCalendarLogic.monthStart(for: januaryEnd, calendar: calendar)
    XCTAssertEqual(TaskDates.day(start, calendar: calendar), "2026-01-01")
    XCTAssertEqual(calendar.component(.hour, from: start), 0)
    XCTAssertEqual(
      TaskDates.day(
        CompletionCalendarLogic.shiftedMonth(januaryEnd, by: 1, calendar: calendar),
        calendar: calendar), "2026-02-01")
    XCTAssertEqual(
      TaskDates.day(
        CompletionCalendarLogic.shiftedMonth(januaryEnd, by: -1, calendar: calendar),
        calendar: calendar), "2025-12-01")
    let december = try XCTUnwrap(TaskDates.date("2026-12-31", calendar: calendar))
    XCTAssertEqual(
      TaskDates.day(
        CompletionCalendarLogic.shiftedMonth(december, by: 1, calendar: calendar),
        calendar: calendar), "2027-01-01")
  }

  func testCompletionCalendarGridUsesCalendarDaysAcrossDaylightSavingTime() throws {
    var eastern = Calendar(identifier: .gregorian)
    eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    eastern.firstWeekday = 1
    let month = try XCTUnwrap(eastern.date(from: DateComponents(year: 2026, month: 3, day: 15)))
    let grid = CompletionCalendarLogic.days(in: month, calendar: eastern)
    let dates = grid.compactMap { $0 }
    XCTAssertEqual(grid.prefix(while: { $0 == nil }).count, 6)
    XCTAssertEqual(dates.map { eastern.component(.day, from: $0) }, Array(1...31))
    XCTAssertTrue(dates.allSatisfy { eastern.component(.hour, from: $0) == 0 })
    XCTAssertEqual(dates[8].timeIntervalSince(dates[7]), 23 * 3600, accuracy: 0.001)
  }

  func testCompletionCalendarUsesLocalCompletionDayAndExcludesUndatedOrPendingTasks() throws {
    let start = calendar.startOfDay(for: now)
    let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
    let items = [
      task("earliest", dueDate: "2026-11-28", completed: true, completedAt: start),
      task(
        "latest", dueDate: "2026-11-20", completed: true,
        completedAt: tomorrow.addingTimeInterval(-1)),
      task(
        "previous", dueDate: "2026-11-24", completed: true,
        completedAt: start.addingTimeInterval(-1)),
      task("next", completed: true, completedAt: tomorrow),
      task("pending", completedAt: now),
      task("undated", completed: true),
    ]
    let completed = CompletionCalendarLogic.completedTasks(items, on: now, calendar: calendar)
    XCTAssertEqual(completed.map(\.id), ["latest", "earliest"])
    XCTAssertEqual(TaskLogic.completionCounts(items, calendar: calendar)["2026-11-24"], 2)
    var utc = calendar
    utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    XCTAssertEqual(TaskDates.day(start, calendar: utc), "2026-11-23")
  }

  @MainActor
  func testCompletionCalendarUpdatesAfterCompleteRestoreAndCompleteOnAnotherDay() async throws {
    let store = TaskStore(url: try temporaryURL())
    freeze(store, at: now)
    XCTAssertTrue(store.saveTask(task("calendar-task")))
    store.toggle("calendar-task")
    XCTAssertEqual(
      CompletionCalendarLogic.completedTasks(store.tasks, on: now, calendar: calendar).map(\.id),
      ["calendar-task"])
    XCTAssertEqual(TaskLogic.completionCounts(store.tasks, calendar: calendar)["2026-11-24"], 1)
    store.toggle("calendar-task")
    XCTAssertTrue(
      CompletionCalendarLogic.completedTasks(store.tasks, on: now, calendar: calendar).isEmpty)
    XCTAssertNil(TaskLogic.completionCounts(store.tasks, calendar: calendar)["2026-11-24"])
    let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
    freeze(store, at: tomorrow)
    store.toggle("calendar-task")
    XCTAssertTrue(
      CompletionCalendarLogic.completedTasks(store.tasks, on: now, calendar: calendar).isEmpty)
    XCTAssertEqual(
      CompletionCalendarLogic.completedTasks(store.tasks, on: tomorrow, calendar: calendar).count, 1
    )
    XCTAssertEqual(TaskLogic.completionCounts(store.tasks, calendar: calendar)["2026-11-25"], 1)
  }

  func testReminderPlanSchedulesAdvanceAndDueNotifications() throws {
    let due = now.addingTimeInterval(48 * 3600)
    let item = task("future", dueDate: TaskDates.day(due), dueTime: TaskDates.time(due))
    let plans = ReminderPlan.make(
      tasks: [item, task("undated"), task("done", completed: true)], hours: 24, now: now)
    XCTAssertEqual(plans.count, 2)
    XCTAssertEqual(plans.map(\.date), [due.addingTimeInterval(-86400), due])
    XCTAssertEqual(Set(plans.map(\.taskID)), ["future"])
    XCTAssertTrue(plans[0].identifier.hasSuffix(".soon"))
    XCTAssertTrue(plans[1].identifier.hasSuffix(".due"))
  }

  func testReminderPlanSnoozeSuppressesNotificationsBeforeSnooze() {
    let due = now.addingTimeInterval(1800)
    var item = task("snoozed", dueDate: TaskDates.day(due), dueTime: TaskDates.time(due))
    item.snoozedUntil = now.addingTimeInterval(3600)
    let plans = ReminderPlan.make(tasks: [item], hours: 24, now: now)
    XCTAssertEqual(plans.count, 1)
    XCTAssertEqual(plans[0].date, item.snoozedUntil)
    XCTAssertTrue(plans[0].identifier.contains(".snooze."))
  }

  func testReminderPlanCapsScheduledRequestsAndOrdersEarliestFirst() {
    let items = (0..<50).map { index in
      let due = now.addingTimeInterval(Double(100 + index) * 3600)
      return task("item-\(index)", dueDate: TaskDates.day(due), dueTime: TaskDates.time(due))
    }
    let plans = ReminderPlan.make(tasks: items.reversed(), hours: 24, now: now)
    XCTAssertEqual(plans.count, 64)
    XCTAssertEqual(plans.map(\.date), plans.map(\.date).sorted())
    XCTAssertEqual(Set(plans.map(\.identifier)).count, plans.count)
  }

  func testReminderPlanSnoozeOnFarFutureTaskKeepsAdvanceAlert() {
    let due = now.addingTimeInterval(5 * 86400)
    var item = task("far", dueDate: TaskDates.day(due), dueTime: TaskDates.time(due))
    item.snoozedUntil = now.addingTimeInterval(3600)
    let plans = ReminderPlan.make(tasks: [item], hours: 24, now: now)
    XCTAssertEqual(plans.map(\.date), [item.snoozedUntil!, due.addingTimeInterval(-86400), due])
    XCTAssertTrue(plans[1].identifier.hasSuffix(".soon"))

    // After the snooze has fired, the advance and due alerts are still planned.
    let later = now.addingTimeInterval(7200)
    let afterSnooze = ReminderPlan.make(tasks: [item], hours: 24, now: later)
    XCTAssertEqual(afterSnooze.map(\.date), [due.addingTimeInterval(-86400), due])
  }

  func testReminderPlanSkipsAlreadyOverdueDueAlerts() {
    let past = now.addingTimeInterval(-3600)
    let overdue = task("overdue", dueDate: TaskDates.day(past), dueTime: TaskDates.time(past))
    XCTAssertTrue(ReminderPlan.make(tasks: [overdue], hours: 24, now: now).isEmpty)
  }

  func testDefaultDeadlineNeverStartsInThePast() throws {
    func at(_ hour: Int, _ minute: Int, day: Int = 24) throws -> Date {
      try XCTUnwrap(
        calendar.date(
          from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)))
    }
    XCTAssertEqual(TaskDates.defaultDeadline(now: try at(12, 0), calendar: calendar), try at(18, 0))
    XCTAssertEqual(TaskDates.defaultDeadline(now: try at(17, 0), calendar: calendar), try at(18, 0))
    XCTAssertEqual(
      TaskDates.defaultDeadline(now: try at(17, 10), calendar: calendar), try at(19, 30))
    XCTAssertEqual(
      TaskDates.defaultDeadline(now: try at(18, 30), calendar: calendar), try at(20, 30))
    XCTAssertEqual(TaskDates.defaultDeadline(now: try at(18, 40), calendar: calendar), try at(21, 0))
    XCTAssertEqual(
      TaskDates.defaultDeadline(now: try at(23, 10), calendar: calendar), try at(1, 30, day: 25))
  }

  @MainActor
  func testNewTaskDraftUsesFreshDefaultDeadline() throws {
    let store = TaskStore(url: try temporaryURL())
    let evening = try XCTUnwrap(calendar.date(byAdding: .hour, value: 8, to: now))  // 20:00
    store.clock = { evening }
    store.newTask()
    let draft = try XCTUnwrap(store.editor)
    let deadline = try XCTUnwrap(draft.task.deadline())
    XCTAssertGreaterThan(deadline, evening)
    XCTAssertEqual(store.now, evening)
  }

  func testDecodingFillsMissingFieldsAndAcceptsEnglishCategories() throws {
    let json = """
      {"tasks":[{"id":"minimal","title":"最少字段"},
                {"id":"english","title":"英文分类","category":"study"}],
       "settings":{"theme":"unknown-theme"}}
      """
    let document = try TaskPersistence.decoder().decode(TaskDocument.self, from: Data(json.utf8))
    XCTAssertEqual(document.version, 1)
    XCTAssertEqual(document.tasks[0].priority, .medium)
    XCTAssertEqual(document.tasks[0].category, .work)
    XCTAssertFalse(document.tasks[0].completed)
    XCTAssertEqual(document.tasks[1].category, .study)
    XCTAssertEqual(document.settings, AppSettings())
    XCTAssertNoThrow(try TaskPersistence.validate(document))

    let roundTrip = try TaskPersistence.decoder().decode(
      TaskDocument.self, from: TaskPersistence.encoded(document))
    XCTAssertEqual(roundTrip.tasks.map(\.category), [.work, .study])
    XCTAssertThrowsError(
      try TaskPersistence.decoder().decode(
        TaskItem.self, from: Data(#"{"id":"x","title":"x","category":"bogus"}"#.utf8)))
  }
}

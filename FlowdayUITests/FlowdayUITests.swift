import AppKit
import XCTest

final class FlowdayUITests: XCTestCase {
  @MainActor
  private func waitForInputSourceToSettle() {
    let indicator = XCUIApplication().dialogs.containing(.button, identifier: "InputSource")
      .firstMatch
    var quietSince = ProcessInfo.processInfo.systemUptime
    let settled = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        if indicator.exists {
          quietSince = ProcessInfo.processInfo.systemUptime
          return false
        }
        return ProcessInfo.processInfo.systemUptime - quietSince >= 1.5
      }, object: nil)
    // macOS briefly presents an input-source indicator after a field gains focus.
    // Wait for a quiet interval so XCTest does not treat it as an app dialog.
    wait(for: [settled], timeout: 6)
  }

  @MainActor
  private func paste(_ text: String, into field: XCUIElement) {
    let board = NSPasteboard.general
    let saved = (board.pasteboardItems ?? []).map { item in
      let copy = NSPasteboardItem()
      for type in item.types {
        if let data = item.data(forType: type) { copy.setData(data, forType: type) }
      }
      return copy
    }
    defer {
      board.clearContents()
      board.writeObjects(saved)
    }
    board.clearContents()
    board.setString(text, forType: .string)
    field.click()
    waitForInputSourceToSettle()
    field.typeKey("a", modifierFlags: .command)
    field.typeKey("v", modifierFlags: .command)
    waitForInputSourceToSettle()
  }
  @MainActor
  func testTaskLifecycleAndPersistence() throws {
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FlowdayUI-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--data-directory", directory.path]
    app.launch()
    XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
    let empty = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    empty.name = "Centered empty list"
    empty.lifetime = .keepAlways
    add(empty)
    app.buttons["new-task"].click()
    let title = app.textFields["editor-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    paste("Native lifecycle task", into: title)
    paste("test, native", into: app.textFields["editor-tags"])
    app.buttons["editor-save"].click()
    let taskButton = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "task-title-")
    ).firstMatch
    XCTAssertTrue(taskButton.waitForExistence(timeout: 5))
    XCTAssertEqual(taskButton.label, "Native lifecycle task")
    taskButton.click()
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    paste("Edited native task", into: title)
    app.buttons["editor-save"].click()
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
    let persisted = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "task-title-")
    ).firstMatch
    XCTAssertTrue(persisted.waitForExistence(timeout: 5))
    XCTAssertEqual(persisted.label, "Edited native task")
    let toggle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "toggle-"))
      .firstMatch
    toggle.click()
    app.buttons["nav-completed"].click()
    XCTAssertTrue(persisted.waitForExistence(timeout: 5))
    XCTAssertEqual(persisted.label, "Edited native task")
    toggle.click()
    app.buttons["nav-all"].click()
    XCTAssertTrue(persisted.waitForExistence(timeout: 5))
    let search = app.textFields["task-search"]
    paste("no-match-123", into: search)
    XCTAssertTrue(app.staticTexts["没有匹配的任务"].waitForExistence(timeout: 5))
    app.buttons["清除搜索"].click()
    XCTAssertTrue(persisted.waitForExistence(timeout: 5))
    persisted.rightClick()
    app.menuItems["删除任务"].click()
    app.buttons["删除任务"].click()
    XCTAssertTrue(app.staticTexts["清单已清空"].waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["清单已清空"].waitForExistence(timeout: 15))
    app.terminate()
  }

  @MainActor
  func testWidgetNewTaskLinkOpensEditorAndSavesInApp() throws {
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FlowdayWidgetUI-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--data-directory", directory.path]
    app.open(try XCTUnwrap(URL(string: "daylight://new-task")))
    defer { app.terminate() }
    let title = app.textFields["editor-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 15))
    XCTAssertEqual(app.windows.count, 1, "A widget link should reuse the main window.")
    XCTAssertFalse(app.buttons["editor-save"].isEnabled)
    paste("Widget link task", into: title)
    app.buttons["editor-save"].click()
    let task = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "task-title-")
    ).firstMatch
    XCTAssertTrue(task.waitForExistence(timeout: 5))
    XCTAssertEqual(task.label, "Widget link task")
    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = "Widget link and titlebar separator"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  private func calendarDayID(_ date: Date) -> String {
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "completion-day-%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }

  @MainActor
  private func staticTextValue(_ element: XCUIElement) -> String {
    let value = element.value as? String ?? ""
    let text = value.isEmpty ? element.label : value
    XCTAssertFalse(
      text.isEmpty, "The visible static text must expose a nonempty accessibility value or label.")
    return text
  }

  @MainActor @discardableResult
  private func openCompletionCalendarIfNeeded(_ app: XCUIApplication) -> Bool {
    if app.staticTexts["calendar-month"].exists { return false }
    app.buttons["completion-calendar-toggle"].click()
    XCTAssertTrue(app.staticTexts["calendar-month"].waitForExistence(timeout: 5))
    return true
  }

  @MainActor
  func testCompletionCalendarSelectionAndLiveCounts() throws {
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FlowdayCalendar-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--sample-data", "--data-directory", directory.path]
    let now = Date()
    let calendar = Calendar.current
    let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
    app.launch()
    XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
    let window = app.windows["main-AppWindow-1"]
    if window.frame.width < 1100 {
      let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(
        CGVector(dx: -2, dy: -2))
      corner.click(
        forDuration: 0.2,
        thenDragTo: corner.withOffset(CGVector(dx: 1240 - window.frame.width, dy: 0)))
    }
    openCompletionCalendarIfNeeded(app)
    let month = app.staticTexts["calendar-month"]
    let currentMonth = staticTextValue(month)
    app.buttons["calendar-previous-month"].click()
    XCTAssertNotEqual(staticTextValue(month), currentMonth)
    app.buttons["calendar-next-month"].click()
    XCTAssertEqual(staticTextValue(month), currentMonth)
    app.buttons["calendar-previous-month"].click()
    app.buttons["calendar-current-month"].click()
    XCTAssertEqual(staticTextValue(month), currentMonth)
    if !calendar.isDate(yesterday, equalTo: now, toGranularity: .month) {
      app.buttons["calendar-previous-month"].click()
    }
    let yesterdayButton = app.buttons[calendarDayID(yesterday)]
    XCTAssertTrue(yesterdayButton.waitForExistence(timeout: 5))
    XCTAssertTrue(yesterdayButton.label.contains("完成 1 项"))
    yesterdayButton.click()
    XCTAssertTrue(app.staticTexts["completion-date-filter"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["task-title-sample-history-1"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["task-title-sample-done-today"].exists)
    XCTAssertFalse(app.buttons["task-title-sample-history-2"].exists)
    let selected = XCTAttachment(screenshot: window.screenshot())
    selected.name = "Selected completion day"
    selected.lifetime = .keepAlways
    add(selected)

    app.buttons["toggle-sample-history-1"].click()
    XCTAssertTrue(app.staticTexts["这一天没有完成记录"].waitForExistence(timeout: 5))
    openCompletionCalendarIfNeeded(app)
    XCTAssertTrue(app.buttons[calendarDayID(yesterday)].label.contains("完成 0 项"))
    app.buttons["calendar-current-month"].click()
    let first = try XCTUnwrap(calendar.dateInterval(of: .month, for: now)?.start)
    let range = try XCTUnwrap(calendar.range(of: .day, in: .month, for: now))
    let occupied = Set(
      (0...5).compactMap { offset in
        calendar.date(byAdding: .day, value: -offset, to: now).map(calendarDayID)
      })
    let emptyDay = try XCTUnwrap(
      range.compactMap { day in
        calendar.date(byAdding: .day, value: day - 1, to: first)
      }.first { !occupied.contains(calendarDayID($0)) })
    app.buttons[calendarDayID(emptyDay)].click()
    XCTAssertTrue(app.staticTexts["这一天没有完成记录"].waitForExistence(timeout: 5))
    app.buttons["completion-clear-date"].click()
    XCTAssertFalse(app.staticTexts["completion-date-filter"].exists)
    XCTAssertTrue(app.buttons["task-title-sample-done-today"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["task-title-sample-history-2"].exists)
    XCTAssertFalse(app.buttons["task-title-sample-history-1"].exists)
    app.terminate()
  }

  @MainActor
  func testSettingsAndVisualStates() throws {
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FlowdayVisual-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--sample-data", "--data-directory", directory.path]
    app.launch()
    XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
    app.buttons["设置"].click()
    XCTAssertTrue(app.radioButtons["浅色"].waitForExistence(timeout: 5))
    app.radioButtons["浅色"].click()
    app.windows.firstMatch.buttons["_XCUI:CloseWindow"].click()
    XCTAssertFalse(app.textFields["quick-tags"].exists)
    app.buttons["quick-options"].click()
    XCTAssertTrue(app.textFields["quick-tags"].waitForExistence(timeout: 5))
    app.buttons["quick-options"].click()
    XCTAssertFalse(app.textFields["quick-tags"].exists)
    let main = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    main.name = "Main window"
    main.lifetime = .keepAlways
    add(main)
    app.buttons["nav-completed"].click()
    let archive = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    archive.name = "Completion archive"
    archive.lifetime = .keepAlways
    add(archive)
    app.buttons["nav-today"].click()
    app.buttons["设置"].click()
    XCTAssertTrue(app.radioButtons["深色"].waitForExistence(timeout: 5))
    app.radioButtons["深色"].click()
    let settings = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    settings.name = "Dark settings"
    settings.lifetime = .keepAlways
    add(settings)
    app.windows.firstMatch.buttons["_XCUI:CloseWindow"].click()
    let mainWindow = app.windows["main-AppWindow-1"]
    let corner = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(
      CGVector(dx: -2, dy: -2))
    let frame = mainWindow.frame
    corner.click(
      forDuration: 0.2,
      thenDragTo: corner.withOffset(CGVector(dx: 900 - frame.width, dy: 640 - frame.height)))
    XCTAssertLessThanOrEqual(mainWindow.frame.width, 950)
    let narrow = XCTAttachment(screenshot: mainWindow.screenshot())
    narrow.name = "Dark narrow main window"
    narrow.lifetime = .keepAlways
    add(narrow)
    app.buttons["quick-options"].click()
    XCTAssertTrue(app.textFields["quick-tags"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["quick-tags"].isHittable)
    let options = XCTAttachment(screenshot: mainWindow.screenshot())
    options.name = "Narrow quick-add options"
    options.lifetime = .keepAlways
    add(options)
    app.buttons["quick-options"].click()
    XCTAssertTrue(app.buttons["completion-calendar-toggle"].isHittable)
    app.buttons["completion-calendar-toggle"].click()
    XCTAssertTrue(app.staticTexts["calendar-month"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["calendar-previous-month"].isHittable)
    let calendarPopover = XCTAttachment(screenshot: mainWindow.screenshot())
    calendarPopover.name = "Narrow completion calendar"
    calendarPopover.lifetime = .keepAlways
    add(calendarPopover)
    app.typeKey(.escape, modifierFlags: [])
    app.buttons["new-task"].click()
    XCTAssertTrue(app.textFields["editor-title"].waitForExistence(timeout: 5))
    let editor = XCTAttachment(screenshot: mainWindow.screenshot())
    editor.name = "Dark task editor"
    editor.lifetime = .keepAlways
    add(editor)
    app.buttons["取消"].click()
    app.terminate()
  }
}

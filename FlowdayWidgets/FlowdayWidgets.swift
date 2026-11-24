import SwiftUI
import WidgetKit

struct FlowdayWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot?

  var pendingTasks: [TaskItem] {
    guard let snapshot else { return [] }
    return TaskLogic.sorted(
      TaskLogic.filtered(
        snapshot.tasks, view: .today, hours: snapshot.reminderHours, now: date
      ).filter { !$0.completed }, by: .dueDate)
  }

  var completionCounts: [String: Int] {
    TaskLogic.completionCounts(snapshot?.tasks ?? [])
  }

  var completedToday: Int { completionCounts[TaskDates.day(date)] ?? 0 }
}

struct FlowdayWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> FlowdayWidgetEntry {
    previewEntry()
  }

  func getSnapshot(in context: Context, completion: @escaping (FlowdayWidgetEntry) -> Void) {
    completion(context.isPreview ? previewEntry() : loadEntry(at: Date()))
  }

  func getTimeline(
    in context: Context, completion: @escaping (Timeline<FlowdayWidgetEntry>) -> Void
  ) {
    let now = Date()
    let refresh = now.addingTimeInterval(15 * 60)
    let midnight = Calendar.current.dateInterval(of: .day, for: now)?.end ?? refresh
    completion(Timeline(entries: [loadEntry(at: now)], policy: .after(min(refresh, midnight))))
  }

  private func loadEntry(at date: Date) -> FlowdayWidgetEntry {
    FlowdayWidgetEntry(date: date, snapshot: try? WidgetSharedStore.load())
  }

  private func previewEntry() -> FlowdayWidgetEntry {
    let now = Date()
    let tasks = [
      TaskItem(id: "widget-preview-plan", title: "整理今天的计划", priority: .high),
      TaskItem(id: "widget-preview-read", title: "阅读与学习", priority: .medium),
      TaskItem(
        id: "widget-preview-done", title: "完成一件小事", completed: true, completedAt: now),
    ]
    return FlowdayWidgetEntry(
      date: now, snapshot: WidgetSnapshot(generatedAt: now, tasks: tasks, reminderHours: 24))
  }
}

private struct WidgetSyncPrompt: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label("Flowday", systemImage: "checkmark.circle").font(.system(size: 13, weight: .semibold))
      Spacer(minLength: 0)
      Text("打开 Flowday，同步任务").font(.system(size: 14, weight: .medium))
      Text("点击小组件打开应用，完成一次数据同步。")
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

private struct FlowdayTasksView: View {
  let entry: FlowdayWidgetEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.widgetRenderingMode) private var renderingMode

  private var accent: Color { renderingMode == .fullColor ? .indigo : .primary }
  private var small: Bool { family == .systemSmall }
  private var limit: Int { small ? 2 : 4 }

  var body: some View {
    Group {
      if entry.snapshot == nil {
        WidgetSyncPrompt()
      } else {
        VStack(alignment: .leading, spacing: small ? 8 : 10) {
          HStack {
            Label("今日待办", systemImage: "checklist")
              .font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
              .widgetAccentable()
            Spacer(minLength: 4)
            Text(entry.date, format: .dateTime.month().day())
              .font(.system(size: 10)).foregroundStyle(.secondary)
          }
          if small {
            smallContent
          } else {
            mediumContent
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
    .widgetURL(URL(string: "daylight://today"))
    .environment(\.locale, Locale(identifier: "zh_CN"))
  }

  private var smallContent: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text("\(entry.pendingTasks.count)")
          .font(.system(size: 29, weight: .semibold)).monospacedDigit()
        Text("项待办").font(.system(size: 10)).foregroundStyle(.secondary)
      }.accessibilityElement(children: .combine)
      taskList
      Spacer(minLength: 0)
      Text("今日已完成 \(entry.completedToday) 项")
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }
  }

  private var mediumContent: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(entry.pendingTasks.count)")
          .font(.system(size: 34, weight: .semibold)).monospacedDigit()
        Text("项待办").font(.system(size: 10)).foregroundStyle(.secondary)
        Spacer(minLength: 4)
        Label("已完成 \(entry.completedToday)", systemImage: "checkmark.circle")
          .font(.system(size: 10)).foregroundStyle(.secondary)
      }.frame(width: 78, alignment: .leading).accessibilityElement(children: .combine)
      Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1)
      taskList.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var taskList: some View {
    VStack(alignment: .leading, spacing: small ? 4 : 5) {
      if entry.pendingTasks.isEmpty {
        Text("今天的清单已清空")
          .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        if !small {
          Text("点击打开 Flowday，记录新的任务。")
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
      } else {
        ForEach(Array(entry.pendingTasks.prefix(limit))) { task in
          HStack(spacing: 6) {
            Image(systemName: "circle").font(.system(size: 10))
              .foregroundStyle(.secondary).accessibilityHidden(true)
            Text(task.title).font(.system(size: 11)).lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
            if !small && task.priority == .high {
              Image(systemName: "flag.fill").font(.system(size: 8))
                .foregroundStyle(accent).accessibilityLabel("高优先级")
            }
          }.accessibilityElement(children: .combine)
        }
        if entry.pendingTasks.count > limit {
          Text("还有 \(entry.pendingTasks.count - limit) 项")
            .font(.system(size: 9)).foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct FlowdayDailyTasksView: View {
  let entry: FlowdayWidgetEntry
  @Environment(\.widgetRenderingMode) private var renderingMode

  private var accent: Color { renderingMode == .fullColor ? .indigo : .primary }
  private var completedColor: Color { renderingMode == .fullColor ? .green : .primary }

  var body: some View {
    Group {
      if let snapshot = entry.snapshot {
        dailyContent(DailyWidgetSummary(snapshot: snapshot, now: entry.date))
      } else {
        WidgetSyncPrompt()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
    .widgetURL(URL(string: "daylight://today"))
    .environment(\.locale, Locale(identifier: "zh_CN"))
  }

  private func dailyContent(_ summary: DailyWidgetSummary) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Flowday · 每日任务").font(.system(size: 14, weight: .semibold))
          Text("已完成 \(summary.completedCount) 项 · 待办 \(summary.pendingCount) 项")
            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
        Spacer(minLength: 0)
        progressRing(summary.progress)
      }
      Divider()
      Link(destination: URL(string: "daylight://new-task")!) {
        HStack(spacing: 8) {
          Text("记录新任务…").font(.system(size: 12)).foregroundStyle(.secondary)
          Spacer(minLength: 4)
          Image(systemName: "plus").font(.system(size: 13, weight: .medium))
            .foregroundStyle(accent)
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
          RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
      }.accessibilityLabel("在 Flowday 中记录新任务")

      if summary.displayedTasks.isEmpty {
        VStack(spacing: 9) {
          Image(systemName: "checkmark.circle").font(.system(size: 24, weight: .light))
            .foregroundStyle(accent).accessibilityHidden(true)
          Text("今天还没有任务").font(.system(size: 12, weight: .medium))
          Text("记录一件小事，从这里开始。")
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(spacing: 0) {
          ForEach(summary.displayedTasks) { task in
            dailyTaskRow(task)
            if task.id != summary.displayedTasks.last?.id {
              Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).padding(.leading, 27)
            }
          }
        }
        Spacer(minLength: 0)
      }

      Link(destination: URL(string: "daylight://today")!) {
        HStack(spacing: 4) {
          Text(summary.remainingCount > 0 ? "另有 \(summary.remainingCount) 项" : "今日任务")
            .foregroundStyle(.secondary)
          Spacer(minLength: 4)
          Text("查看全部").foregroundStyle(accent)
          Image(systemName: "arrow.up.right").foregroundStyle(accent)
        }.font(.system(size: 10))
      }.accessibilityLabel("查看全部今日任务，共 \(summary.totalCount) 项")
    }
  }

  private func progressRing(_ progress: Double) -> some View {
    ZStack {
      Circle().stroke(Color.primary.opacity(0.09), lineWidth: 4)
      Circle().trim(from: 0, to: progress)
        .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .rotationEffect(.degrees(-90)).widgetAccentable()
      Text("\(Int((progress * 100).rounded()))%")
        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
    }
    .frame(width: 42, height: 42).padding(2)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("今日完成进度 \(Int((progress * 100).rounded()))%")
  }

  private func dailyTaskRow(_ task: TaskItem) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(task.completed ? completedColor : Color.secondary)
        .frame(width: 18, height: 18).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(task.title).font(.system(size: 12, weight: .medium))
          .strikethrough(task.completed)
          .foregroundStyle(task.completed ? Color.secondary : Color.primary)
          .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 6) {
          Circle().fill(priorityColor(task.priority)).frame(width: 4, height: 4)
          Text(task.priority.label).foregroundStyle(priorityColor(task.priority))
          Text("·").foregroundStyle(.tertiary)
          Text(task.completed ? "已完成" : TaskDates.dueLabel(task, now: entry.date))
            .foregroundStyle(.secondary).lineLimit(1)
          Spacer(minLength: 0)
          Text(task.category.rawValue).foregroundStyle(.secondary)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 3))
        }.font(.system(size: 9)).lineLimit(1)
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(task.completed ? "已完成" : "待办")：\(task.title)，\(task.priority.label)，\(task.completed ? "已完成" : TaskDates.dueLabel(task, now: entry.date))，\(task.category.rawValue)"
    )
  }

  private func priorityColor(_ priority: Priority) -> Color {
    guard renderingMode == .fullColor else { return .secondary }
    switch priority {
    case .high: return .red
    case .medium: return .orange
    case .low: return .secondary
    }
  }
}

private struct FlowdayCalendarView: View {
  let entry: FlowdayWidgetEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.widgetRenderingMode) private var renderingMode

  private var large: Bool { family == .systemLarge }
  private var accent: Color { renderingMode == .fullColor ? .indigo : .primary }

  private var dates: [Date?] {
    let calendar = Calendar.current
    guard let start = calendar.dateInterval(of: .month, for: entry.date)?.start,
      let range = calendar.range(of: .day, in: .month, for: start)
    else { return [] }
    let leading = (calendar.component(.weekday, from: start) + 5) % 7
    var result = [Date?](repeating: nil, count: leading)
    result += range.map { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    result += [Date?](repeating: nil, count: (7 - result.count % 7) % 7)
    return result
  }

  private var completedThisMonth: Int {
    dates.compactMap { $0 }.reduce(0) { $0 + (entry.completionCounts[TaskDates.day($1)] ?? 0) }
  }

  var body: some View {
    Group {
      if entry.snapshot == nil {
        WidgetSyncPrompt()
      } else if large {
        VStack(alignment: .leading, spacing: 14) {
          header
          calendarGrid
          Divider()
          HStack {
            statistic("本月完成", value: completedThisMonth, unit: "项")
            Spacer()
            statistic("今日完成", value: entry.completedToday, unit: "项")
            Spacer()
            statistic("连续记录", value: streak, unit: "天")
          }
        }
      } else {
        HStack(alignment: .top, spacing: 16) {
          VStack(alignment: .leading, spacing: 7) {
            Label("完成日历", systemImage: "calendar")
              .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
              .widgetAccentable()
            statistic("本月完成", value: completedThisMonth, unit: "项")
            Spacer(minLength: 0)
            Text("连续记录 \(streak) 天").font(.system(size: 9)).foregroundStyle(.secondary)
          }.frame(width: 90, alignment: .leading)
          VStack(spacing: 5) {
            Text(entry.date, format: .dateTime.year().month(.wide))
              .font(.system(size: 11, weight: .semibold)).frame(
                maxWidth: .infinity, alignment: .leading)
            calendarGrid
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
    .widgetURL(URL(string: "daylight://completed"))
    .environment(\.locale, Locale(identifier: "zh_CN"))
  }

  private var streak: Int { TaskLogic.streak(entry.snapshot?.tasks ?? [], now: entry.date) }

  private var header: some View {
    HStack {
      Label("完成日历", systemImage: "calendar")
        .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent).widgetAccentable()
      Spacer(minLength: 4)
      Text(entry.date, format: .dateTime.year().month(.wide))
        .font(.system(size: 11)).foregroundStyle(.secondary)
    }
  }

  private var calendarGrid: some View {
    GeometryReader { geometry in
      let rows = max(1, dates.count / 7)
      let gap: CGFloat = large ? 5 : 2
      let weekdayHeight: CGFloat = large ? 14 : 9
      let cellHeight = max(
        10, (geometry.size.height - weekdayHeight - gap * CGFloat(rows)) / CGFloat(rows))
      VStack(spacing: gap) {
        HStack(spacing: gap) {
          ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
            Text(weekday).font(.system(size: large ? 10 : 7)).foregroundStyle(.secondary)
              .frame(maxWidth: .infinity).frame(height: weekdayHeight).accessibilityHidden(true)
          }
        }
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 7), spacing: gap
        ) {
          ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
            if let date {
              calendarDay(date, height: cellHeight)
            } else {
              Color.clear.frame(height: cellHeight).accessibilityHidden(true)
            }
          }
        }
      }
    }
  }

  private func calendarDay(_ date: Date, height: CGFloat) -> some View {
    let count = entry.completionCounts[TaskDates.day(date)] ?? 0
    let today = Calendar.current.isDate(date, inSameDayAs: entry.date)
    return Group {
      if large {
        VStack(spacing: 1) {
          Text("\(Calendar.current.component(.day, from: date))")
            .font(.system(size: 12, weight: today ? .semibold : .regular))
            .foregroundStyle(today ? accent : .primary)
          Text(count > 0 ? (count > 99 ? "99+" : "\(count)") : " ")
            .font(.system(size: 8, weight: .semibold)).foregroundStyle(accent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
          Text("\(Calendar.current.component(.day, from: date))")
            .font(.system(size: 9, weight: today ? .semibold : .regular))
            .foregroundStyle(today ? accent : .primary)
          if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
              .font(.system(size: 7, weight: .semibold)).foregroundStyle(accent)
              .baselineOffset(2)
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(height: height)
    .background(
      count > 0 ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: large ? 6 : 3)
    )
    .overlay(
      RoundedRectangle(cornerRadius: large ? 6 : 3)
        .strokeBorder(today ? accent : .clear, lineWidth: 1)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(TaskDates.day(date))，完成 \(count) 项" + (today ? "，今天" : ""))
  }

  private func statistic(_ label: String, value: Int, unit: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text("\(value)").font(.system(size: large ? 23 : 27, weight: .semibold)).monospacedDigit()
        Text(unit).font(.system(size: 9)).foregroundStyle(.secondary)
      }
    }.accessibilityElement(children: .combine)
  }
}

struct FlowdayTasksWidget: Widget {
  let kind = "DaylightTasks"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FlowdayWidgetProvider()) { entry in
      FlowdayTasksView(entry: entry)
    }
    .configurationDisplayName("今日待办")
    .description("在桌面查看今日待办与完成数量，点击打开 Flowday。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct FlowdayCompletionCalendarWidget: Widget {
  let kind = "DaylightCompletionCalendar"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FlowdayWidgetProvider()) { entry in
      FlowdayCalendarView(entry: entry)
    }
    .configurationDisplayName("完成日历")
    .description("查看本月每天完成的任务数量和连续记录，点击打开完成归档。")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

struct FlowdayDailyTasksWidget: Widget {
  let kind = "DaylightDailyTasks"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FlowdayWidgetProvider()) { entry in
      FlowdayDailyTasksView(entry: entry)
    }
    .configurationDisplayName("每日任务")
    .description("查看今日任务、完成进度与任务详情，点击加号在 Flowday 中记录新任务。")
    .supportedFamilies([.systemLarge])
  }
}

@main
struct FlowdayWidgetBundle: WidgetBundle {
  var body: some Widget {
    FlowdayTasksWidget()
    FlowdayDailyTasksWidget()
    FlowdayCompletionCalendarWidget()
  }
}

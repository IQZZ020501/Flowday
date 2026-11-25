import SwiftUI

struct ContentView: View {
  @Bindable var store: TaskStore
  let reminders: ReminderService
  @State private var visibility: NavigationSplitViewVisibility = .all
  @State private var deletion: TaskItem?
  @State private var selectedCompletionDate: Date?
  @State private var calendarMonth = Date()
  @State private var calendarPresented = false
  @FocusState private var searchFocused: Bool
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationSplitView(columnVisibility: $visibility) {
      SidebarView(store: store)
    } detail: {
      workspace
        .navigationTitle("Flowday")
        .toolbarBackground(FlowdayStyle.canvas, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
    }
    .sheet(item: $store.editor) { draft in
      TaskEditorView(store: store, draft: draft)
    }
    .alert(
      "操作未完成",
      isPresented: Binding(
        get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    ) {
      Button("知道了", role: .cancel) { store.errorMessage = nil }
    } message: {
      Text(store.errorMessage ?? "")
    }
    .confirmationDialog(
      "删除这项任务？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
      titleVisibility: .visible
    ) {
      Button("删除任务", role: .destructive) {
        if let task = deletion { store.delete(task.id) }
        deletion = nil
      }
      Button("取消", role: .cancel) { deletion = nil }
    } message: {
      Text(deletion?.title ?? "")
    }
    .overlay(alignment: .bottom) {
      if let notice = store.notice {
        Text(notice).font(.system(size: 12)).padding(.horizontal, 18).padding(.vertical, 10)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(16)
          .accessibilityIdentifier("notice")
      }
    }
    .task(id: store.notice) {
      guard store.notice != nil else { return }
      do {
        try await Task.sleep(for: .seconds(2.5))
        store.notice = nil
      } catch {}
    }
    .task(id: store.document) {
      await reminders.synchronize(tasks: store.tasks, settings: store.settings)
    }
    .task {
      // A long-lived task keeps ticking even when the body re-renders (a Timer created in
      // body would be recreated and reset on every update).
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        store.refreshNow()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        store.refreshNow()
        Task { await reminders.refresh() }
      }
    }
    .onChange(of: store.searchFocusToken) { searchFocused = true }
    .onChange(of: store.widgetNavigationToken) {
      selectedCompletionDate = nil
      calendarPresented = false
    }
    .onChange(of: store.selectedView) { _, view in
      if view != .completed { selectedCompletionDate = nil }
    }
  }

  private var searchField: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass").foregroundStyle(FlowdayStyle.muted)
      TextField("搜索任务…", text: $store.filter.search)
        .textFieldStyle(.plain).focused($searchFocused)
        .accessibilityIdentifier("task-search")
      if !store.filter.search.isEmpty {
        Button {
          store.filter.search = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain).foregroundStyle(FlowdayStyle.muted).accessibilityLabel("清除搜索")
      }
    }.font(.system(size: 12)).padding(.horizontal, 9).padding(.vertical, 7)
      .background(FlowdayStyle.surface, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(FlowdayStyle.border, lineWidth: 1))
      .frame(width: 165)
  }

  private var sortMenu: some View {
    Menu {
      Picker(
        "排序方式",
        selection: Binding(
          get: { store.settings.sort },
          set: { value in store.updateSettings { $0.sort = value } })
      ) {
        ForEach(TaskSort.allCases) { mode in Text(mode.label).tag(mode) }
      }
    } label: {
      Image(systemName: "slider.horizontal.3").font(.system(size: 13))
        .foregroundStyle(FlowdayStyle.muted).frame(width: 30, height: 30)
        .background(FlowdayStyle.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(FlowdayStyle.border, lineWidth: 1))
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .help("按\(store.settings.sort.label)排序").accessibilityLabel("排序")
    .accessibilityIdentifier("sort-menu")
  }

  private var completedTasks: [TaskItem] {
    TaskLogic.filtered(store.tasks, view: .completed, filter: store.filter, now: store.now)
  }

  private var displayedTasks: [TaskItem] {
    if store.selectedView == .completed, let selectedCompletionDate {
      return CompletionCalendarLogic.completedTasks(completedTasks, on: selectedCompletionDate)
    }
    return store.visibleTasks
  }

  private var workspace: some View {
    GeometryReader { geometry in
      let showsCalendar = geometry.size.width >= 840
      VStack(spacing: 0) {
        Rectangle().fill(FlowdayStyle.border).frame(height: 1)
        header(showsCalendar: showsCalendar)
        Rectangle().fill(FlowdayStyle.border).frame(height: 1)
        HStack(spacing: 0) {
          taskWorkspace.frame(maxWidth: .infinity, maxHeight: .infinity)
          if showsCalendar {
            Rectangle().fill(FlowdayStyle.border).frame(width: 1)
            ScrollView {
              calendarPanel.padding(20)
            }
            .frame(width: 286)
            .frame(maxHeight: .infinity)
            .background(FlowdayStyle.surface)
          }
        }
      }
      .onChange(of: showsCalendar) { _, visible in
        if visible { calendarPresented = false }
      }
    }
    .background(FlowdayStyle.canvas)
  }

  private var taskWorkspace: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        filterBar
        if store.readOnly {
          Label("本地数据读取失败，写入已暂停。", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red).font(.system(size: 12))
        }
        if store.selectedView == .reminders && !store.reminders.isEmpty { reminderStrip }
        if store.selectedView != .completed { QuickAddView(store: store) }
        if store.filter.isActive { activeFilters }
        if store.selectedView == .completed, let selectedCompletionDate {
          HStack(spacing: 8) {
            Label(
              TaskDates.heading(selectedCompletionDate, now: store.now), systemImage: "calendar"
            )
            .font(.system(size: 12, weight: .medium)).foregroundStyle(FlowdayStyle.ink)
            .accessibilityIdentifier("completion-date-filter")
            Spacer(minLength: 0)
            Button("全部记录") { self.selectedCompletionDate = nil }
              .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(FlowdayStyle.accent)
              .accessibilityIdentifier("completion-clear-date")
          }
          .padding(10).background(FlowdayStyle.selection, in: RoundedRectangle(cornerRadius: 6))
        }
      }
      .padding(.horizontal, 20).padding(.vertical, 16)
      if displayedTasks.isEmpty {
        taskSections.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if store.selectedView == .completed { completionHistory }
            taskSections
          }
          .padding(.top, 4).padding(.bottom, 24)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  private var filterBar: some View {
    HStack(spacing: 10) {
      Picker("分类筛选", selection: $store.filter.category) {
        Text("全部分类").tag(Optional<TaskCategory>.none)
        ForEach(TaskCategory.allCases) { category in
          Label(category.rawValue, systemImage: category.symbol).tag(Optional(category))
        }
      }.labelsHidden().frame(width: 105).accessibilityIdentifier("category-filter")
      Picker("优先级筛选", selection: $store.filter.priority) {
        Text("全部优先级").tag(Optional<Priority>.none)
        ForEach(Priority.allCases) { priority in
          Text(priority.label).tag(Optional(priority))
        }
      }.labelsHidden().frame(width: 112).accessibilityIdentifier("priority-filter")
      Spacer(minLength: 8)
      sortMenu
    }.controlSize(.small)
  }

  private func header(showsCalendar: Bool) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(store.selectedView.title)
            .font(.system(size: 17, weight: .semibold)).foregroundStyle(FlowdayStyle.ink)
            .accessibilityAddTraits(.isHeader)
          Text("\(displayedTasks.count)")
            .font(.system(size: 11, weight: .medium)).monospacedDigit()
            .foregroundStyle(FlowdayStyle.muted)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(FlowdayStyle.hover, in: RoundedRectangle(cornerRadius: 4))
        }
        Text(store.now, format: .dateTime.month().day().weekday(.wide))
          .font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted)
      }
      Spacer(minLength: 8)
      searchField
      if !showsCalendar {
        Button {
          calendarPresented.toggle()
        } label: {
          Image(systemName: "calendar").font(.system(size: 13))
        }
        .buttonStyle(FlowdayButtonStyle()).help("查看完成日历")
        .accessibilityLabel("完成日历").accessibilityIdentifier("completion-calendar-toggle")
        .popover(isPresented: $calendarPresented, arrowEdge: .bottom) {
          calendarPanel.padding(20).frame(width: 300).background(FlowdayStyle.surface)
        }
      }
      Button {
        store.newTask(completed: store.selectedView == .completed)
      } label: {
        Label(store.selectedView == .completed ? "记录完成项" : "新建任务", systemImage: "plus")
      }
      .buttonStyle(FlowdayButtonStyle(primary: true)).fixedSize()
      .help("新建任务（⌘N）").accessibilityIdentifier("new-task")
    }
    .padding(.horizontal, 20).padding(.vertical, 16)
  }

  private var calendarPanel: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Label("完成日历", systemImage: "calendar.badge.checkmark")
          .font(.system(size: 13, weight: .semibold)).foregroundStyle(FlowdayStyle.ink)
        Text(store.filter.isActive ? "按当前筛选显示完成记录" : "点击日期，回顾当天完成的任务")
          .font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted)
      }
      CompletionCalendarView(
        tasks: completedTasks, now: store.now, month: $calendarMonth,
        selectedDate: selectedCompletionDate
      ) { date in
        selectedCompletionDate = date
        store.selectedView = .completed
        calendarPresented = false
      }
      Rectangle().fill(FlowdayStyle.border).frame(height: 1)
      HStack(spacing: 0) {
        calendarMetric(
          "今日完成",
          value: CompletionCalendarLogic.completedTasks(completedTasks, on: store.now).count,
          unit: "项")
        Spacer(minLength: 8)
        calendarMetric("连续记录", value: TaskLogic.streak(completedTasks, now: store.now), unit: "天")
      }
      Button {
        selectedCompletionDate = nil
        store.selectedView = .completed
        calendarPresented = false
      } label: {
        HStack {
          Text("查看全部完成记录")
          Spacer()
          Image(systemName: "arrow.up.right")
        }.font(.system(size: 11)).foregroundStyle(FlowdayStyle.accent)
          .padding(.vertical, 4).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("calendar-all-completions")
    }
    .accessibilityIdentifier("completion-calendar-panel")
  }

  private func calendarMetric(_ title: String, value: Int, unit: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text("\(value)").font(.system(size: 22, weight: .semibold)).monospacedDigit()
          .foregroundStyle(FlowdayStyle.ink)
        Text(unit).font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted)
      }
    }
  }

  private var completionHistory: some View {
    DisclosureGroup {
      HeatmapView(tasks: completedTasks, now: store.now).padding(.top, 12)
    } label: {
      Label("最近 28 天趋势", systemImage: "chart.bar.xaxis")
        .font(.system(size: 11, weight: .medium)).foregroundStyle(FlowdayStyle.muted)
    }
    .padding(12)
    .background(FlowdayStyle.surface, in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(FlowdayStyle.border, lineWidth: 1))
    .padding(.horizontal, 20)
    .accessibilityIdentifier("completion-history")
  }

  private var reminderStrip: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        reminderLabel
        Spacer()
        reminderControls
      }
      VStack(alignment: .leading, spacing: 12) {
        reminderLabel
        reminderControls
      }
    }
    .padding(.horizontal, 12).padding(.vertical, 9)
    .background(FlowdayStyle.hover.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
  }

  private var reminderLabel: some View {
    Label("\(store.reminders.count) 项任务需要留意", systemImage: "bell.badge")
      .font(.system(size: 12, weight: .medium))
  }

  private var reminderControls: some View {
    HStack(spacing: 14) {
      Picker(
        "提醒范围",
        selection: Binding(
          get: { store.settings.reminderHours },
          set: { value in store.updateSettings { $0.reminderHours = value } })
      ) {
        ForEach([2, 24, 48], id: \.self) { Text("\($0) 小时内").tag($0) }
      }.labelsHidden().frame(width: 112).controlSize(.small)
    }
  }

  private var activeFilters: some View {
    HStack {
      Text("筛选结果：\(displayedTasks.count) 项" + (store.filter.tag.map { " · #" + $0 } ?? ""))
        .foregroundStyle(.secondary).lineLimit(2)
      Spacer()
      Button("清除筛选") { store.filter = TaskFilter() }.buttonStyle(.link)
    }.font(.system(size: 11))
  }

  @ViewBuilder private var taskSections: some View {
    let visible = displayedTasks
    if visible.isEmpty {
      VStack(spacing: 12) {
        Image(systemName: store.filter.isActive ? "magnifyingglass" : "checkmark.circle")
          .font(.system(size: 26, weight: .light)).foregroundStyle(FlowdayStyle.muted)
          .frame(width: 56, height: 56)
          .background(FlowdayStyle.hover, in: RoundedRectangle(cornerRadius: 12))
          .padding(.bottom, 4).accessibilityHidden(true)
        Text(
          selectedCompletionDate != nil && store.selectedView == .completed
            ? (store.filter.isActive ? "这一天没有匹配的完成记录" : "这一天没有完成记录")
            : store.filter.isActive
              ? "没有匹配的任务" : store.selectedView == .completed ? "还没有完成记录" : "清单已清空"
        )
        .font(.system(size: 16, weight: .semibold)).foregroundStyle(
          FlowdayStyle.ink)
        Text(
          selectedCompletionDate != nil && store.selectedView == .completed
            ? "选择其他日期，或查看全部完成记录。"
            : store.filter.isActive
              ? "换个关键词，或清除筛选后再看看。"
              : store.selectedView == .reminders ? "当前没有需要提醒的任务。" : "记录一件小事，从这里开始。"
        )
        .font(.system(size: 12)).foregroundStyle(FlowdayStyle.muted)
        .multilineTextAlignment(.center)
        if selectedCompletionDate != nil && store.selectedView == .completed {
          Button("查看全部记录") { selectedCompletionDate = nil }.buttonStyle(FlowdayButtonStyle())
        } else if store.filter.isActive {
          Button("清除筛选") { store.filter = TaskFilter() }.buttonStyle(FlowdayButtonStyle())
        } else if store.selectedView != .reminders {
          Button("记录任务") { store.newTask(completed: store.selectedView == .completed) }
            .buttonStyle(FlowdayButtonStyle(primary: true)).padding(.top, 4)
        }
      }
      .padding(24).frame(maxWidth: .infinity, minHeight: 220)
    } else if store.selectedView == .completed, selectedCompletionDate != nil {
      rows(visible)
    } else if store.selectedView == .completed {
      let groups = Dictionary(grouping: visible) { $0.completedAt.map { TaskDates.day($0) } ?? "" }
      ForEach(groups.keys.sorted(by: >), id: \.self) { key in
        VStack(alignment: .leading, spacing: 8) {
          Text(TaskDates.date(key).map { TaskDates.heading($0, now: store.now) } ?? "未记录完成日期")
            .font(.system(size: 11, weight: .medium)).foregroundStyle(FlowdayStyle.muted)
            .padding(.horizontal, 24).padding(.vertical, 9)
          rows(groups[key] ?? [])
        }
      }
    } else {
      let pending = visible.filter { !$0.completed }
      let done = visible.filter(\.completed)
      if !pending.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Image(systemName: "circle.dotted").foregroundStyle(FlowdayStyle.muted)
            Text("待处理").fontWeight(.medium).foregroundStyle(FlowdayStyle.ink)
            Text("\(pending.count)").foregroundStyle(FlowdayStyle.muted).monospacedDigit()
            Spacer()
            Text(store.settings.sort == .manual ? "自定义顺序" : "按\(store.settings.sort.label)排序")
          }.font(.system(size: 11)).foregroundStyle(FlowdayStyle.muted)
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(FlowdayStyle.sidebar.opacity(0.5))
          rows(pending)
        }
      }
      if !done.isEmpty {
        DisclosureGroup {
          rows(done).padding(.top, 10)
        } label: {
          Text("\(store.selectedView == .today ? "今日已完成" : "已完成记录") · \(done.count) 项")
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }.padding(.horizontal, 24)
      }
    }
  }

  private func rows(_ tasks: [TaskItem]) -> some View {
    LazyVStack(spacing: 0) {
      ForEach(tasks) { task in
        TaskRowView(task: task, store: store, onDelete: { deletion = task })
        if task.id != tasks.last?.id {
          Rectangle().fill(FlowdayStyle.border.opacity(0.55)).frame(height: 1)
            .padding(.horizontal, 12)
        }
      }
    }
    .padding(.horizontal, 12)
  }
}

import SwiftUI

struct TaskEditorView: View {
  let store: TaskStore
  let draft: EditorDraft
  @State private var task: TaskItem
  @State private var tags: String
  @State private var hasDate: Bool
  @State private var hasTime: Bool
  @State private var date: Date
  @FocusState private var titleFocused: Bool
  @Environment(\.dismiss) private var dismiss

  init(store: TaskStore, draft: EditorDraft) {
    self.store = store
    self.draft = draft
    _task = State(initialValue: draft.task)
    _tags = State(initialValue: draft.task.tagList.joined(separator: ", "))
    _hasDate = State(initialValue: draft.task.dueDate != nil)
    _hasTime = State(initialValue: draft.task.dueTime != nil)
    _date = State(initialValue: draft.task.deadline() ?? store.now)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(draft.isNew ? (task.completed ? "记录完成项" : "新建任务") : "编辑任务")
          .font(.system(size: 18, weight: .semibold))
        Spacer()
        Image(systemName: "square.and.pencil").foregroundStyle(.secondary)
      }.padding(24)

      Form {
        Section {
          TextField("任务标题", text: $task.title, prompt: Text("想完成什么？"), axis: .vertical)
            .labelsHidden()
            .font(.system(size: 16)).lineLimit(1...3).focused($titleFocused)
            .accessibilityIdentifier("editor-title")
          TextField(
            "备注", text: Binding(get: { task.note ?? "" }, set: { task.note = $0 }),
            prompt: Text("添加备注（可选）"), axis: .vertical
          )
          .labelsHidden().lineLimit(3...5).accessibilityIdentifier("editor-note")
        }
        Section {
          Picker("分类", selection: $task.category) {
            ForEach(TaskCategory.allCases) { category in
              Label(category.rawValue, systemImage: category.symbol).tag(category)
            }
          }.accessibilityIdentifier("editor-category")
          Picker("优先级", selection: $task.priority) {
            ForEach(Priority.allCases) { priority in
              Label(priority.label, systemImage: "flag").tag(priority)
            }
          }.accessibilityIdentifier("editor-priority")
          TextField("标签", text: $tags, prompt: Text("逗号或空格分隔"))
            .accessibilityIdentifier("editor-tags")
          if !store.allTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 12) {
                ForEach(Array(store.allTags.prefix(8)), id: \.name) { tag in
                  Button("#" + tag.name) {
                    tags = Array(NSOrderedSet(array: TaskLogic.tags(from: tags) + [tag.name]))
                      .compactMap { $0 as? String }.joined(separator: ", ")
                  }.buttonStyle(.link).font(.system(size: 11))
                }
              }
            }
          }
        }
        Section("截止时间") {
          DeadlineOptions(hasDate: $hasDate, hasTime: $hasTime, date: $date)
        }
        Section {
          Toggle("标记为已完成", isOn: $task.completed).accessibilityIdentifier("editor-completed")
        }
      }.formStyle(.grouped).scrollContentBackground(.hidden)

      HStack(spacing: 14) {
        Text("⌘↩ 保存")
          .font(.system(size: 10)).foregroundStyle(.secondary)
        Spacer()
        Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("保存") { save() }.buttonStyle(FlowdayButtonStyle(primary: true))
          .keyboardShortcut(.return, modifiers: [.command])
          .disabled(
            task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.readOnly
          )
          .accessibilityIdentifier("editor-save")
      }.padding(20)
    }
    .frame(width: 530, height: 560)
    .background(FlowdayStyle.canvas)
    .onAppear { titleFocused = true }
  }

  private func save() {
    task.tags = TaskLogic.tags(from: tags)
    task.dueDate = hasDate ? TaskDates.day(date) : nil
    task.dueTime = hasDate && hasTime ? TaskDates.time(date) : nil
    if store.saveTask(task) { dismiss() }
  }
}

struct DeadlineOptions: View {
  @Binding var hasDate: Bool
  @Binding var hasTime: Bool
  @Binding var date: Date

  var body: some View {
    Toggle("设置截止日期", isOn: $hasDate).accessibilityIdentifier("has-deadline")
    if hasDate {
      DatePicker("日期", selection: $date, displayedComponents: .date)
        .datePickerStyle(.compact).accessibilityIdentifier("due-date")
      Toggle("指定时间", isOn: $hasTime)
      if hasTime {
        DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute)
          .accessibilityIdentifier("due-time")
      }
    }
    HStack(spacing: 14) {
      Button("2 小时后") { apply(Date().addingTimeInterval(7200)) }
      Button("今天 18:00") {
        apply(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date())
      }
      Button("明天 10:00") {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        apply(
          Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? tomorrow)
      }
    }.buttonStyle(.link).font(.system(size: 11)).padding(.vertical, 3)
  }

  private func apply(_ value: Date) {
    date = value
    hasDate = true
    hasTime = true
  }
}

struct QuickAddView: View {
  let store: TaskStore
  @State private var title = ""
  @State private var priority: Priority = .medium
  @State private var category: TaskCategory = .work
  @State private var tags = ""
  @State private var hasDate = true
  @State private var hasTime = true
  /// nil means "follow the default deadline", which is recomputed from the current time so it
  /// never goes stale (past 18:00, or overnight while the app stays open).
  @State private var customDate: Date?
  @State private var datePopover = false
  @State private var optionsExpanded = false
  @FocusState private var titleFocused: Bool

  private var date: Date { customDate ?? TaskDates.defaultDeadline(now: store.now) }
  private var dateBinding: Binding<Date> {
    Binding(get: { date }, set: { customDate = $0 })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "plus").font(.system(size: 14)).foregroundStyle(
          FlowdayStyle.muted)
        TextField("添加一件待办，回车保存…", text: $title)
          .textFieldStyle(.plain).font(.system(size: 13)).focused($titleFocused).onSubmit { add() }
          .accessibilityIdentifier("quick-title")
        Button {
          optionsExpanded.toggle()
        } label: {
          HStack(spacing: 4) {
            Text("任务选项")
            Image(systemName: optionsExpanded ? "chevron.up" : "chevron.down")
              .font(.system(size: 9, weight: .semibold))
          }.font(.system(size: 11)).fixedSize()
        }.buttonStyle(.plain).foregroundStyle(.secondary)
          .help("设置优先级、分类、截止时间和标签")
          .accessibilityLabel("任务选项")
          .accessibilityValue(optionsExpanded ? "已展开" : "已收起")
          .accessibilityIdentifier("quick-options")
        Button("添加") { add() }.buttonStyle(FlowdayButtonStyle(primary: true))
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.readOnly)
          .accessibilityIdentifier("quick-add")
      }
      if optionsExpanded {
        Divider()
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) {
            options
            tagsField.frame(width: 160)
          }
          VStack(alignment: .leading, spacing: 10) {
            options
            tagsField
          }
        }
      }
    }
    .padding(10)
    .background(FlowdayStyle.surface, in: RoundedRectangle(cornerRadius: 7))
    .overlay(
      RoundedRectangle(cornerRadius: 7)
        .strokeBorder(
          titleFocused ? FlowdayStyle.accent : FlowdayStyle.border,
          lineWidth: titleFocused ? 1.5 : 1))
  }

  private var options: some View {
    HStack(spacing: 12) {
      Picker("优先级", selection: $priority) {
        ForEach(Priority.allCases) { value in Text(value.label).tag(value) }
      }.labelsHidden().frame(width: 95)
      Picker("分类", selection: $category) {
        ForEach(TaskCategory.allCases) { value in Text(value.rawValue).tag(value) }
      }.labelsHidden().frame(width: 80)
      Button {
        datePopover.toggle()
      } label: {
        Label(
          hasDate
            ? TaskDates.dueLabel(
              TaskItem(
                title: "", dueDate: TaskDates.day(date),
                dueTime: hasTime ? TaskDates.time(date) : nil, completed: true), now: store.now)
            : "无截止日期", systemImage: "calendar"
        )
        .font(.system(size: 11)).lineLimit(1)
      }.buttonStyle(.plain).foregroundStyle(.secondary).help("设置截止日期")
        .popover(isPresented: $datePopover) {
          Form { DeadlineOptions(hasDate: $hasDate, hasTime: $hasTime, date: dateBinding) }
            .formStyle(.grouped).frame(width: 340, height: 270).padding(6)
        }
    }.controlSize(.small)
  }

  private var tagsField: some View {
    HStack(spacing: 5) {
      Image(systemName: "number").foregroundStyle(.tertiary)
      TextField("标签（可选）", text: $tags).textFieldStyle(.plain).onSubmit { add() }
        .accessibilityIdentifier("quick-tags")
    }.font(.system(size: 11))
  }

  private func add() {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let date = customDate ?? TaskDates.defaultDeadline(now: Date())
    let task = TaskItem(
      title: title, priority: priority, category: category,
      dueDate: hasDate ? TaskDates.day(date) : nil,
      dueTime: hasDate && hasTime ? TaskDates.time(date) : nil,
      tags: TaskLogic.tags(from: tags))
    if store.saveTask(task) {
      title = ""
      tags = ""
      customDate = nil
    }
  }
}

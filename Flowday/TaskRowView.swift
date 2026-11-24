import SwiftUI

struct TaskRowView: View {
  let task: TaskItem
  let store: TaskStore
  let onDelete: () -> Void
  @State private var hovered = false
  @State private var targeted = false

  private var urgency: DeadlineUrgency {
    task.urgency(at: store.now, hours: store.settings.reminderHours)
  }
  private var pending: [TaskItem] { store.visibleTasks.filter { !$0.completed } }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if !task.completed {
        Image(systemName: "line.3.horizontal")
          .font(.system(size: 9)).foregroundStyle(FlowdayStyle.muted.opacity(hovered ? 0.85 : 0.4))
          .frame(width: 10, height: 18)
          .draggable(task.id).help("拖动调整顺序")
          .accessibilityLabel("拖动任务排序")
      }
      Button {
        store.toggle(task.id)
      } label: {
        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 16, weight: .regular))
          .foregroundStyle(
            task.completed ? FlowdayStyle.success : FlowdayStyle.muted.opacity(0.7)
          )
          .frame(width: 18, height: 18)
      }.buttonStyle(.plain)
        .help(task.completed ? "恢复为待办" : "标记完成")
        .accessibilityLabel(task.completed ? "恢复为待办：" + task.title : "完成任务：" + task.title)
        .accessibilityIdentifier("toggle-\(task.id)")

      VStack(alignment: .leading, spacing: 6) {
        Button {
          store.edit(task)
        } label: {
          Text(task.title).font(.system(size: 12, weight: .medium))
            .strikethrough(task.completed).foregroundStyle(
              task.completed ? FlowdayStyle.muted : FlowdayStyle.ink
            )
            .multilineTextAlignment(.leading).lineLimit(2).frame(
              maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).help(task.title).accessibilityIdentifier("task-title-\(task.id)")
        if !task.tagList.isEmpty || !(task.note ?? "").isEmpty {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
              tagButtons
              note
            }
            VStack(alignment: .leading, spacing: 4) {
              tagButtons
              note
            }
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 1)

      VStack(alignment: .trailing, spacing: 6) {
        if task.completed, let completedAt = task.completedAt {
          Text(completedAt, format: .dateTime.hour().minute()).foregroundStyle(FlowdayStyle.muted)
        } else {
          Text(TaskDates.dueLabel(task, now: store.now))
            .foregroundStyle(
              urgency == .overdue
                ? Color.red : urgency == .soon ? FlowdayStyle.warning : FlowdayStyle.muted)
        }
        HStack(spacing: 8) {
          category
          Label(task.priority.label, systemImage: task.priority == .high ? "flag.fill" : "flag")
            .foregroundStyle(task.priority == .high ? FlowdayStyle.warning : FlowdayStyle.muted)
        }
        if let snooze = task.snoozedUntil, snooze > store.now {
          Label("已延后提醒", systemImage: "bell.slash").foregroundStyle(FlowdayStyle.muted)
        }
      }.font(.system(size: 10)).multilineTextAlignment(.trailing).lineLimit(2).frame(
        minWidth: 96, idealWidth: 112, maxWidth: 122, alignment: .trailing
      ).padding(.top, 2)

      Menu {
        actions
      } label: {
        Image(systemName: "ellipsis").foregroundStyle(FlowdayStyle.muted)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18).padding(.top, 1)
      .accessibilityLabel("任务操作：" + task.title).accessibilityIdentifier("actions-\(task.id)")
    }
    .padding(.horizontal, 12).padding(.vertical, 11)
    .background(
      targeted
        ? FlowdayStyle.selection : hovered ? FlowdayStyle.hover : .clear,
      in: RoundedRectangle(cornerRadius: 4)
    )
    .onHover { hovered = $0 }
    .contextMenu { actions }
    .dropDestination(for: String.self) { values, _ in
      guard !task.completed, let source = values.first else { return false }
      return store.reorder(source, before: task.id)
    } isTargeted: {
      targeted = $0 && !task.completed
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("task-row-\(task.id)")
  }

  private var category: some View {
    Text(task.category.rawValue)
      .font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted)
      .padding(.horizontal, 5).padding(.vertical, 1)
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(FlowdayStyle.border, lineWidth: 1))
  }

  @ViewBuilder private var note: some View {
    if let note = task.note, !note.isEmpty {
      Text(note).font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted).lineLimit(1).help(
        note)
    }
  }

  private var tagButtons: some View {
    HStack(spacing: 6) {
      ForEach(Array(task.tagList.prefix(3)), id: \.self) { tag in
        Button("#" + tag) { store.filter.tag = store.filter.tag == tag ? nil : tag }
          .buttonStyle(.plain).font(.system(size: 10))
          .foregroundStyle(store.filter.tag == tag ? FlowdayStyle.accent : FlowdayStyle.muted)
          .lineLimit(1)
      }
      if task.tagList.count > 3 {
        Text("+\(task.tagList.count - 3)").font(.system(size: 10)).foregroundStyle(
          FlowdayStyle.muted)
      }
    }
  }

  @ViewBuilder private var actions: some View {
    Button("编辑任务") { store.edit(task) }
    Button(task.completed ? "恢复为待办" : "标记完成") { store.toggle(task.id) }
    if !task.completed {
      if task.dueDate != nil { Button("1 小时后提醒") { store.snooze(task.id) } }
      if let index = pending.firstIndex(where: { $0.id == task.id }) {
        Button("上移") { store.reorder(task.id, before: pending[index - 1].id) }.disabled(index == 0)
        Button("下移") { store.reorder(task.id, before: pending[index + 1].id, after: true) }
          .disabled(index == pending.count - 1)
      }
    }
    Divider()
    Button("删除任务", role: .destructive, action: onDelete)
  }
}

import SwiftUI

enum CompletionCalendarLogic {
  static func monthStart(for date: Date, calendar: Calendar = .current) -> Date {
    calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
  }

  static func days(in month: Date, calendar: Calendar = .current) -> [Date?] {
    let start = monthStart(for: month, calendar: calendar)
    guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
    let leading = (calendar.component(.weekday, from: start) + 5) % 7
    var result = [Date?](repeating: nil, count: leading)
    result += range.map { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    result += [Date?](repeating: nil, count: (7 - result.count % 7) % 7)
    return result
  }

  static func shiftedMonth(_ month: Date, by offset: Int, calendar: Calendar = .current) -> Date {
    let start = monthStart(for: month, calendar: calendar)
    return calendar.date(byAdding: .month, value: offset, to: start) ?? start
  }

  static func completedTasks(_ tasks: [TaskItem], on day: Date, calendar: Calendar = .current)
    -> [TaskItem]
  {
    TaskLogic.sorted(
      tasks.filter {
        $0.completed && $0.completedAt.map { calendar.isDate($0, inSameDayAs: day) } == true
      }, by: .createdAt, calendar: calendar)
  }
}

struct CompletionCalendarView: View {
  let tasks: [TaskItem]
  let now: Date
  @Binding var month: Date
  let selectedDate: Date?
  let onSelect: (Date) -> Void
  @State private var hoveredDate: Date?

  var body: some View {
    let days = CompletionCalendarLogic.days(in: month)
    let counts = TaskLogic.completionCounts(tasks)
    let monthCounts = days.compactMap { date in date.map { counts[TaskDates.day($0)] ?? 0 } }
    VStack(alignment: .leading, spacing: 14) {
      monthHeader

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4)
      {
        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
          Text(weekday).font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted)
            .frame(maxWidth: .infinity).padding(.bottom, 6).accessibilityHidden(true)
        }
        ForEach(Array(days.enumerated()), id: \.offset) { _, date in
          if let date {
            dayButton(date, count: counts[TaskDates.day(date)] ?? 0)
          } else {
            Color.clear.frame(height: 37).accessibilityHidden(true)
          }
        }
      }

      Rectangle().fill(FlowdayStyle.border).frame(height: 1)
      HStack(alignment: .firstTextBaseline) {
        summary("本月完成", value: monthCounts.reduce(0, +), unit: "项")
        Spacer(minLength: 12)
        summary("有记录", value: monthCounts.filter { $0 > 0 }.count, unit: "天")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("completion-calendar")
  }

  private var monthHeader: some View {
    HStack(spacing: 5) {
      Text(month, format: .dateTime.year().month(.wide))
        .font(.system(size: 13, weight: .semibold)).foregroundStyle(FlowdayStyle.ink)
        .accessibilityIdentifier("calendar-month")
      Spacer(minLength: 3)
      Button("本月") {
        month = CompletionCalendarLogic.monthStart(for: now)
      }
      .font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted)
      .buttonStyle(.plain).padding(.horizontal, 4).frame(height: 25)
      .help("回到本月").accessibilityIdentifier("calendar-current-month")
      monthButton("chevron.left", label: "上个月", offset: -1, id: "calendar-previous-month")
      monthButton("chevron.right", label: "下个月", offset: 1, id: "calendar-next-month")
    }
  }

  private func monthButton(_ symbol: String, label: String, offset: Int, id: String) -> some View {
    Button {
      month = CompletionCalendarLogic.shiftedMonth(month, by: offset)
    } label: {
      Image(systemName: symbol).font(.system(size: 10, weight: .medium))
        .foregroundStyle(FlowdayStyle.muted).frame(width: 24, height: 25)
        .background(FlowdayStyle.surface, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(FlowdayStyle.border, lineWidth: 1))
    }
    .buttonStyle(.plain).help(label).accessibilityLabel(label).accessibilityIdentifier(id)
  }

  private func dayButton(_ date: Date, count: Int) -> some View {
    let selected = selectedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true
    let today = Calendar.current.isDate(date, inSameDayAs: now)
    return Button {
      onSelect(date)
    } label: {
      VStack(spacing: 2) {
        Text("\(Calendar.current.component(.day, from: date))")
          .font(.system(size: 11, weight: selected || today ? .semibold : .regular))
          .foregroundStyle(
            selected ? Color.white : today ? FlowdayStyle.accent : FlowdayStyle.ink)
        Text(count > 0 ? "\(count)" : " ")
          .font(.system(size: 8, weight: .medium))
          .foregroundStyle(selected ? Color.white : FlowdayStyle.accent)
      }
      .monospacedDigit().frame(maxWidth: .infinity).frame(height: 37)
      .background(
        selected
          ? FlowdayStyle.primaryButton
          : hoveredDate == date
            ? FlowdayStyle.hover : count > 0 ? FlowdayStyle.accent.opacity(0.08) : .clear,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(today && !selected ? FlowdayStyle.accent : .clear, lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .onHover { hoveredDate = $0 ? date : nil }
    .help("\(TaskDates.heading(date, now: now)) · 完成 \(count) 项")
    .accessibilityLabel("\(TaskDates.day(date))，完成 \(count) 项" + (today ? "，今天" : ""))
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("completion-day-\(TaskDates.day(date))")
  }

  private func summary(_ title: String, value: Int, unit: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text("\(value)").font(.system(size: 17, weight: .semibold)).monospacedDigit()
          .foregroundStyle(FlowdayStyle.ink)
        Text(unit).font(.system(size: 10)).foregroundStyle(FlowdayStyle.muted)
      }
    }.accessibilityElement(children: .combine)
  }
}

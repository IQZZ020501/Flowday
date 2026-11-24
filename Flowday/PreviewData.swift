import Foundation

enum PreviewData {
  static func tasks(now: Date = Date()) -> [TaskItem] {
    let calendar = Calendar.current
    let overdue = now.addingTimeInterval(-5400)
    let soon = now.addingTimeInterval(7200)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
    let later = calendar.date(byAdding: .day, value: 3, to: now) ?? now
    var result: [TaskItem] = [
      TaskItem(
        id: "sample-review", title: "整理本周项目进展", note: "补充已完成事项和下一步安排。", priority: .high,
        category: .work, dueDate: TaskDates.day(soon), dueTime: TaskDates.time(soon),
        createdAt: now.addingTimeInterval(-3600), tags: ["周报", "项目"]),
      TaskItem(
        id: "sample-reply", title: "回复待确认的设计意见", priority: .high, category: .work,
        dueDate: TaskDates.day(overdue), dueTime: TaskDates.time(overdue),
        createdAt: now.addingTimeInterval(-86400), tags: ["设计"]),
      TaskItem(
        id: "sample-reading", title: "读完一章 SwiftUI 笔记", note: "试着用原生控件实现一个小页面。", priority: .medium,
        category: .study, dueDate: TaskDates.day(tomorrow), dueTime: "10:00",
        tags: ["阅读", "SwiftUI"]),
      TaskItem(id: "sample-walk", title: "傍晚散步半小时", priority: .low, category: .life, tags: ["运动"]),
      TaskItem(
        id: "sample-files", title: "整理照片与文件备份", priority: .medium, category: .personal,
        dueDate: TaskDates.day(later), tags: ["整理"]),
      TaskItem(
        id: "sample-done-today", title: "列出本周的三件重要事项", priority: .medium, category: .personal,
        completed: true, createdAt: now.addingTimeInterval(-10800),
        completedAt: now.addingTimeInterval(-1800), tags: ["计划"]),
    ]
    for offset in 1...5 {
      let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
      result.append(
        TaskItem(
          id: "sample-history-\(offset)",
          title: ["完成日常阅读", "整理书桌", "复盘学习笔记", "整理项目资料", "完成每周运动"][offset - 1],
          priority: .low, category: offset % 2 == 0 ? .life : .study,
          completed: true, createdAt: date.addingTimeInterval(-3600), completedAt: date))
    }
    return result
  }
}

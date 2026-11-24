import Foundation
import Observation
import UserNotifications

struct ReminderPlan: Equatable {
  var identifier: String
  var taskID: String
  var title: String
  var body: String
  var date: Date

  static func make(tasks: [TaskItem], hours: Int, now: Date) -> [Self] {
    var plans: [Self] = []
    for task in tasks where !task.completed {
      guard let due = task.deadline() else { continue }
      let base = "daylight.\(task.id).\(Int(due.timeIntervalSince1970))"
      let body = "[\(task.priority.label)] \(task.title)"
      if let snooze = task.snoozedUntil {
        plans.append(
          .init(
            identifier: "\(base).snooze.\(Int(snooze.timeIntervalSince1970))", taskID: task.id,
            title: "Flowday · 延后提醒", body: body, date: max(snooze, now.addingTimeInterval(2))))
      } else if due > now {
        plans.append(
          .init(
            identifier: base + ".soon", taskID: task.id, title: "Flowday · 截止日期临近",
            body: body,
            date: max(due.addingTimeInterval(-Double(hours) * 3600), now.addingTimeInterval(2))))
      }
      if task.snoozedUntil == nil || task.snoozedUntil! < due {
        plans.append(
          .init(
            identifier: base + ".due", taskID: task.id, title: "Flowday · 任务已到期",
            body: body, date: max(due, now.addingTimeInterval(2))))
      }
    }
    return Array(plans.sorted { $0.date < $1.date }.prefix(64))
  }
}

@MainActor @Observable
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
  var status = "未开启"
  var errorMessage: String?
  private let center = UNUserNotificationCenter.current()
  private var generation = 0
  private let disabled: Bool
  private let historyKey = "daylight.notificationSchedule.v1"

  init(disabled: Bool = false) {
    self.disabled = disabled
    super.init()
    if !disabled { center.delegate = self }
  }

  func requestPermission() async -> Bool {
    guard !disabled else { return false }
    do {
      let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      status = allowed ? "已开启" : "请在系统设置中允许通知"
      return allowed
    } catch {
      status = "开启失败"
      errorMessage = error.localizedDescription
      return false
    }
  }

  func refresh() async {
    guard !disabled else { return }
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional: status = "已允许"
    case .denied: status = "系统已禁用通知"
    default: status = "未开启"
    }
  }

  func synchronize(tasks: [TaskItem], settings: AppSettings, now: Date) async {
    guard !disabled else { return }
    generation += 1
    let current = generation
    let authorization = await center.notificationSettings().authorizationStatus
    guard current == generation, !Task.isCancelled else { return }
    let permitted = authorization == .authorized || authorization == .provisional
    let plans =
      settings.notificationsEnabled && permitted
      ? ReminderPlan.make(tasks: tasks, hours: settings.reminderHours, now: now) : []
    let pending = await center.pendingNotificationRequests()
    let delivered = await center.deliveredNotifications()
    guard current == generation, !Task.isCancelled else { return }
    let expected = Set(plans.map(\.identifier))
    let obsolete = pending.filter {
      $0.identifier.hasPrefix("daylight.") && !expected.contains($0.identifier)
    }.map(\.identifier)
    center.removePendingNotificationRequests(withIdentifiers: obsolete)
    let activeIDs = Set(tasks.filter { !$0.completed }.map(\.id))
    let obsoleteDelivered = delivered.filter {
      guard $0.request.identifier.hasPrefix("daylight.") else { return false }
      return !settings.notificationsEnabled
        || !activeIDs.contains($0.request.content.userInfo["taskID"] as? String ?? "")
    }.map { $0.request.identifier }
    center.removeDeliveredNotifications(withIdentifiers: obsoleteDelivered)
    let deliveredIDs = Set(delivered.map { $0.request.identifier })
    let pendingIDs = Set(pending.map(\.identifier))
    var scheduled = UserDefaults.standard.dictionary(forKey: historyKey) as? [String: Double] ?? [:]
    for plan in plans where !deliveredIDs.contains(plan.identifier) {
      guard current == generation, !Task.isCancelled else { return }
      // A past scheduled alert may already have been dismissed by the user.
      if let previous = scheduled[plan.identifier], previous <= now.timeIntervalSince1970,
        !pendingIDs.contains(plan.identifier)
      {
        continue
      }
      let content = UNMutableNotificationContent()
      content.title = plan.title
      content.body = plan.body
      content.sound = .default
      content.userInfo = ["taskID": plan.taskID]
      var components = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: plan.date)
      components.timeZone = .current
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      do {
        try await center.add(
          UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
        scheduled[plan.identifier] = plan.date.timeIntervalSince1970
        UserDefaults.standard.set(scheduled, forKey: historyKey)
      } catch { errorMessage = "提醒未能安排：" + error.localizedDescription }
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}

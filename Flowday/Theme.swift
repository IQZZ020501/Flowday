import SwiftUI

enum FlowdayStyle {
  static let accent = adaptive(light: 0x5E5CE6, dark: 0xA4A0FF)
  static let primaryButton = adaptive(light: 0x5E5CE6, dark: 0x6965DB)
  static let selection = adaptive(light: 0xE9E9F0, dark: 0x30303D)
  static let canvas = adaptive(light: 0xFCFCFD, dark: 0x1B1C22)
  static let sidebar = adaptive(light: 0xF3F3F6, dark: 0x17181D)
  static let surface = adaptive(light: 0xFFFFFF, dark: 0x23242B)
  static let border = adaptive(light: 0xE4E4EA, dark: 0x34353E)
  static let hover = adaptive(light: 0xF0F0F5, dark: 0x282932)
  static let ink = adaptive(light: 0x282932, dark: 0xECECF1)
  static let muted = adaptive(light: 0x6D6E7C, dark: 0xA0A1AF)
  static let success = adaptive(light: 0x31785B, dark: 0x7DBE9E)
  static let warning = adaptive(light: 0x996A1C, dark: 0xD8AD64)

  private static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(
          srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
          green: CGFloat((value >> 8) & 0xFF) / 255,
          blue: CGFloat(value & 0xFF) / 255, alpha: 1)
      })
  }
}

extension AppTheme {
  var scheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

struct FlowdayButtonStyle: ButtonStyle {
  var primary = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 11).padding(.vertical, 7)
      .foregroundStyle(primary && isEnabled ? Color.white : FlowdayStyle.muted)
      .background(
        primary && isEnabled ? FlowdayStyle.primaryButton : FlowdayStyle.surface,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(primary && isEnabled ? Color.clear : FlowdayStyle.border, lineWidth: 1)
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.55)
  }
}

extension Priority {
  var color: Color {
    switch self {
    case .high: .red
    case .medium: .orange
    case .low: .secondary
    }
  }
}

struct HeatmapView: View {
  let tasks: [TaskItem]
  let now: Date
  var compact = false

  private var dates: [Date] {
    (-27...0).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: now) }
  }

  var body: some View {
    let counts = TaskLogic.completionCounts(tasks)
    VStack(alignment: .leading, spacing: compact ? 8 : 14) {
      HStack {
        Text(compact ? "最近 28 天" : "完成足迹").font(.system(size: compact ? 11 : 14, weight: .medium))
        Spacer()
        Text("\(dates.reduce(0) { $0 + (counts[TaskDates.day($1)] ?? 0) }) 项")
          .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
      }
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: compact ? 5 : 8), count: compact ? 7 : 14),
        spacing: compact ? 5 : 8
      ) {
        ForEach(dates, id: \.self) { date in
          let count = counts[TaskDates.day(date)] ?? 0
          ZStack {
            RoundedRectangle(cornerRadius: compact ? 3 : 6)
              .fill(
                count == 0
                  ? FlowdayStyle.hover
                  : count >= 3
                    ? FlowdayStyle.primaryButton
                    : FlowdayStyle.accent.opacity(0.12 + Double(count) * 0.12))
            if !compact {
              Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 11)).foregroundStyle(
                  count >= 3 ? Color.white : FlowdayStyle.ink)
            }
          }
          .frame(height: compact ? 13 : 30)
          .help("\(TaskDates.heading(date, now: now))：完成 \(count) 项")
          .accessibilityLabel("\(TaskDates.day(date))，完成 \(count) 项")
        }
      }
      if !compact {
        HStack(spacing: 5) {
          Text("每一件完成的小事，都算数。")
          Spacer()
          Text("少")
          ForEach([0.10, 0.30, 0.60, 1.0], id: \.self) { value in
            RoundedRectangle(cornerRadius: 2).fill(FlowdayStyle.accent.opacity(value)).frame(
              width: 9, height: 9)
          }
          Text("多")
        }.font(.system(size: 10)).foregroundStyle(.secondary)
      }
    }
  }
}

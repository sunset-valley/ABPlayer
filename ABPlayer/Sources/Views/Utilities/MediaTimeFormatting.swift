import Foundation

enum MediaTimeFormatting {
  static func clock(from seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else {
      return "0:00"
    }

    let totalSeconds = Int(seconds.rounded())
    let minutes = totalSeconds / 60
    let remainingSeconds = totalSeconds % 60

    if minutes >= 60 {
      let hours = minutes / 60
      let remainingMinutes = minutes % 60
      return String(format: "%d:%02d:%02d", hours, remainingMinutes, remainingSeconds)
    }

    return String(format: "%d:%02d", minutes, remainingSeconds)
  }
}

@MainActor
enum RelativeTimeFormatting {
  private static let shortFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
  }()

  static func short(from date: Date) -> String {
    shortFormatter.localizedString(for: date, relativeTo: .now)
  }
}

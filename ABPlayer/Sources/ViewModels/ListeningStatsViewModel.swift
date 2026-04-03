import Foundation
import Observation

@Observable
@MainActor
final class ListeningStatsViewModel {
  enum Range: String, CaseIterable, Hashable, Identifiable {
    case last7Days
    case last30Days
    case month

    var id: String { rawValue }

    var dayCount: Int {
      switch self {
      case .last7Days:
        return 7
      case .last30Days:
        return 30
      case .month:
        return 0
      }
    }

    var title: String {
      switch self {
      case .last7Days:
        return "7 Days"
      case .last30Days:
        return "30 Days"
      case .month:
        return "Month"
      }
    }
  }

  struct Input {
    enum Event {
      case onAppear
      case refresh
      case selectRange(Range)
      case previousMonth
      case nextMonth
    }

    let event: Event
  }

  struct SessionRow: Identifiable, Hashable {
    let id: String
    let timeRangeText: String
    let durationText: String
    let duration: Double
    let isOngoing: Bool
  }

  struct SessionSection: Identifiable, Hashable {
    let dayStart: Date
    let title: String
    let subtitle: String
    let totalDuration: Double
    let totalDurationText: String
    let rows: [SessionRow]

    var id: Date {
      dayStart
    }
  }

  struct Output {
    let selectedRange: Range
    let chartStats: [DailyListeningStat]
    let sessionSections: [SessionSection]
    let sessionSliceCount: Int
    let totalSessionDuration: Double
    let averageSessionDuration: Double
    let monthTitle: String
    let canGoToNextMonth: Bool
    let showsTrendEmptyState: Bool
    let showsSessionsEmptyState: Bool
  }

  @ObservationIgnored
  private var statsService: ListeningStatsService?
  private var calendar: Calendar
  private var selectedMonthStart: Date

  private var selectedRange: Range = .last7Days
  private(set) var output: Output

  init(calendar: Calendar = .autoupdatingCurrent) {
    self.calendar = calendar
    if let interval = calendar.dateInterval(of: .month, for: Date()) {
      selectedMonthStart = interval.start
    } else {
      selectedMonthStart = calendar.startOfDay(for: Date())
    }

    output = Output(
      selectedRange: .last7Days,
      chartStats: [],
      sessionSections: [],
      sessionSliceCount: 0,
      totalSessionDuration: 0,
      averageSessionDuration: 0,
      monthTitle: "",
      canGoToNextMonth: false,
      showsTrendEmptyState: true,
      showsSessionsEmptyState: true
    )
  }

  func configureIfNeeded(statsService: ListeningStatsService) {
    if self.statsService == nil {
      self.statsService = statsService
    }
  }

  var activeCalendar: Calendar {
    calendar
  }

  @discardableResult
  func transform(input: Input) -> Output {
    switch input.event {
    case .onAppear, .refresh:
      reload()
    case .selectRange(let range):
      selectedRange = range
      reload()
    case .previousMonth:
      guard selectedRange == .month else { break }
      guard let previous = calendar.date(byAdding: .month, value: -1, to: selectedMonthStart) else { break }
      selectedMonthStart = startOfMonth(for: previous)
      reload()
    case .nextMonth:
      guard selectedRange == .month else { break }
      guard canGoToNextMonth else { break }
      guard let next = calendar.date(byAdding: .month, value: 1, to: selectedMonthStart) else { break }
      selectedMonthStart = startOfMonth(for: next)
      reload()
    }

    return output
  }

  private func reload() {
    guard let statsService else {
      output = Output(
        selectedRange: selectedRange,
        chartStats: [],
        sessionSections: [],
        sessionSliceCount: 0,
        totalSessionDuration: 0,
        averageSessionDuration: 0,
        monthTitle: monthTitle,
        canGoToNextMonth: false,
        showsTrendEmptyState: true,
        showsSessionsEmptyState: true
      )
      return
    }

    let stats: [DailyListeningStat]
    let sessionSlices: [ListeningSessionSlice]
    switch selectedRange {
    case .last7Days, .last30Days:
      stats = statsService.dailyStats(days: selectedRange.dayCount, calendar: calendar)
      sessionSlices = statsService.sessionSlices(days: selectedRange.dayCount, calendar: calendar)
    case .month:
      stats = statsService.monthlyStats(for: selectedMonthStart, calendar: calendar)
      sessionSlices = statsService.monthlySessionSlices(for: selectedMonthStart, calendar: calendar)
    }

    let showsTrendEmptyState: Bool
    switch selectedRange {
    case .month:
      showsTrendEmptyState = false
    case .last7Days, .last30Days:
      showsTrendEmptyState = stats.allSatisfy { $0.duration <= 0 }
    }

    let sessionSections = makeSessionSections(from: sessionSlices)
    let totalSessionDuration = sessionSlices.reduce(0) { $0 + $1.duration }
    let sessionSliceCount = sessionSlices.count
    let averageSessionDuration = sessionSliceCount > 0
      ? totalSessionDuration / Double(sessionSliceCount)
      : 0

    output = Output(
      selectedRange: selectedRange,
      chartStats: stats,
      sessionSections: sessionSections,
      sessionSliceCount: sessionSliceCount,
      totalSessionDuration: totalSessionDuration,
      averageSessionDuration: averageSessionDuration,
      monthTitle: monthTitle,
      canGoToNextMonth: canGoToNextMonth,
      showsTrendEmptyState: showsTrendEmptyState,
      showsSessionsEmptyState: sessionSlices.isEmpty
    )
  }

  private func makeSessionSections(from slices: [ListeningSessionSlice]) -> [SessionSection] {
    let groupedByDay = Dictionary(grouping: slices, by: { $0.dayStart })

    return groupedByDay.keys.sorted(by: >).map { dayStart in
      let rows = groupedByDay[dayStart, default: []]
        .sorted { lhs, rhs in
          if lhs.startedAt == rhs.startedAt {
            return lhs.endedAt > rhs.endedAt
          }
          return lhs.startedAt > rhs.startedAt
        }
        .map(makeSessionRow(from:))

      let totalDuration = rows.reduce(0) { $0 + $1.duration }

      return SessionSection(
        dayStart: dayStart,
        title: dayStart.formatted(.dateTime.month(.abbreviated).day()),
        subtitle: dayStart.formatted(.dateTime.weekday(.wide)),
        totalDuration: totalDuration,
        totalDurationText: readableDurationLabel(seconds: totalDuration),
        rows: rows
      )
    }
  }

  private func makeSessionRow(from slice: ListeningSessionSlice) -> SessionRow {
    let startText = slice.startedAt.formatted(.dateTime.hour().minute())
    let endText = slice.isOngoing ? "Now" : slice.endedAt.formatted(.dateTime.hour().minute())

    return SessionRow(
      id: slice.id,
      timeRangeText: "\(startText) - \(endText)",
      durationText: readableDurationLabel(seconds: slice.duration),
      duration: slice.duration,
      isOngoing: slice.isOngoing
    )
  }

  private func readableDurationLabel(seconds: Double) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainingSeconds = totalSeconds % 60

    if hours > 0 {
      return "\(hours)h \(minutes)m \(remainingSeconds)s"
    }

    if minutes > 0 {
      return "\(minutes)m \(remainingSeconds)s"
    }

    return "\(remainingSeconds)s"
  }

  private var currentMonthStart: Date {
    startOfMonth(for: Date())
  }

  private var canGoToNextMonth: Bool {
    selectedMonthStart < currentMonthStart
  }

  private var monthTitle: String {
    selectedMonthStart.formatted(.dateTime.month(.wide).year())
  }

  private func startOfMonth(for date: Date) -> Date {
    if let interval = calendar.dateInterval(of: .month, for: date) {
      return interval.start
    }
    return calendar.startOfDay(for: date)
  }
}

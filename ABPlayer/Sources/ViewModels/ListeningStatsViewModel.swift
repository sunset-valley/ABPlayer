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

  struct Output {
    let selectedRange: Range
    let chartStats: [DailyListeningStat]
    let monthTitle: String
    let canGoToNextMonth: Bool
    let showsEmptyState: Bool
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
      monthTitle: "",
      canGoToNextMonth: false,
      showsEmptyState: true
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
        monthTitle: monthTitle,
        canGoToNextMonth: false,
        showsEmptyState: true
      )
      return
    }

    let stats: [DailyListeningStat]
    switch selectedRange {
    case .last7Days, .last30Days:
      stats = statsService.dailyStats(days: selectedRange.dayCount, calendar: calendar)
    case .month:
      stats = statsService.monthlyStats(for: selectedMonthStart, calendar: calendar)
    }

    let showsEmptyState: Bool
    switch selectedRange {
    case .month:
      showsEmptyState = false
    case .last7Days, .last30Days:
      showsEmptyState = stats.allSatisfy { $0.duration <= 0 }
    }

    output = Output(
      selectedRange: selectedRange,
      chartStats: stats,
      monthTitle: monthTitle,
      canGoToNextMonth: canGoToNextMonth,
      showsEmptyState: showsEmptyState
    )
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

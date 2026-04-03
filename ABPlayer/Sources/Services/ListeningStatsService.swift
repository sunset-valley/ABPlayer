import Foundation
import Observation
import SwiftData

struct DailyListeningStat: Identifiable, Hashable {
  let dayStart: Date
  let duration: Double

  var id: Date {
    dayStart
  }
}

struct ListeningSessionSlice: Identifiable, Hashable {
  let sessionID: UUID
  let dayStart: Date
  let startedAt: Date
  let endedAt: Date
  let duration: Double
  let isOngoing: Bool

  var id: String {
    "\(sessionID.uuidString.lowercased())-\(Int(dayStart.timeIntervalSinceReferenceDate))"
  }
}

enum ListeningStatsAggregation {
  static func aggregate(
    sessions: [ListeningSession],
    days: Int,
    now: Date,
    calendar: Calendar
  ) -> [DailyListeningStat] {
    guard days > 0 else { return [] }

    let todayStart = calendar.startOfDay(for: now)
    guard
      let rangeStart = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart),
      let rangeEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)
    else {
      return []
    }

    return aggregate(
      sessions: sessions,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      now: now,
      calendar: calendar
    )
  }

  static func aggregate(
    sessions: [ListeningSession],
    rangeStart: Date,
    rangeEnd: Date,
    now: Date,
    calendar: Calendar
  ) -> [DailyListeningStat] {
    guard rangeEnd > rangeStart else { return [] }

    let dayStarts = dayStarts(in: rangeStart..<rangeEnd, calendar: calendar)
    guard !dayStarts.isEmpty else { return [] }

    var totalsByDayStart = Dictionary(uniqueKeysWithValues: dayStarts.map { ($0, 0.0) })

    for session in sessions {
      let sessionEnd = session.endedAt ?? now
      guard session.duration > 0 else { continue }
      guard sessionEnd > session.startedAt else { continue }

      let clampedStart = max(session.startedAt, rangeStart)
      let clampedEnd = min(sessionEnd, rangeEnd)
      guard clampedEnd > clampedStart else { continue }

      let sessionInterval = sessionEnd.timeIntervalSince(session.startedAt)
      guard sessionInterval > 0 else { continue }

      let clampedInterval = clampedEnd.timeIntervalSince(clampedStart)
      guard clampedInterval > 0 else { continue }

      let clampedDuration = session.duration * (clampedInterval / sessionInterval)

      var cursor = clampedStart
      while cursor < clampedEnd {
        let dayStart = calendar.startOfDay(for: cursor)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
          break
        }

        let segmentEnd = min(nextDayStart, clampedEnd)
        let segmentInterval = segmentEnd.timeIntervalSince(cursor)
        guard segmentInterval > 0 else { break }

        let segmentDuration = clampedDuration * (segmentInterval / clampedInterval)
        if totalsByDayStart[dayStart] != nil {
          totalsByDayStart[dayStart, default: 0] += segmentDuration
        }

        cursor = segmentEnd
      }
    }

    return dayStarts.map { dayStart in
      DailyListeningStat(dayStart: dayStart, duration: max(0, totalsByDayStart[dayStart, default: 0]))
    }
  }

  private static func dayStarts(in range: Range<Date>, calendar: Calendar) -> [Date] {
    var starts: [Date] = []
    var cursor = calendar.startOfDay(for: range.lowerBound)

    while cursor < range.upperBound {
      starts.append(cursor)
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
        break
      }
      cursor = next
    }

    return starts
  }
}

enum ListeningSessionSliceAggregation {
  static func slices(
    sessions: [ListeningSession],
    days: Int,
    now: Date,
    calendar: Calendar
  ) -> [ListeningSessionSlice] {
    guard days > 0 else { return [] }

    let todayStart = calendar.startOfDay(for: now)
    guard
      let rangeStart = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart),
      let rangeEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)
    else {
      return []
    }

    return slices(
      sessions: sessions,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      now: now,
      calendar: calendar
    )
  }

  static func slices(
    sessions: [ListeningSession],
    rangeStart: Date,
    rangeEnd: Date,
    now: Date,
    calendar: Calendar
  ) -> [ListeningSessionSlice] {
    guard rangeEnd > rangeStart else { return [] }

    var sessionSlices: [ListeningSessionSlice] = []

    for session in sessions {
      let sessionEnd = session.endedAt ?? now
      guard session.duration > 0 else { continue }
      guard sessionEnd > session.startedAt else { continue }

      let clampedStart = max(session.startedAt, rangeStart)
      let clampedEnd = min(sessionEnd, rangeEnd)
      guard clampedEnd > clampedStart else { continue }

      let sessionInterval = sessionEnd.timeIntervalSince(session.startedAt)
      guard sessionInterval > 0 else { continue }

      let clampedInterval = clampedEnd.timeIntervalSince(clampedStart)
      guard clampedInterval > 0 else { continue }

      let clampedDuration = session.duration * (clampedInterval / sessionInterval)
      let isSessionOngoing = session.endedAt == nil

      var cursor = clampedStart
      while cursor < clampedEnd {
        let dayStart = calendar.startOfDay(for: cursor)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
          break
        }

        let segmentEnd = min(nextDayStart, clampedEnd)
        let segmentInterval = segmentEnd.timeIntervalSince(cursor)
        guard segmentInterval > 0 else { break }

        let segmentDuration = clampedDuration * (segmentInterval / clampedInterval)
        let isOngoingSlice =
          isSessionOngoing
          && abs(segmentEnd.timeIntervalSince(now)) < 0.001

        sessionSlices.append(
          ListeningSessionSlice(
            sessionID: session.id,
            dayStart: dayStart,
            startedAt: cursor,
            endedAt: segmentEnd,
            duration: max(0, segmentDuration),
            isOngoing: isOngoingSlice
          )
        )

        cursor = segmentEnd
      }
    }

    return sessionSlices.sorted { lhs, rhs in
      if lhs.startedAt == rhs.startedAt {
        return lhs.endedAt < rhs.endedAt
      }
      return lhs.startedAt < rhs.startedAt
    }
  }
}

@Observable
@MainActor
final class ListeningStatsService {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  func dailyStats(
    days: Int,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
  ) -> [DailyListeningStat] {
    guard days > 0 else { return [] }

    let sessions = allSessions()
    return ListeningStatsAggregation.aggregate(
      sessions: sessions,
      days: days,
      now: now,
      calendar: calendar
    )
  }

  func monthlyStats(
    for monthDate: Date,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
  ) -> [DailyListeningStat] {
    guard let monthInterval = calendar.dateInterval(of: .month, for: monthDate) else {
      return []
    }

    let sessions = allSessions()
    return ListeningStatsAggregation.aggregate(
      sessions: sessions,
      rangeStart: monthInterval.start,
      rangeEnd: monthInterval.end,
      now: now,
      calendar: calendar
    )
  }

  func sessionSlices(
    days: Int,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
  ) -> [ListeningSessionSlice] {
    guard days > 0 else { return [] }

    let sessions = allSessions()
    return ListeningSessionSliceAggregation.slices(
      sessions: sessions,
      days: days,
      now: now,
      calendar: calendar
    )
  }

  func monthlySessionSlices(
    for monthDate: Date,
    now: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent
  ) -> [ListeningSessionSlice] {
    guard let monthInterval = calendar.dateInterval(of: .month, for: monthDate) else {
      return []
    }

    let sessions = allSessions()
    return ListeningSessionSliceAggregation.slices(
      sessions: sessions,
      rangeStart: monthInterval.start,
      rangeEnd: monthInterval.end,
      now: now,
      calendar: calendar
    )
  }

  private func allSessions() -> [ListeningSession] {
    let descriptor = FetchDescriptor<ListeningSession>(
      sortBy: [SortDescriptor(\ListeningSession.startedAt, order: .forward)]
    )
    return (try? modelContext.fetch(descriptor)) ?? []
  }
}

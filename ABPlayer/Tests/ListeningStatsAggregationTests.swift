import Foundation
import Testing

@testable import ABPlayerDev

struct ListeningStatsAggregationTests {
  private func makeCalendar(timeZone: TimeZone = TimeZone(secondsFromGMT: 0) ?? .gmt) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int = 0,
    calendar: Calendar
  ) -> Date {
    let components = DateComponents(
      calendar: calendar,
      timeZone: calendar.timeZone,
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second
    )

    return calendar.date(from: components) ?? .distantPast
  }

  private func monthRange(
    year: Int,
    month: Int,
    calendar: Calendar
  ) -> Range<Date> {
    let monthStart = makeDate(year: year, month: month, day: 1, hour: 0, minute: 0, calendar: calendar)
    let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
    return monthStart..<nextMonth
  }

  @Test
  func aggregateReturnsExpectedDayCountWithNoData() {
    let calendar = makeCalendar()
    let now = makeDate(year: 2026, month: 3, day: 28, hour: 12, minute: 0, calendar: calendar)

    let stats = ListeningStatsAggregation.aggregate(
      sessions: [],
      days: 7,
      now: now,
      calendar: calendar
    )

    #expect(stats.count == 7)
    #expect(stats.allSatisfy { $0.duration == 0 })
  }

  @Test
  func aggregateAssignsSameDaySessionToSingleDay() {
    let calendar = makeCalendar()
    let sessionStart = makeDate(year: 2026, month: 3, day: 28, hour: 10, minute: 0, calendar: calendar)
    let sessionEnd = makeDate(year: 2026, month: 3, day: 28, hour: 10, minute: 30, calendar: calendar)
    let now = makeDate(year: 2026, month: 3, day: 28, hour: 12, minute: 0, calendar: calendar)

    let session = ListeningSession(startedAt: sessionStart, endedAt: sessionEnd, duration: 1_800)

    let stats = ListeningStatsAggregation.aggregate(
      sessions: [session],
      days: 1,
      now: now,
      calendar: calendar
    )

    #expect(stats.count == 1)
    #expect(abs(stats[0].duration - 1_800) < 0.001)
  }

  @Test
  func aggregateSplitsCrossMidnightSessionProportionally() {
    let calendar = makeCalendar()
    let sessionStart = makeDate(year: 2026, month: 3, day: 27, hour: 23, minute: 50, calendar: calendar)
    let sessionEnd = makeDate(year: 2026, month: 3, day: 28, hour: 0, minute: 10, calendar: calendar)
    let now = makeDate(year: 2026, month: 3, day: 28, hour: 10, minute: 0, calendar: calendar)

    let session = ListeningSession(startedAt: sessionStart, endedAt: sessionEnd, duration: 1_200)

    let stats = ListeningStatsAggregation.aggregate(
      sessions: [session],
      days: 2,
      now: now,
      calendar: calendar
    )

    #expect(stats.count == 2)
    #expect(abs(stats[0].duration - 600) < 0.001)
    #expect(abs(stats[1].duration - 600) < 0.001)
  }

  @Test
  func aggregateClampsSessionOutsideRange() {
    let calendar = makeCalendar()
    let sessionStart = makeDate(year: 2026, month: 3, day: 20, hour: 10, minute: 0, calendar: calendar)
    let sessionEnd = makeDate(year: 2026, month: 3, day: 20, hour: 10, minute: 30, calendar: calendar)
    let now = makeDate(year: 2026, month: 3, day: 28, hour: 12, minute: 0, calendar: calendar)

    let session = ListeningSession(startedAt: sessionStart, endedAt: sessionEnd, duration: 1_800)

    let stats = ListeningStatsAggregation.aggregate(
      sessions: [session],
      days: 7,
      now: now,
      calendar: calendar
    )

    #expect(stats.count == 7)
    #expect(stats.allSatisfy { $0.duration == 0 })
  }

  @Test
  func aggregateUsesNowForOngoingSession() {
    let calendar = makeCalendar()
    let sessionStart = makeDate(year: 2026, month: 3, day: 28, hour: 11, minute: 0, calendar: calendar)
    let now = makeDate(year: 2026, month: 3, day: 28, hour: 12, minute: 0, calendar: calendar)

    let session = ListeningSession(startedAt: sessionStart, endedAt: nil, duration: 900)

    let stats = ListeningStatsAggregation.aggregate(
      sessions: [session],
      days: 1,
      now: now,
      calendar: calendar
    )

    #expect(stats.count == 1)
    #expect(abs(stats[0].duration - 900) < 0.001)
  }

  @Test
  func aggregateRangeForMarchHas31Days() {
    let calendar = makeCalendar()
    let range = monthRange(year: 2026, month: 3, calendar: calendar)
    let now = makeDate(year: 2026, month: 3, day: 15, hour: 12, minute: 0, calendar: calendar)

    let stats = ListeningStatsAggregation.aggregate(
      sessions: [],
      rangeStart: range.lowerBound,
      rangeEnd: range.upperBound,
      now: now,
      calendar: calendar
    )

    #expect(stats.count == 31)
    #expect(stats.first?.dayStart == range.lowerBound)
  }

  @Test
  func aggregateRangeForFebruaryRespectsLeapYear() {
    let calendar = makeCalendar()
    let leapRange = monthRange(year: 2024, month: 2, calendar: calendar)
    let nonLeapRange = monthRange(year: 2025, month: 2, calendar: calendar)
    let now = makeDate(year: 2026, month: 3, day: 15, hour: 12, minute: 0, calendar: calendar)

    let leapStats = ListeningStatsAggregation.aggregate(
      sessions: [],
      rangeStart: leapRange.lowerBound,
      rangeEnd: leapRange.upperBound,
      now: now,
      calendar: calendar
    )

    let nonLeapStats = ListeningStatsAggregation.aggregate(
      sessions: [],
      rangeStart: nonLeapRange.lowerBound,
      rangeEnd: nonLeapRange.upperBound,
      now: now,
      calendar: calendar
    )

    #expect(leapStats.count == 29)
    #expect(nonLeapStats.count == 28)
  }

  @Test
  func aggregateRangeSplitsCrossMonthSession() {
    let calendar = makeCalendar()
    let sessionStart = makeDate(year: 2026, month: 3, day: 31, hour: 23, minute: 50, calendar: calendar)
    let sessionEnd = makeDate(year: 2026, month: 4, day: 1, hour: 0, minute: 10, calendar: calendar)
    let now = makeDate(year: 2026, month: 4, day: 1, hour: 8, minute: 0, calendar: calendar)
    let marchRange = monthRange(year: 2026, month: 3, calendar: calendar)
    let aprilRange = monthRange(year: 2026, month: 4, calendar: calendar)

    let session = ListeningSession(startedAt: sessionStart, endedAt: sessionEnd, duration: 1_200)

    let marchStats = ListeningStatsAggregation.aggregate(
      sessions: [session],
      rangeStart: marchRange.lowerBound,
      rangeEnd: marchRange.upperBound,
      now: now,
      calendar: calendar
    )

    let aprilStats = ListeningStatsAggregation.aggregate(
      sessions: [session],
      rangeStart: aprilRange.lowerBound,
      rangeEnd: aprilRange.upperBound,
      now: now,
      calendar: calendar
    )

    #expect(abs((marchStats.last?.duration ?? 0) - 600) < 0.001)
    #expect(abs((aprilStats.first?.duration ?? 0) - 600) < 0.001)
  }

  @Test
  func aggregateUsesCalendarTimeZoneForDayBucketing() {
    let utcCalendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt)
    let plus8Calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 8 * 3_600) ?? .gmt)

    let sessionStart = makeDate(year: 2026, month: 3, day: 28, hour: 23, minute: 30, calendar: utcCalendar)
    let sessionEnd = makeDate(year: 2026, month: 3, day: 29, hour: 0, minute: 30, calendar: utcCalendar)
    let now = makeDate(year: 2026, month: 3, day: 29, hour: 12, minute: 0, calendar: utcCalendar)

    let session = ListeningSession(startedAt: sessionStart, endedAt: sessionEnd, duration: 3_600)

    let utcStats = ListeningStatsAggregation.aggregate(
      sessions: [session],
      days: 2,
      now: now,
      calendar: utcCalendar
    )

    let plus8Stats = ListeningStatsAggregation.aggregate(
      sessions: [session],
      days: 2,
      now: now,
      calendar: plus8Calendar
    )

    #expect(utcStats.count == 2)
    #expect(plus8Stats.count == 2)

    #expect(abs(utcStats[0].duration - 1_800) < 0.001)
    #expect(abs(utcStats[1].duration - 1_800) < 0.001)

    #expect(abs(plus8Stats[0].duration - 0) < 0.001)
    #expect(abs(plus8Stats[1].duration - 3_600) < 0.001)
  }
}

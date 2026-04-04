import Foundation
import Testing

@testable import ABPlayerDev

struct ListeningSessionSliceAggregationTests {
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

  @Test
  func slicesSplitCrossMidnightSessionIntoTwoDays() {
    let calendar = makeCalendar()
    let sessionStart = makeDate(year: 2026, month: 3, day: 27, hour: 23, minute: 50, calendar: calendar)
    let sessionEnd = makeDate(year: 2026, month: 3, day: 28, hour: 0, minute: 10, calendar: calendar)
    let now = makeDate(year: 2026, month: 3, day: 28, hour: 12, minute: 0, calendar: calendar)

    let session = ListeningSession(startedAt: sessionStart, endedAt: sessionEnd, duration: 1_200)

    let slices = ListeningSessionSliceAggregation.slices(
      sessions: [session],
      days: 2,
      now: now,
      calendar: calendar
    )

    #expect(slices.count == 2)
    #expect(abs(slices[0].duration - 600) < 0.001)
    #expect(abs(slices[1].duration - 600) < 0.001)
    #expect(slices[0].dayStart != slices[1].dayStart)
  }

  @Test
  func slicesClampSessionToRange() {
    let calendar = makeCalendar()
    let rangeStart = makeDate(year: 2026, month: 3, day: 28, hour: 0, minute: 0, calendar: calendar)
    let rangeEnd = makeDate(year: 2026, month: 3, day: 29, hour: 0, minute: 0, calendar: calendar)
    let sessionStart = makeDate(year: 2026, month: 3, day: 27, hour: 23, minute: 50, calendar: calendar)
    let sessionEnd = makeDate(year: 2026, month: 3, day: 28, hour: 0, minute: 10, calendar: calendar)
    let now = makeDate(year: 2026, month: 3, day: 28, hour: 12, minute: 0, calendar: calendar)

    let session = ListeningSession(startedAt: sessionStart, endedAt: sessionEnd, duration: 1_200)

    let slices = ListeningSessionSliceAggregation.slices(
      sessions: [session],
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      now: now,
      calendar: calendar
    )

    #expect(slices.count == 1)
    #expect(abs(slices[0].duration - 600) < 0.001)
    #expect(slices[0].startedAt == rangeStart)
    #expect(slices[0].endedAt == sessionEnd)
  }

  @Test
  func slicesMarkOnlyLatestSliceAsOngoingForOpenSession() {
    let calendar = makeCalendar()
    let sessionStart = makeDate(year: 2026, month: 3, day: 27, hour: 23, minute: 50, calendar: calendar)
    let now = makeDate(year: 2026, month: 3, day: 28, hour: 0, minute: 10, calendar: calendar)

    let session = ListeningSession(startedAt: sessionStart, endedAt: nil, duration: 1_200)

    let slices = ListeningSessionSliceAggregation.slices(
      sessions: [session],
      days: 2,
      now: now,
      calendar: calendar
    )

    #expect(slices.count == 2)
    #expect(slices[0].isOngoing == false)
    #expect(slices[1].isOngoing == true)
  }

  @Test
  func slicesMarkOnlyNewestOpenSessionAsOngoingWhenMultipleAreOpen() {
    let calendar = makeCalendar()
    let now = makeDate(year: 2026, month: 3, day: 28, hour: 1, minute: 0, calendar: calendar)

    let oldOpen = ListeningSession(
      startedAt: makeDate(year: 2026, month: 3, day: 28, hour: 0, minute: 0, calendar: calendar),
      endedAt: nil,
      duration: 600
    )
    let newOpen = ListeningSession(
      startedAt: makeDate(year: 2026, month: 3, day: 28, hour: 0, minute: 40, calendar: calendar),
      endedAt: nil,
      duration: 300
    )

    let slices = ListeningSessionSliceAggregation.slices(
      sessions: [oldOpen, newOpen],
      days: 1,
      now: now,
      calendar: calendar
    )

    #expect(slices.count == 2)
    #expect(slices[0].isOngoing == false)
    #expect(slices[1].isOngoing == true)
  }

  @Test
  func slicesIgnoreZeroDurationSession() {
    let calendar = makeCalendar()
    let now = makeDate(year: 2026, month: 3, day: 28, hour: 12, minute: 0, calendar: calendar)
    let session = ListeningSession(
      startedAt: makeDate(year: 2026, month: 3, day: 28, hour: 10, minute: 0, calendar: calendar),
      endedAt: makeDate(year: 2026, month: 3, day: 28, hour: 10, minute: 30, calendar: calendar),
      duration: 0
    )

    let slices = ListeningSessionSliceAggregation.slices(
      sessions: [session],
      days: 1,
      now: now,
      calendar: calendar
    )

    #expect(slices.isEmpty)
  }
}

import Charts
import Foundation
import SwiftUI

@MainActor
struct ListeningStatsView: View {
  enum ContentTab: String, CaseIterable, Hashable, Identifiable {
    case trend
    case sessions

    var id: String { rawValue }

    var title: String {
      switch self {
      case .trend:
        return "Trend"
      case .sessions:
        return "Sessions"
      }
    }
  }

  @Environment(ListeningStatsService.self) private var statsService

  @State private var viewModel = ListeningStatsViewModel()
  @State private var selectedContentTab: ContentTab = .trend
  @State private var hoveredDayStart: Date?
  @State private var hoverLocation: CGPoint?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      titleSection
      contentTabRow
      controlRow
      contentSection
    }
    .padding(20)
    .frame(minWidth: 820, minHeight: 520)
    .onAppear {
      viewModel.configureIfNeeded(statsService: statsService)
      _ = viewModel.transform(input: .init(event: .onAppear))
    }
  }

  private var contentSection: some View {
    Group {
      switch selectedContentTab {
      case .trend:
        chartSection
      case .sessions:
        sessionsSection
      }
    }
  }

  private var contentTabRow: some View {
    HStack(spacing: 16) {
      Picker("Content", selection: $selectedContentTab) {
        ForEach(ContentTab.allCases) { tab in
          Text(tab.title)
            .tag(tab)
            .accessibilityIdentifier("listening-stats-content-tab-\(tab.rawValue)")
        }
      }
      .pickerStyle(.segmented)
//      .frame(maxWidth: 260)
      .accessibilityIdentifier("listening-stats-content-tab-picker")
      .accessibilityValue(selectedContentTab.title)
    }
  }

  private var titleSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Daily Listening Time")
        .font(.title2)
        .fontWeight(.semibold)
        .accessibilityIdentifier("listening-stats-title")
      Text("Data source: session timer in the top toolbar")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var controlRow: some View {
    HStack(spacing: 16) {
      Picker("Range", selection: selectedRangeBinding) {
        ForEach(ListeningStatsViewModel.Range.allCases) { range in
          Text(range.title)
            .tag(range)
            .accessibilityIdentifier("listening-stats-range-\(range.rawValue)")
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("listening-stats-range-picker")
      .accessibilityValue(viewModel.output.selectedRange.title)

      if viewModel.output.selectedRange == .month {
        monthNavigation
      }
    }
  }

  private var monthNavigation: some View {
    HStack(spacing: 10) {
      Button {
        _ = viewModel.transform(input: .init(event: .previousMonth))
      } label: {
        Image(systemName: "chevron.left")
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("listening-stats-month-prev")

      Text(viewModel.output.monthTitle)
        .font(.headline)
        .frame(minWidth: 140)
        .accessibilityIdentifier("listening-stats-month-title")

      Button {
        _ = viewModel.transform(input: .init(event: .nextMonth))
      } label: {
        Image(systemName: "chevron.right")
      }
      .buttonStyle(.bordered)
      .disabled(!viewModel.output.canGoToNextMonth)
      .accessibilityIdentifier("listening-stats-month-next")
    }
    .accessibilityIdentifier("listening-stats-month-navigation")
  }

  private var chartSection: some View {
    GroupBox("Trend") {
      if viewModel.output.showsTrendEmptyState {
        ContentUnavailableView(
          "No Listening Data",
          systemImage: "chart.bar.xaxis",
          description: Text("Start playing audio or video to accumulate listening time.")
        )
        .frame(maxWidth: .infinity, minHeight: 320)
        .accessibilityIdentifier("listening-stats-empty")
      } else {
        Chart(viewModel.output.chartStats) { stat in
          BarMark(
            x: .value("Day", stat.dayStart, unit: .day),
            y: .value("Minutes", stat.duration / 60)
          )
          .foregroundStyle(.blue.gradient)
          .cornerRadius(4)
          .opacity(barOpacity(for: stat.dayStart))
          .accessibilityIdentifier(barAccessibilityIdentifier(for: stat))
        }
        .accessibilityIdentifier("listening-stats-chart")
        .accessibilityValue("\(viewModel.output.chartStats.count)")
        .chartYAxis {
          AxisMarks(position: .leading)
        }
        .chartXAxis {
          AxisMarks(values: .stride(by: .day, count: xAxisStrideCount)) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(centered: true) {
              if let date = value.as(Date.self) {
                Text(xAxisLabel(for: date))
              }
            }
          }
        }
        .chartOverlay { proxy in
          GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
              Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                  switch phase {
                  case .active(let location):
                    guard let plotFrame = proxy.plotFrame.map({ geometry[$0] }) else {
                      hoveredDayStart = nil
                      hoverLocation = nil
                      return
                    }
                    guard plotFrame.contains(location) else {
                      hoveredDayStart = nil
                      hoverLocation = nil
                      return
                    }

                    let xPosition = location.x - plotFrame.origin.x
                    guard let hoveredDate = proxy.value(atX: xPosition, as: Date.self) else {
                      hoveredDayStart = nil
                      hoverLocation = nil
                      return
                    }

                    let nearestDayStart = nearestDayStart(for: hoveredDate)
                    if
                      let nearestDayStart,
                      let stat = stat(for: nearestDayStart),
                      stat.duration > 0
                    {
                      hoveredDayStart = nearestDayStart
                      hoverLocation = location
                    } else {
                      hoveredDayStart = nil
                      hoverLocation = nil
                    }

                  case .ended:
                    hoveredDayStart = nil
                    hoverLocation = nil
                  }
                }

              if
                let plotFrame = proxy.plotFrame.map({ geometry[$0] }),
                let hoveredStat,
                let hoverLocation
              {
                let tooltipX = min(
                  max(hoverLocation.x, plotFrame.minX + 52),
                  plotFrame.maxX - 52
                )
                let tooltipY = max(
                  plotFrame.minY + 14,
                  min(hoverLocation.y - 18, plotFrame.maxY - 14)
                )

                Text(readableDurationLabel(seconds: hoveredStat.duration))
                  .font(.caption)
                  .fontWeight(.medium)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(.regularMaterial, in: Capsule())
                  .accessibilityIdentifier("listening-stats-tooltip")
                  .position(x: tooltipX, y: tooltipY)
              }
            }
          }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
      }
    }
    .frame(maxHeight: .infinity)
  }

  private var sessionsSection: some View {
    GroupBox("Sessions") {
      if viewModel.output.showsSessionsEmptyState {
        ContentUnavailableView(
          "No Sessions",
          systemImage: "list.bullet.rectangle",
          description: Text("No listening sessions were recorded for this range.")
        )
        .frame(maxWidth: .infinity, minHeight: 320)
        .accessibilityIdentifier("listening-stats-sessions-empty")
      } else {
        VStack(alignment: .leading, spacing: 10) {
          sessionsSummary

          List {
            ForEach(viewModel.output.sessionSections) { section in
              Section {
                ForEach(section.rows) { row in
                  sessionRow(row)
                }
              } header: {
                sessionSectionHeader(section)
              }
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .accessibilityIdentifier("listening-stats-sessions-list")
        }
        .frame(maxWidth: .infinity, minHeight: 360)
      }
    }
    .frame(maxHeight: .infinity)
  }

  private var sessionsSummary: some View {
    HStack(spacing: 14) {
      Label("\(viewModel.output.sessionSliceCount)", systemImage: "list.number")
        .font(.subheadline)
        .help("Session slices")

      Label(readableDurationLabel(seconds: viewModel.output.totalSessionDuration), systemImage: "clock")
        .font(.subheadline)
        .help("Total duration")

      Label(readableDurationLabel(seconds: viewModel.output.averageSessionDuration), systemImage: "chart.bar.doc.horizontal")
        .font(.subheadline)
        .help("Average slice duration")

      Spacer(minLength: 0)
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 2)
    .accessibilityIdentifier("listening-stats-sessions-summary")
  }

  private func sessionSectionHeader(_ section: ListeningStatsViewModel.SessionSection) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(section.title)
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(section.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      Text(section.totalDurationText)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
    }
    .accessibilityIdentifier(
      "listening-stats-sessions-section-\(section.dayStart.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))"
    )
  }

  private func sessionRow(_ row: ListeningStatsViewModel.SessionRow) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(row.timeRangeText)
          .font(.subheadline)
          .fontWeight(.medium)

        if row.isOngoing {
          Text("Ongoing")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 0)

      Text(row.durationText)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
    .accessibilityIdentifier("listening-stats-session-row-\(row.id)")
  }

  private var selectedRangeBinding: Binding<ListeningStatsViewModel.Range> {
    Binding(
      get: { viewModel.output.selectedRange },
      set: { newRange in
        _ = viewModel.transform(input: .init(event: .selectRange(newRange)))
      }
    )
  }

  private var xAxisStrideCount: Int {
    switch viewModel.output.selectedRange {
    case .last7Days:
      return 1
    case .last30Days:
      return 3
    case .month:
      switch viewModel.output.chartStats.count {
      case 0...10:
        return 1
      case 11...20:
        return 2
      default:
        return 3
      }
    }
  }

  private func xAxisLabel(for date: Date) -> String {
    switch viewModel.output.selectedRange {
    case .month:
      return date.formatted(.dateTime.day())
    case .last7Days, .last30Days:
      return date.formatted(.dateTime.month(.abbreviated).day())
    }
  }

  private func nearestDayStart(for hoveredDate: Date) -> Date? {
    guard !viewModel.output.chartStats.isEmpty else { return nil }

    let calendar = viewModel.activeCalendar
    let targetStart = calendar.startOfDay(for: hoveredDate)

    if let exact = viewModel.output.chartStats.first(where: { calendar.isDate($0.dayStart, inSameDayAs: targetStart) }) {
      return exact.dayStart
    }

    return viewModel.output.chartStats.min { lhs, rhs in
      abs(lhs.dayStart.timeIntervalSince(targetStart)) < abs(rhs.dayStart.timeIntervalSince(targetStart))
    }?.dayStart
  }

  private func barOpacity(for dayStart: Date) -> Double {
    guard let hoveredDayStart else { return 1 }
    return hoveredDayStart == dayStart ? 1 : 0.45
  }

  private var hoveredStat: DailyListeningStat? {
    guard let hoveredDayStart else { return nil }
    return stat(for: hoveredDayStart)
  }

  private func stat(for dayStart: Date) -> DailyListeningStat? {
    viewModel.output.chartStats.first(where: { $0.dayStart == dayStart })
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

  private func barAccessibilityIdentifier(for stat: DailyListeningStat) -> String {
    let dateText = stat.dayStart.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    let prefix = stat.duration > 0 ? "listening-stats-bar-nonzero" : "listening-stats-bar-zero"
    return "\(prefix)-\(dateText)"
  }
}

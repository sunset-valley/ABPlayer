import SwiftData
import SwiftUI

@MainActor
struct ListeningStatsDemoView: View {
  @Environment(\.modelContext) private var modelContext

  @State private var didSeedData = false
  @State private var seedErrorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Listening Stats Demo")
        .font(.title2)
        .accessibilityIdentifier("listening-stats-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-listening-stats")
        .font(.caption)
        .foregroundStyle(.secondary)

      if let seedErrorMessage {
        ContentUnavailableView(
          "Failed to Seed Demo Data",
          systemImage: "exclamationmark.triangle",
          description: Text(seedErrorMessage)
        )
      } else if didSeedData {
        ListeningStatsView()
      } else {
        ProgressView("Preparing listening stats demo...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(16)
    .frame(minWidth: 980, minHeight: 620)
    .task {
      guard !didSeedData else { return }
      do {
        try seedDemoDataIfNeeded()
        didSeedData = true
      } catch {
        seedErrorMessage = error.localizedDescription
      }
    }
  }

  private func seedDemoDataIfNeeded() throws {
    let descriptor = FetchDescriptor<ListeningSession>()
    let sessions = try modelContext.fetch(descriptor)
    if !sessions.isEmpty {
      return
    }

    let calendar = Calendar.current
    let todayStart = calendar.startOfDay(for: Date())

    for dayOffset in 0..<12 {
      if dayOffset == 4 {
        continue
      }

      guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else {
        continue
      }

      guard let sessionStart = calendar.date(byAdding: .hour, value: 9 + (dayOffset % 4), to: dayStart) else {
        continue
      }

      let durationSeconds = Double((dayOffset + 1) * 180)
      let sessionEnd = sessionStart.addingTimeInterval(durationSeconds)
      let session = ListeningSession(
        startedAt: sessionStart,
        endedAt: sessionEnd,
        duration: durationSeconds
      )
      modelContext.insert(session)
    }

    if let zeroDurationDay = calendar.date(byAdding: .day, value: -4, to: todayStart) {
      let zeroDurationSession = ListeningSession(
        startedAt: zeroDurationDay,
        endedAt: zeroDurationDay.addingTimeInterval(600),
        duration: 0
      )
      modelContext.insert(zeroDurationSession)
    }

    // Keep one explicit zero-duration day in current month.
    if let zeroDayStart = calendar.date(byAdding: .day, value: -13, to: todayStart) {
      let zeroSession = ListeningSession(
        startedAt: zeroDayStart,
        endedAt: zeroDayStart,
        duration: 0
      )
      modelContext.insert(zeroSession)
    }

    try modelContext.save()
  }
}

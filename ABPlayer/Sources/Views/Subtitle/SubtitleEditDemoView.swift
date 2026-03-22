import SwiftUI

@MainActor
struct SubtitleEditDemoView: View {
  private static let demoCueID =
    UUID(uuidString: "10000000-0000-0000-0000-000000000001") ?? UUID()

  @State private var cues: [SubtitleCue] = [
    SubtitleCue(
      id: demoCueID,
      startTime: 0,
      endTime: 4,
      text: "Original demo subtitle"
    )
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Subtitle Edit Demo")
        .font(.title2)
        .accessibilityIdentifier("subtitle-edit-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-subtitle-edit")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text(cues.first?.text ?? "")
        .font(.caption)
        .accessibilityIdentifier("subtitle-edit-demo-current-text")

      SubtitleView(
        cues: cues,
        fontSize: 16,
        onEditSubtitle: { cueID, newSubtitle in
          guard let index = cues.firstIndex(where: { $0.id == cueID }) else { return }
          let existingCue = cues[index]
          cues[index] = SubtitleCue(
            id: existingCue.id,
            startTime: existingCue.startTime,
            endTime: existingCue.endTime,
            text: newSubtitle
          )
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier("subtitle-edit-demo-subtitle-view")
    }
    .padding(16)
    .frame(minWidth: 880, minHeight: 560)
  }
}

import SwiftUI

@MainActor
struct TranscriptScrollDemoView: View {
  @State private var cues: [SubtitleCue] = Self.makeDemoCues()
  @State private var transcriptMaxWidth: CGFloat = .infinity
  @State private var scrollMetrics = TranscriptTextView.ScrollMetrics(
    offsetY: 0,
    maxOffsetY: 0,
    documentHeight: 0,
    visibleHeight: 0,
    cueCount: 0,
    firstFullyVisibleCueIndex: nil,
    lastFullyVisibleCueIndex: nil
  )

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Transcript Scroll Demo")
        .font(.title2)
        .accessibilityIdentifier("transcript-scroll-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-transcript-scroll")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 16) {
        metric("offset", value: String(format: "%.1f", scrollMetrics.offsetY), id: "transcript-scroll-offset-y")
        metric("max", value: String(format: "%.1f", scrollMetrics.maxOffsetY), id: "transcript-scroll-max-offset-y")
        metric(
          "document",
          value: String(format: "%.1f", scrollMetrics.documentHeight),
          id: "transcript-scroll-document-height"
        )
        metric(
          "visible",
          value: String(format: "%.1f", scrollMetrics.visibleHeight),
          id: "transcript-scroll-visible-height"
        )
        metric(
          "bottom",
          value: scrollMetrics.isAtBottom ? "true" : "false",
          id: "transcript-scroll-at-bottom"
        )
        metric(
          "firstFullyVisible",
          value: scrollMetrics.firstFullyVisibleCueIndex.map(String.init) ?? "nil",
          id: "transcript-scroll-first-fully-visible-cue-index"
        )
        metric(
          "lastFullyVisible",
          value: scrollMetrics.lastFullyVisibleCueIndex.map(String.init) ?? "nil",
          id: "transcript-scroll-last-fully-visible-cue-index"
        )
        metric(
          "cueCount",
          value: String(scrollMetrics.cueCount),
          id: "transcript-scroll-cue-count"
        )
      }
      .font(.caption.monospacedDigit())

      HStack(spacing: 10) {
        Button("Compact Width") {
          transcriptMaxWidth = 520
        }
        .accessibilityIdentifier("transcript-scroll-width-compact")

        Button("Full Width") {
          transcriptMaxWidth = .infinity
        }
        .accessibilityIdentifier("transcript-scroll-width-full")
      }
      .buttonStyle(.bordered)

      SubtitleView(
        cues: cues,
        fontSize: 16,
        onEditSubtitle: { _, _ in },
        onScrollMetricsChanged: { metrics in
          scrollMetrics = metrics
        }
      )
      .frame(maxWidth: transcriptMaxWidth, maxHeight: .infinity, alignment: .leading)
      .accessibilityIdentifier("transcript-scroll-demo-subtitle-view")
    }
    .padding(16)
    .frame(minWidth: 980, minHeight: 620)
  }

  @ViewBuilder
  private func metric(_ title: String, value: String, id: String) -> some View {
    Text("\(title): \(value)")
      .accessibilityIdentifier(id)
  }

  private static func makeDemoCues() -> [SubtitleCue] {
    (0..<260).map { index in
      let start = Double(index) * 2.0
      let end = start + 1.8
      return SubtitleCue(
        startTime: start,
        endTime: end,
        text: "Line \(index + 1): This is a long transcript cue for scroll regression testing, covering wrapping behavior and document height synchronization."
      )
    }
  }
}

import AppKit
import SwiftUI

@MainActor
struct AnnotationMenuDemoView: View {
  @Environment(AnnotationService.self) private var annotationService
  @Environment(AnnotationStyleService.self) private var annotationStyleService

  @State private var didSeedUsedStyle = false
  @State private var styles: [AnnotationStyleDisplayData] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Annotation Menu Demo")
        .font(.title2)
        .accessibilityIdentifier("annotation-menu-demo-title")
      Text("Used by UI tests. Launch with --ui-testing --ui-testing-annotation-demo")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Style count: \(styles.count)")
        .font(.caption)
        .accessibilityIdentifier("style-count")
      Text("\(styles.count)")
        .font(.caption)
        .accessibilityIdentifier("style-count-value")

      AnnotationMenuView(
        selectedText: "demo",
        existingAnnotation: nil,
        styles: styles,
        onAnnotate: { styleID in
          addDemoAnnotation(stylePresetID: styleID)
        },
        onEditComment: {},
        onChangeStyle: { _ in },
        onDelete: {},
        onLookup: {},
        onCopy: {},
        onDismiss: {}
      )
    }
    .padding(16)
    .frame(minWidth: 680, minHeight: 520, alignment: .topLeading)
    .onAppear {
      reloadStyles()
      seedUsedStyleIfNeeded(styles: styles)
    }
    .onChange(of: annotationStyleService.version) { _, _ in
      reloadStyles()
      seedUsedStyleIfNeeded(styles: styles)
    }
    .onChange(of: styles.map(\.id)) { _, _ in
      seedUsedStyleIfNeeded(styles: styles)
    }
  }

  private func reloadStyles() {
    styles = annotationStyleService.allStyles()
  }

  private func seedUsedStyleIfNeeded(styles: [AnnotationStyleDisplayData]) {
    guard !didSeedUsedStyle else { return }
    guard let firstStyle = styles.first else { return }
    if annotationService.styleUsageCount(stylePresetID: firstStyle.id) == 0 {
      addDemoAnnotation(stylePresetID: firstStyle.id)
    }
    didSeedUsedStyle = true
  }

  private func addDemoAnnotation(stylePresetID: UUID) {
    let selection = CrossCueTextSelection(
      segments: [
        .init(
          cueID: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
          localRange: NSRange(location: 0, length: 4),
          text: "demo"
        )
      ],
      fullText: "demo",
      globalRange: NSRange(location: 0, length: 4)
    )
    _ = annotationService.addAnnotation(selection: selection, stylePresetID: stylePresetID)
  }
}

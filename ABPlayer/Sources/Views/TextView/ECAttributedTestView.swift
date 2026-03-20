import AppKit
import SwiftUI

struct ECAttributedTestContainer: View {
    let lines: [String]
    let fontSize: CGFloat
    let textColor: NSColor

    @State private var markups: [ECMarkup] = []
    @State private var paragraphOffsets: [Int: CGFloat] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prototype offsets: \(paragraphOffsets.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ECAttributedScrollTextView(
                lines: lines,
                fontSize: fontSize,
                textColor: textColor,
                markups: $markups,
                paragraphOffsets: $paragraphOffsets
            )
        }
    }
}

private struct ECAttributedScrollTextView: NSViewRepresentable {
    var lines: [String]
    var fontSize: CGFloat
    var textColor: NSColor
    @Binding var markups: [ECMarkup]
    @Binding var paragraphOffsets: [Int: CGFloat]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ECAttributedPrototypeScrollView {
        let scrollView = ECAttributedPrototypeScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let documentView = ECAttributedNativeView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        documentView.autoresizingMask = [.width]
        documentView.onMarkupsChange = { [weak coordinator = context.coordinator] next in
            coordinator?.receiveMarkups(next)
        }
        documentView.onParagraphOffsetsChange = { [weak coordinator = context.coordinator] next in
            coordinator?.receiveOffsets(next)
        }

        scrollView.documentView = documentView
        return scrollView
    }

    func updateNSView(_ scrollView: ECAttributedPrototypeScrollView, context: Context) {
        context.coordinator.parent = self

        guard let documentView = scrollView.documentView as? ECAttributedNativeView else {
            return
        }

        let targetWidth = max(200, scrollView.contentSize.width)
        if abs(documentView.frame.width - targetWidth) > 0.5 {
            documentView.setFrameSize(NSSize(width: targetWidth, height: documentView.frame.height))
        }

        documentView.updateContent(
            lines: lines,
            fontSize: fontSize,
            textColor: textColor,
            markups: markups
        )
    }

    final class Coordinator {
        var parent: ECAttributedScrollTextView

        init(parent: ECAttributedScrollTextView) {
            self.parent = parent
        }

        func receiveMarkups(_ next: [ECMarkup]) {
            guard parent.markups != next else {
                return
            }
            parent.markups = next
        }

        func receiveOffsets(_ next: [Int: CGFloat]) {
            guard parent.paragraphOffsets != next else {
                return
            }
            parent.paragraphOffsets = next
        }
    }
}

private final class ECAttributedPrototypeScrollView: NSScrollView {
    override func layout() {
        super.layout()

        guard let documentView else {
            return
        }

        let targetWidth = max(200, contentSize.width)
        if abs(documentView.frame.width - targetWidth) > 0.5 {
            documentView.setFrameSize(NSSize(width: targetWidth, height: documentView.frame.height))
        }
    }
}

import AppKit
import SwiftUI

struct ECTextView: NSViewRepresentable {
    var id: Int
    var text: String
    var fontSize: CGFloat
    var textColor: NSColor
    var selection: ECTextSharedSelection?
    var markups: [ECMarkup]
    var comments: [ECComment]
    var onSelectRange: (NSRange?) -> Void
    var onRequestContextMenu: (ECContextMenuRequest) -> Void

    func makeNSView(context: Context) -> ECTextNativeView {
        let view = ECTextNativeView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: ECTextNativeView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: ECTextNativeView) {
        view.onSelectionChange = onSelectRange
        view.onContextMenuRequest = onRequestContextMenu
        view.updateContent(
            text: text,
            fontSize: fontSize,
            textColor: textColor,
            selectedRange: effectiveSelectedRange,
            markups: markups,
            comments: comments
        )
    }

    private var effectiveSelectedRange: NSRange? {
        guard let selection, selection.id == id else { return nil }
        return selection.selectionRange
    }
}

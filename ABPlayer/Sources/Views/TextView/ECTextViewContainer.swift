import AppKit
import SwiftUI

struct ECTextViewContainer: View {
    let itemCount: Int
    let sampleParagraphs: [String]
    let fontSize: CGFloat
    let textColor: NSColor

    @State private var selection: ECTextSharedSelection?
    @State private var markupsByTextID: [Int: [ECMarkup]] = [:]
    @State private var commentsByTextID: [Int: [ECComment]] = [:]
    @State private var contextMenuHandler = ECTextContextMenuHandler()

    var body: some View {
        LazyVStack(spacing: 14) {
            ForEach(0..<itemCount, id: \.self) { index in
                let paragraph = sampleParagraphs[index % sampleParagraphs.count]
                ECTextView(
                    id: index,
                    text: "[\(index + 1)] \(paragraph)",
                    fontSize: fontSize,
                    textColor: textColor,
                    selection: selection,
                    markups: markupsByTextID[index, default: []],
                    comments: commentsByTextID[index, default: []],
                    onSelectRange: { range in
                        handleSelectionChange(for: index, range: range)
                    },
                    onRequestContextMenu: { request in
                        handleContextMenuRequest(for: index, request: request)
                    }
                )
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }

    private func handleSelectionChange(for id: Int, range: NSRange?) {
        guard let nextSelection = targetSelection(for: id, range: range) else {
            selection = nil
            return
        }

        if selection != nextSelection {
            selection = nextSelection
        }
    }

    private func handleContextMenuRequest(for id: Int, request: ECContextMenuRequest) {
        guard let target = targetSelection(for: id, range: request.selectedRange) else {
            selection = nil
            return
        }

        if selection != target {
            selection = target
        }

        presentContextMenu(for: target, request: request)
    }

    private func presentContextMenu(for target: ECTextSharedSelection, request: ECContextMenuRequest) {
        guard let window = NSApp.window(withWindowNumber: request.windowNumber) ?? NSApp.mainWindow ?? NSApp.keyWindow,
              let anchorView = window.contentView else {
            return
        }

        let menu = makeContextMenu(for: target)
        guard !menu.items.isEmpty else {
            return
        }

        guard let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: request.locationInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            return
        }

        NSMenu.popUpContextMenu(menu, with: event, for: anchorView)
    }

    private func makeContextMenu(for target: ECTextSharedSelection) -> NSMenu {
        let menu = NSMenu(title: "Selection")
        contextMenuHandler.reset()

        let blockItems: [(title: String, color: NSColor)] = [
            (title: "Block Yellow", color: NSColor.systemYellow.withAlphaComponent(0.45)),
            (title: "Block Green", color: NSColor.systemGreen.withAlphaComponent(0.35)),
            (title: "Block Red", color: NSColor.systemRed.withAlphaComponent(0.25))
        ]

        for blockItem in blockItems {
            menu.addItem(contextMenuHandler.item(title: blockItem.title) { [self] in
                performMenuAction {
                    appendBlockMarkup(color: blockItem.color, target: target)
                }
            })
        }

        menu.addItem(.separator())

        menu.addItem(contextMenuHandler.item(title: "Underline Blue") { [self] in
            performMenuAction {
                appendUnderlineMarkup(color: .systemBlue, target: target)
            }
        })

        menu.addItem(.separator())

        menu.addItem(contextMenuHandler.item(title: "Add Comment") { [self] in
            performMenuAction {
                addComment(target: target)
            }
        })

        return menu
    }

    private func targetSelection(for id: Int, range: NSRange?) -> ECTextSharedSelection? {
        guard let range, range.length > 0 else {
            return nil
        }

        return ECTextSharedSelection(id: id, selectionRange: range)
    }

    private func performMenuAction(_ action: () -> Void) {
        action()
        selection = nil
    }

    private func appendMarkup(_ markup: ECMarkup, for id: Int) {
        var current = markupsByTextID[id, default: []]
        current.append(markup)
        markupsByTextID[id] = current
    }

    private func appendBlockMarkup(color: NSColor, target: ECTextSharedSelection) {
        appendMarkup(
            ECMarkup(range: target.selectionRange, type: .block, color: color, thickness: .thin1),
            for: target.id
        )
    }

    private func appendUnderlineMarkup(color: NSColor, target: ECTextSharedSelection) {
        appendMarkup(
            ECMarkup(range: target.selectionRange, type: .underline, color: color, thickness: .thin2),
            for: target.id
        )
    }

    private func addComment(target: ECTextSharedSelection) {
        let alert = NSAlert()
        alert.messageText = "Add Comment"
        alert.informativeText = "Comment will appear above selected text"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Type comment"
        alert.accessoryView = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let commentText = value.isEmpty ? "Comment" : value
        appendComment(ECComment(range: target.selectionRange, text: commentText, color: .systemBlue), for: target.id)
    }

    private func appendComment(_ comment: ECComment, for id: Int) {
        var current = commentsByTextID[id, default: []]
        current.append(comment)
        commentsByTextID[id] = current
    }
}

private final class ECTextContextMenuHandler: NSObject {
    private var handlers: [UUID: () -> Void] = [:]

    func reset() {
        handlers.removeAll()
    }

    func item(title: String, action: @escaping () -> Void) -> NSMenuItem {
        let token = UUID()
        handlers[token] = action

        let item = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = token
        return item
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? UUID,
              let handler = handlers[token] else {
            return
        }

        handler()
    }
}

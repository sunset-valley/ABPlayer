import AppKit
import Foundation

struct ECTextSharedSelection: Equatable {
    let id: Int
    let selectionRange: NSRange
}

struct ECContextMenuRequest {
    let windowNumber: Int
    let locationInWindow: NSPoint
    let selectedRange: NSRange?
}

struct ECMarkup: Identifiable, Equatable {
    enum Kind: Equatable {
        case underline
        case block
    }

    enum Thickness: Equatable {
        case thin1
        case thin2
    }

    let id: UUID
    let range: NSRange
    let type: Kind
    let color: NSColor
    let thickness: Thickness

    init(
        id: UUID = UUID(),
        range: NSRange,
        type: Kind,
        color: NSColor,
        thickness: Thickness = .thin1
    ) {
        self.id = id
        self.range = range
        self.type = type
        self.color = color
        self.thickness = thickness
    }

    static func == (lhs: ECMarkup, rhs: ECMarkup) -> Bool {
        lhs.id == rhs.id
            && lhs.range == rhs.range
            && lhs.type == rhs.type
            && lhs.thickness == rhs.thickness
            && lhs.color.isEqual(rhs.color)
    }
}

struct ECComment: Identifiable, Equatable {
    let id: UUID
    let range: NSRange
    let text: String
    let color: NSColor

    init(id: UUID = UUID(), range: NSRange, text: String, color: NSColor) {
        self.id = id
        self.range = range
        self.text = text
        self.color = color
    }

    static func == (lhs: ECComment, rhs: ECComment) -> Bool {
        lhs.id == rhs.id
            && lhs.range == rhs.range
            && lhs.text == rhs.text
            && lhs.color.isEqual(rhs.color)
    }
}

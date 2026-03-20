import AppKit
import CoreText

struct ECAttributedParagraphEntry {
    let id: Int
    let text: String
    let globalRange: NSRange
    let topY: CGFloat
    let height: CGFloat
    let bottomY: CGFloat
}

struct ECAttributedDocumentIndex {
    let entries: [ECAttributedParagraphEntry]
    let totalHeight: CGFloat
    let lineSpacing: CGFloat

    static let empty = ECAttributedDocumentIndex(entries: [], totalHeight: 0, lineSpacing: 0)

    static func build(
        lines: [String],
        width: CGFloat,
        fontSize: CGFloat,
        paragraphSpacing: CGFloat
    ) -> ECAttributedDocumentIndex {
        guard !lines.isEmpty, width > 1 else {
            return .empty
        }

        let font = NSFont.systemFont(ofSize: fontSize)
        let lineSpacing = max(3, fontSize * 0.18)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing

        let minimumLineHeight = ceil(font.ascender - font.descender + font.leading)
        var entries: [ECAttributedParagraphEntry] = []
        entries.reserveCapacity(lines.count)

        var runningY: CGFloat = 0
        var runningGlobalLocation = 0

        for (index, paragraphText) in lines.enumerated() {
            let displayText = paragraphText.isEmpty ? " " : paragraphText
            let attributed = NSAttributedString(
                string: displayText,
                attributes: [
                    .font: font,
                    .paragraphStyle: paragraphStyle
                ]
            )

            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let measured = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: attributed.length),
                nil,
                CGSize(width: width, height: .greatestFiniteMagnitude),
                nil
            )

            let height = max(minimumLineHeight, ceil(measured.height))
            let globalRange = NSRange(location: runningGlobalLocation, length: paragraphText.utf16.count)

            let entry = ECAttributedParagraphEntry(
                id: index,
                text: paragraphText,
                globalRange: globalRange,
                topY: runningY,
                height: height,
                bottomY: runningY + height
            )
            entries.append(entry)

            runningY += height
            if index < lines.count - 1 {
                runningY += paragraphSpacing
                runningGlobalLocation += paragraphText.utf16.count + 1
            } else {
                runningGlobalLocation += paragraphText.utf16.count
            }
        }

        return ECAttributedDocumentIndex(entries: entries, totalHeight: runningY, lineSpacing: lineSpacing)
    }

    func visibleParagraphRange(minY: CGFloat, maxY: CGFloat) -> ClosedRange<Int>? {
        guard !entries.isEmpty else {
            return nil
        }

        let first = firstIntersectingIndex(minY: minY)
        let last = lastIntersectingIndex(maxY: maxY)

        guard first <= last,
              first >= 0,
              last < entries.count else {
            return nil
        }

        return first ... last
    }

    func entryIndex(forGlobalTextIndex index: Int) -> Int? {
        guard !entries.isEmpty else {
            return nil
        }

        var low = 0
        var high = entries.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let entry = entries[mid]
            let start = entry.globalRange.location
            let end = start + entry.globalRange.length

            if index < start {
                high = mid - 1
                continue
            }

            if index >= end {
                low = mid + 1
                continue
            }

            return mid
        }

        return nil
    }

    private func firstIntersectingIndex(minY: CGFloat) -> Int {
        var low = 0
        var high = entries.count - 1
        var answer = entries.count

        while low <= high {
            let mid = (low + high) / 2
            if entries[mid].bottomY >= minY {
                answer = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }

        return min(max(answer, 0), entries.count - 1)
    }

    private func lastIntersectingIndex(maxY: CGFloat) -> Int {
        var low = 0
        var high = entries.count - 1
        var answer = -1

        while low <= high {
            let mid = (low + high) / 2
            if entries[mid].topY <= maxY {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return min(max(answer, 0), entries.count - 1)
    }
}

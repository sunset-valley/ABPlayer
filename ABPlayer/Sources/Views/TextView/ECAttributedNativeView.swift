import AppKit
import CoreText

final class ECAttributedNativeView: NSView {
    var onMarkupsChange: (([ECMarkup]) -> Void)?
    var onParagraphOffsetsChange: (([Int: CGFloat]) -> Void)?

    private var lines: [String] = []
    private var fontSize: CGFloat = 18
    private var textColor: NSColor = .labelColor
    private var markups: [ECMarkup] = []
    private var selectedRange: NSRange?
    private var dragStartIndex: Int?

    private var index: ECAttributedDocumentIndex = .empty
    private var cachedFramesByParagraphID: [Int: CTFrame] = [:]
    private var cachedLinesByParagraphID: [Int: [CTLine]] = [:]
    private var cachedLineOriginsByParagraphID: [Int: [CGPoint]] = [:]
    private var lastMeasuredWidth: CGFloat = 0

    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 12
    private let paragraphSpacing: CGFloat = 14
    private let visibleOverscan: CGFloat = 220
    private let wordCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_'")).union(.decimalDigits)
    private let contextMenuHandler = ECAttributedContextMenuHandler()

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func updateContent(
        lines: [String],
        fontSize: CGFloat,
        textColor: NSColor,
        markups: [ECMarkup]
    ) {
        var requiresRelayout = false
        var shouldDisplay = false

        if self.lines != lines {
            self.lines = lines
            selectedRange = nil
            requiresRelayout = true
            shouldDisplay = true
        }

        if self.fontSize != fontSize {
            self.fontSize = fontSize
            requiresRelayout = true
            shouldDisplay = true
        }

        if !self.textColor.isEqual(textColor) {
            self.textColor = textColor
            clearParagraphCache()
            shouldDisplay = true
        }

        if self.markups != markups {
            self.markups = markups
            shouldDisplay = true
        }

        if requiresRelayout {
            rebuildDocumentIndex()
        }

        normalizeStoredRanges()

        if shouldDisplay {
            needsDisplay = true
        }
    }

    override func layout() {
        super.layout()

        if abs(bounds.width - lastMeasuredWidth) > 0.5 {
            lastMeasuredWidth = bounds.width
            rebuildDocumentIndex()
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        guard !index.entries.isEmpty else {
            return
        }

        guard let visibleRange = visibleParagraphRange() else {
            return
        }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        pruneParagraphCache(keeping: visibleRange)

        let blockMarkups = markups.filter { $0.type == .block }
        let underlineMarkups = markups.filter { $0.type == .underline }

        for paragraphIndex in visibleRange {
            let entry = index.entries[paragraphIndex]
            let paragraphRect = paragraphRect(for: entry)

            drawBlockMarkups(blockMarkups, for: entry, in: paragraphRect, context: context)
            drawParagraphText(for: entry, in: paragraphRect, context: context)
            drawUnderlineMarkups(underlineMarkups, for: entry, in: paragraphRect, context: context)
            drawSelection(for: entry, in: paragraphRect, context: context)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        guard let index = globalTextIndex(for: event) else {
            dragStartIndex = nil
            selectedRange = nil
            needsDisplay = true
            return
        }

        dragStartIndex = index
        selectedRange = NSRange(location: index, length: 0)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartIndex,
              let end = globalTextIndex(for: event) else {
            return
        }

        selectedRange = NSRange(location: min(start, end), length: abs(end - start))
        needsDisplay = true
    }

    override func mouseUp(with _: NSEvent) {
        dragStartIndex = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        if let hitIndex = globalTextIndex(for: event),
           let wordRange = wordRange(atGlobalIndex: hitIndex) {
            let intersectsSelection = selectedRange
                .map { NSIntersectionRange($0, wordRange).length > 0 } ?? false

            if !intersectsSelection || selectedRange == nil {
                selectedRange = wordRange
                needsDisplay = true
            }
        }

        showContextMenu(with: event)
    }

    private func showContextMenu(with event: NSEvent) {
        guard let selectedRange, selectedRange.length > 0 else {
            return
        }

        let menu = makeContextMenu(for: selectedRange)
        guard !menu.items.isEmpty else {
            return
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func makeContextMenu(for selection: NSRange) -> NSMenu {
        let menu = NSMenu(title: "Selection")
        contextMenuHandler.reset()

        let blockItems: [(title: String, color: NSColor)] = [
            (title: "Block Yellow", color: NSColor.systemYellow.withAlphaComponent(0.45)),
            (title: "Block Green", color: NSColor.systemGreen.withAlphaComponent(0.35)),
            (title: "Block Red", color: NSColor.systemRed.withAlphaComponent(0.25))
        ]

        for blockItem in blockItems {
            menu.addItem(contextMenuHandler.item(title: blockItem.title) { [weak self] in
                self?.appendMarkup(
                    ECMarkup(range: selection, type: .block, color: blockItem.color, thickness: .thin1)
                )
            })
        }

        menu.addItem(.separator())

        menu.addItem(contextMenuHandler.item(title: "Underline Blue") { [weak self] in
            self?.appendMarkup(
                ECMarkup(range: selection, type: .underline, color: .systemBlue, thickness: .thin2)
            )
        })

        return menu
    }

    private func appendMarkup(_ markup: ECMarkup) {
        guard markup.range.length > 0 else {
            return
        }

        markups.append(markup)
        onMarkupsChange?(markups)
        needsDisplay = true
    }

    private func rebuildDocumentIndex() {
        let contentWidth = max(120, bounds.width - (horizontalPadding * 2))
        index = ECAttributedDocumentIndex.build(
            lines: lines,
            width: contentWidth,
            fontSize: fontSize,
            paragraphSpacing: paragraphSpacing
        )

        clearParagraphCache()
        updateDocumentHeight()
        publishOffsets()
        normalizeStoredRanges()
    }

    private func updateDocumentHeight() {
        let targetHeight = max(220, index.totalHeight + (verticalPadding * 2))
        if abs(frame.height - targetHeight) > 0.5 {
            setFrameSize(NSSize(width: frame.width, height: targetHeight))
        }
    }

    private func publishOffsets() {
        let offsets = Dictionary(uniqueKeysWithValues: index.entries.map { ($0.id, $0.topY + verticalPadding) })
        onParagraphOffsetsChange?(offsets)
    }

    private func normalizeStoredRanges() {
        let docLength = documentLength

        selectedRange = normalizedRange(selectedRange, docLength: docLength)

        let normalizedMarkups = markups.compactMap { item -> ECMarkup? in
            guard let range = normalizedRange(item.range, docLength: docLength), range.length > 0 else {
                return nil
            }

            if range == item.range {
                return item
            }

            return ECMarkup(
                id: item.id,
                range: range,
                type: item.type,
                color: item.color,
                thickness: item.thickness
            )
        }

        if normalizedMarkups != markups {
            markups = normalizedMarkups
            onMarkupsChange?(normalizedMarkups)
        }
    }

    private func normalizedRange(_ range: NSRange?, docLength: Int) -> NSRange? {
        guard let range else {
            return nil
        }

        guard docLength >= 0 else {
            return nil
        }

        let clampedLocation = min(max(range.location, 0), docLength)
        let maxLength = max(0, docLength - clampedLocation)
        let clampedLength = min(max(range.length, 0), maxLength)
        return NSRange(location: clampedLocation, length: clampedLength)
    }

    private var documentLength: Int {
        guard let last = index.entries.last else {
            return 0
        }

        return last.globalRange.location + last.globalRange.length
    }

    private func clearParagraphCache() {
        cachedFramesByParagraphID.removeAll()
        cachedLinesByParagraphID.removeAll()
        cachedLineOriginsByParagraphID.removeAll()
    }

    private func paragraphRect(for entry: ECAttributedParagraphEntry) -> CGRect {
        CGRect(
            x: horizontalPadding,
            y: verticalPadding + entry.topY,
            width: max(120, bounds.width - (horizontalPadding * 2)),
            height: entry.height
        )
    }

    private func visibleParagraphRange() -> ClosedRange<Int>? {
        let minY = max(0, visibleRect.minY - verticalPadding - visibleOverscan)
        let maxY = max(0, visibleRect.maxY - verticalPadding + visibleOverscan)
        return index.visibleParagraphRange(minY: minY, maxY: maxY)
    }

    private func pruneParagraphCache(keeping visibleRange: ClosedRange<Int>) {
        let keepIDs = Set(visibleRange.map { index.entries[$0].id })

        cachedFramesByParagraphID = cachedFramesByParagraphID.filter { keepIDs.contains($0.key) }
        cachedLinesByParagraphID = cachedLinesByParagraphID.filter { keepIDs.contains($0.key) }
        cachedLineOriginsByParagraphID = cachedLineOriginsByParagraphID.filter { keepIDs.contains($0.key) }
    }

    private func frameAndLineData(for entry: ECAttributedParagraphEntry) -> (CTFrame, [CTLine], [CGPoint]) {
        if let frame = cachedFramesByParagraphID[entry.id],
           let lines = cachedLinesByParagraphID[entry.id],
           let origins = cachedLineOriginsByParagraphID[entry.id] {
            return (frame, lines, origins)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = index.lineSpacing

        let displayText = entry.text.isEmpty ? " " : entry.text
        let attributed = NSAttributedString(
            string: displayText,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let localRect = CGRect(x: 0, y: 0, width: max(120, bounds.width - (horizontalPadding * 2)), height: entry.height)
        let path = CGPath(rect: localRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)

        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        cachedFramesByParagraphID[entry.id] = frame
        cachedLinesByParagraphID[entry.id] = lines
        cachedLineOriginsByParagraphID[entry.id] = origins

        return (frame, lines, origins)
    }

    private func drawParagraphText(for entry: ECAttributedParagraphEntry, in rect: CGRect, context: CGContext) {
        let (frame, _, _) = frameAndLineData(for: entry)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: rect.minX, y: rect.minY + rect.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func drawSelection(for entry: ECAttributedParagraphEntry, in rect: CGRect, context: CGContext) {
        guard let selectedRange,
              selectedRange.length > 0,
              let local = localRange(for: selectedRange, in: entry) else {
            return
        }

        let rects = rects(for: local, entry: entry, paragraphRect: rect)
        context.setFillColor(NSColor.selectedTextBackgroundColor.withAlphaComponent(0.32).cgColor)
        for item in rects {
            context.fill(item)
        }
    }

    private func drawBlockMarkups(
        _ blocks: [ECMarkup],
        for entry: ECAttributedParagraphEntry,
        in rect: CGRect,
        context: CGContext
    ) {
        guard !blocks.isEmpty else {
            return
        }

        for markup in blocks {
            guard let local = localRange(for: markup.range, in: entry) else {
                continue
            }

            let rects = rects(for: local, entry: entry, paragraphRect: rect)
            context.setFillColor(markup.color.cgColor)
            for item in rects {
                context.fill(item)
            }
        }
    }

    private func drawUnderlineMarkups(
        _ underlines: [ECMarkup],
        for entry: ECAttributedParagraphEntry,
        in rect: CGRect,
        context: CGContext
    ) {
        guard !underlines.isEmpty else {
            return
        }

        for markup in underlines {
            guard let local = localRange(for: markup.range, in: entry) else {
                continue
            }

            let rects = rects(for: local, entry: entry, paragraphRect: rect)
            context.setStrokeColor(markup.color.cgColor)
            context.setLineWidth(underlineThickness(for: markup.thickness))

            for item in rects {
                let y = item.maxY - max(1, underlineThickness(for: markup.thickness))
                context.move(to: CGPoint(x: item.minX, y: y))
                context.addLine(to: CGPoint(x: item.maxX, y: y))
                context.strokePath()
            }
        }
    }

    private func underlineThickness(for thickness: ECMarkup.Thickness) -> CGFloat {
        switch thickness {
        case .thin1:
            return 1
        case .thin2:
            return 2
        }
    }

    private func localRange(for globalRange: NSRange, in entry: ECAttributedParagraphEntry) -> NSRange? {
        let intersection = NSIntersectionRange(globalRange, entry.globalRange)
        guard intersection.length > 0 else {
            return nil
        }

        return NSRange(
            location: intersection.location - entry.globalRange.location,
            length: intersection.length
        )
    }

    private func rects(
        for localRange: NSRange,
        entry: ECAttributedParagraphEntry,
        paragraphRect: CGRect
    ) -> [CGRect] {
        guard localRange.length > 0 else {
            return []
        }

        let (_, lines, origins) = frameAndLineData(for: entry)
        guard !lines.isEmpty else {
            return []
        }

        var output: [CGRect] = []
        output.reserveCapacity(lines.count)

        for (lineIndex, line) in lines.enumerated() {
            let lineRange = CTLineGetStringRange(line)
            let lineNSRange = NSRange(location: lineRange.location, length: lineRange.length)
            let intersection = NSIntersectionRange(lineNSRange, localRange)
            if intersection.length == 0 {
                continue
            }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)

            let startOffset = CTLineGetOffsetForStringIndex(line, intersection.location, nil)
            let endOffset = CTLineGetOffsetForStringIndex(line, intersection.location + intersection.length, nil)

            let origin = origins[lineIndex]
            let rect = CGRect(
                x: paragraphRect.minX + origin.x + startOffset,
                y: paragraphRect.minY + (paragraphRect.height - origin.y - ascent),
                width: max(1, endOffset - startOffset),
                height: ascent + descent
            )
            output.append(rect)
        }

        return output
    }

    private func globalTextIndex(for event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return globalTextIndex(forPoint: point)
    }

    private func globalTextIndex(forPoint point: CGPoint) -> Int? {
        let contentY = point.y - verticalPadding
        guard contentY >= 0,
              let candidateRange = index.visibleParagraphRange(minY: contentY, maxY: contentY) else {
            return nil
        }

        for paragraphIndex in candidateRange {
            let entry = index.entries[paragraphIndex]
            let paragraphRect = paragraphRect(for: entry)
            guard paragraphRect.contains(point) else {
                continue
            }

            guard let localIndex = localTextIndex(forPoint: point, entry: entry, paragraphRect: paragraphRect) else {
                continue
            }

            let clampedLocal = min(max(localIndex, 0), entry.globalRange.length)
            return entry.globalRange.location + clampedLocal
        }

        return nil
    }

    private func localTextIndex(
        forPoint point: CGPoint,
        entry: ECAttributedParagraphEntry,
        paragraphRect: CGRect
    ) -> Int? {
        let (_, lines, origins) = frameAndLineData(for: entry)
        guard !lines.isEmpty else {
            return nil
        }

        let pointInParagraphCT = CGPoint(
            x: point.x - paragraphRect.minX,
            y: paragraphRect.height - (point.y - paragraphRect.minY)
        )

        for (lineIndex, line) in lines.enumerated() {
            let origin = origins[lineIndex]

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            let lineRect = CGRect(
                x: origin.x,
                y: origin.y - descent,
                width: paragraphRect.width,
                height: ascent + descent + leading
            )

            if lineRect.contains(pointInParagraphCT) {
                let local = CGPoint(
                    x: pointInParagraphCT.x - origin.x,
                    y: pointInParagraphCT.y - origin.y
                )

                let index = stringIndexIfHitText(line: line, local: local)
                if index != kCFNotFound {
                    return index
                }
            }
        }

        return nil
    }

    private func stringIndexIfHitText(line: CTLine, local: CGPoint) -> CFIndex {
        let typographicWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        let trailing = Double(CTLineGetTrailingWhitespaceWidth(line))
        let effectiveRight = CGFloat(typographicWidth - trailing)

        if local.x < 0 || local.x > effectiveRight {
            return kCFNotFound
        }

        return CTLineGetStringIndexForPosition(line, local)
    }

    private func wordRange(atGlobalIndex globalIndex: Int) -> NSRange? {
        let adjusted = max(0, globalIndex)

        let paragraphIndex: Int
        if let exact = index.entryIndex(forGlobalTextIndex: adjusted) {
            paragraphIndex = exact
        } else if adjusted > 0,
                  let previous = index.entryIndex(forGlobalTextIndex: adjusted - 1) {
            paragraphIndex = previous
        } else {
            return nil
        }

        let entry = index.entries[paragraphIndex]
        let nsText = entry.text as NSString
        guard nsText.length > 0 else {
            return nil
        }

        let rawLocal = adjusted - entry.globalRange.location
        var probe = min(max(0, rawLocal), nsText.length - 1)

        if !isWordCharacter(nsText.character(at: probe)) {
            if probe > 0, isWordCharacter(nsText.character(at: probe - 1)) {
                probe -= 1
            } else {
                return nil
            }
        }

        var start = probe
        while start > 0, isWordCharacter(nsText.character(at: start - 1)) {
            start -= 1
        }

        var end = probe
        while end < nsText.length, isWordCharacter(nsText.character(at: end)) {
            end += 1
        }

        guard end > start else {
            return nil
        }

        return NSRange(location: entry.globalRange.location + start, length: end - start)
    }

    private func isWordCharacter(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else {
            return false
        }
        return wordCharacterSet.contains(scalar)
    }
}

private final class ECAttributedContextMenuHandler: NSObject {
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

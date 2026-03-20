import AppKit
import CoreText

final class ECTextNativeView: NSView {
    private struct TextStyleCacheKey: Equatable {
        var text: String
        var fontSize: CGFloat
        var colorToken: UInt64
    }

    private struct LayoutCacheKey: Equatable {
        var styleKey: TextStyleCacheKey
        var contentWidth: CGFloat
        var markupVersion: Int
    }

    var onSelectionChange: ((NSRange?) -> Void)?
    var onContextMenuRequest: ((ECContextMenuRequest) -> Void)?

    private var text: String = ""
    private var fontSize: CGFloat = 18
    private var textColor: NSColor = .labelColor
    private var selectedRange: NSRange?
    private var dragStartIndex: Int?
    private var markups: [ECMarkup] = []
    private var comments: [ECComment] = []
    private var lastMeasuredWidth: CGFloat = 0
    private var markupVersion: Int = 0
    private var cachedFrameKey: LayoutCacheKey?
    private var cachedFrame: CTFrame?
    private var cachedHeightKey: LayoutCacheKey?
    private var cachedSuggestedHeight: CGFloat?
    private let wordCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_'"))

    func updateContent(
        text: String,
        fontSize: CGFloat,
        textColor: NSColor,
        selectedRange: NSRange?,
        markups: [ECMarkup],
        comments: [ECComment]
    ) {
        var affectsIntrinsicSize = false
        var shouldDisplay = false

        if self.text != text {
            self.text = text
            affectsIntrinsicSize = true
            shouldDisplay = true
            invalidateTextLayoutCache()
        }

        if self.fontSize != fontSize {
            self.fontSize = fontSize
            affectsIntrinsicSize = true
            shouldDisplay = true
            invalidateTextLayoutCache()
        }

        if !self.textColor.isEqual(textColor) {
            self.textColor = textColor
            shouldDisplay = true
            invalidateTextLayoutCache()
        }

        if self.markups != markups {
            self.markups = markups
            markupVersion &+= 1
            shouldDisplay = true
            invalidateTextLayoutCache()
        }

        if self.comments != comments {
            self.comments = comments
            shouldDisplay = true
        }

        if self.selectedRange != selectedRange {
            self.selectedRange = selectedRange
            shouldDisplay = true
        }

        requestRenderUpdate(affectsIntrinsicSize: affectsIntrinsicSize, shouldDisplay: shouldDisplay)
    }

    override var intrinsicContentSize: NSSize {
        let contentWidth = max(120, (bounds.width > 1 ? bounds.width : 760) - 24)
        let height = suggestedTextHeight(for: contentWidth)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(84, height + 24))
    }

    override func layout() {
        super.layout()
        if abs(bounds.width - lastMeasuredWidth) > 0.5 {
            lastMeasuredWidth = bounds.width
            invalidateTextLayoutCache()
            requestRenderUpdate(affectsIntrinsicSize: true, shouldDisplay: true)
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        guard !text.isEmpty else { return }

        let insetRect = bounds.insetBy(dx: 12, dy: 12)
        guard insetRect.width > 1, insetRect.height > 1 else { return }

        let frame = frameForCurrentContent(in: insetRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        drawSelection(in: frame, context: context, pathRect: insetRect)
        drawComments(in: frame, context: context, pathRect: insetRect)
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let index = indexForEvent(event) else {
            dragStartIndex = nil
            selectedRange = nil
            onSelectionChange?(nil)
            needsDisplay = true
            return
        }

        dragStartIndex = index
        let range = NSRange(location: index, length: 0)
        if selectedRange != range {
            selectedRange = range
            onSelectionChange?(range)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartIndex, let end = indexForEvent(event) else { return }
        let lower = min(start, end)
        let upper = max(start, end)
        let range = NSRange(location: lower, length: max(0, upper - lower))
        if selectedRange != range {
            selectedRange = range
            onSelectionChange?(range.length > 0 ? range : nil)
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        guard let index = indexForEvent(event),
              let range = wordRange(at: index) else {
            requestContextMenu(locationInWindow: event.locationInWindow, selectedRange: selectedRange)
            return
        }

        let intersectsSelection = selectedRange
            .map { NSIntersectionRange($0, range).length > 0 } ?? false

        if !intersectsSelection, selectedRange != range {
            selectedRange = range
            onSelectionChange?(range)
            needsDisplay = true
        } else if intersectsSelection, let selectedRange, selectedRange.length > 0 {
            onSelectionChange?(selectedRange)
        }

        requestContextMenu(locationInWindow: event.locationInWindow, selectedRange: selectedRange)
    }

    override func mouseUp(with _: NSEvent) {
        defer {
            dragStartIndex = nil
        }

        guard dragStartIndex != nil,
              let selectedRange,
              selectedRange.length > 0 else {
            return
        }

        onSelectionChange?(selectedRange)

        showSelectionContextMenu()
    }

    private func showSelectionContextMenu() {
        guard let window else {
            return
        }

        let locationInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        requestContextMenu(locationInWindow: locationInWindow, selectedRange: selectedRange)
    }

    private func requestContextMenu(locationInWindow: NSPoint, selectedRange: NSRange?) {
        guard let window else {
            return
        }

        let nonEmptySelection = selectedRange.flatMap { range in
            range.length > 0 ? range : nil
        }

        onContextMenuRequest?(
            ECContextMenuRequest(
                windowNumber: window.windowNumber,
                locationInWindow: locationInWindow,
                selectedRange: nonEmptySelection
            )
        )
    }

    private func buildAttributedString() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(3, fontSize * 0.18)

        let mutable = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        )

        for item in markups {
            guard item.range.location != NSNotFound,
                  item.range.location + item.range.length <= mutable.length else {
                continue
            }

            switch item.type {
            case .block:
                mutable.addAttribute(.backgroundColor, value: item.color, range: item.range)
            case .underline:
                mutable.addAttribute(.underlineColor, value: item.color, range: item.range)
                mutable.addAttribute(.underlineStyle, value: underlineStyleValue(for: item.thickness), range: item.range)
            }
        }

        return mutable
    }

    private func underlineStyleValue(for thickness: ECMarkup.Thickness) -> Int {
        switch thickness {
        case .thin1:
            return NSUnderlineStyle.single.rawValue
        case .thin2:
            return NSUnderlineStyle.thick.rawValue
        }
    }

    private func frameForCurrentContent(in rect: CGRect) -> CTFrame {
        let styleKey = styleKeyForCurrentContent()
        let key = LayoutCacheKey(
            styleKey: styleKey,
            contentWidth: rect.width,
            markupVersion: markupVersion
        )

        if let cachedFrameKey,
           cachedFrameKey == key,
           let cachedFrame {
            return cachedFrame
        }

        let attributed = buildAttributedString()
        let frame = makeFrame(for: attributed, in: rect)

        cachedFrameKey = key
        cachedFrame = frame

        return frame
    }

    private func styleKeyForCurrentContent() -> TextStyleCacheKey {
        TextStyleCacheKey(
            text: text,
            fontSize: fontSize,
            colorToken: colorToken(for: textColor)
        )
    }

    private func invalidateTextLayoutCache() {
        invalidateCTFrameCache()
        cachedHeightKey = nil
        cachedSuggestedHeight = nil
    }

    private func requestRenderUpdate(affectsIntrinsicSize: Bool, shouldDisplay: Bool) {
        if affectsIntrinsicSize {
            invalidateIntrinsicContentSize()
        }
        if shouldDisplay {
            needsDisplay = true
        }
    }

    private func invalidateCTFrameCache() {
        cachedFrameKey = nil
        cachedFrame = nil
    }

    private func colorToken(for color: NSColor) -> UInt64 {
        guard let rgb = color.usingColorSpace(.deviceRGB) ?? color.usingColorSpace(.genericRGB) else {
            return 0
        }

        let r = UInt64((rgb.redComponent * 255).rounded())
        let g = UInt64((rgb.greenComponent * 255).rounded())
        let b = UInt64((rgb.blueComponent * 255).rounded())
        let a = UInt64((rgb.alphaComponent * 255).rounded())
        return (r << 24) | (g << 16) | (b << 8) | a
    }

    private func suggestedTextHeight(for width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }

        let key = LayoutCacheKey(
            styleKey: styleKeyForCurrentContent(),
            contentWidth: width,
            markupVersion: markupVersion
        )
        if let cachedHeightKey,
           cachedHeightKey == key,
           let cachedSuggestedHeight {
            return cachedSuggestedHeight
        }

        let attributed = buildAttributedString()
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let target = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            nil,
            target,
            nil
        )
        let measured = ceil(size.height)
        cachedHeightKey = key
        cachedSuggestedHeight = measured
        return measured
    }

    private func makeFrame(for string: NSAttributedString, in rect: CGRect) -> CTFrame {
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: rect, transform: nil)
        return CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: string.length), path, nil)
    }

    private func wordRange(at index: Int) -> NSRange? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        var probe = min(max(0, index), nsText.length - 1)

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

        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private func isWordCharacter(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return false }
        return wordCharacterSet.contains(scalar)
    }

    private func indexForEvent(_ event: NSEvent) -> Int? {
        guard !text.isEmpty else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let insetRect = bounds.insetBy(dx: 12, dy: 12)
        let frame = frameForCurrentContent(in: insetRect)
        return indexForPoint(point, in: frame, pathRect: insetRect)
    }

    private func indexForPoint(_ point: CGPoint, in frame: CTFrame, pathRect: CGRect) -> Int? {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return nil }

        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        for (idx, line) in lines.enumerated() {
            let origin = origins[idx]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            let lineRect = CGRect(
                x: pathRect.minX + origin.x,
                y: pathRect.minY + origin.y - descent,
                width: pathRect.width,
                height: ascent + descent + leading
            )

            if lineRect.contains(point) {
                let local = CGPoint(x: point.x - lineRect.minX, y: point.y - (pathRect.minY + origin.y))
                let value = stringIndexIfHitText(line: line, local: local)
                if value != kCFNotFound {
                    return value
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

    private func drawSelection(in frame: CTFrame, context: CGContext, pathRect: CGRect) {
        guard let range = selectedRange, range.length > 0 else { return }
        let rects = rects(for: range, in: frame, pathRect: pathRect)
        context.setFillColor(NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35).cgColor)
        for rect in rects {
            context.fill(rect)
        }
    }

    private func drawComments(in frame: CTFrame, context: CGContext, pathRect: CGRect) {
        for item in comments {
            guard item.range.length > 0 else { continue }
            guard let anchor = rects(for: item.range, in: frame, pathRect: pathRect).first else { continue }

            let style = NSMutableParagraphStyle()
            style.alignment = .left
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: item.color,
                .paragraphStyle: style
            ]
            let str = NSAttributedString(string: item.text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(str)

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

            let maxY = bounds.maxY - ascent - descent - 2
            let drawPoint = CGPoint(
                x: min(anchor.minX, bounds.maxX - width - 12),
                y: min(maxY, anchor.maxY + 3)
            )

            context.textPosition = drawPoint
            CTLineDraw(line, context)
        }
    }

    private func rects(for selected: NSRange, in frame: CTFrame, pathRect: CGRect) -> [CGRect] {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return [] }

        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        var rects: [CGRect] = []

        for (index, line) in lines.enumerated() {
            let lineRange = CTLineGetStringRange(line)
            let lineNSRange = NSRange(location: lineRange.location, length: lineRange.length)
            let intersection = NSIntersectionRange(lineNSRange, selected)
            if intersection.length == 0 { continue }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)

            let startOffset = CTLineGetOffsetForStringIndex(line, intersection.location, nil)
            let endOffset = CTLineGetOffsetForStringIndex(line, intersection.location + intersection.length, nil)

            let origin = origins[index]
            let baseX = pathRect.minX + origin.x
            let baseY = pathRect.minY + origin.y

            let rect = CGRect(
                x: baseX + startOffset,
                y: baseY - descent,
                width: max(CGFloat(1), endOffset - startOffset),
                height: ascent + descent
            )
            rects.append(rect)
        }

        return rects
    }
}

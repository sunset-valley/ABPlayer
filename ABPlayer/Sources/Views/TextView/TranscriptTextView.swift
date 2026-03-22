import AppKit
import OSLog
import SwiftUI

/// A single `NSScrollView + NSTextView` that renders every subtitle cue in one
/// continuous text buffer, enabling cross-cue (multi-line) text selection.
///
/// - **Performance**: one text-view instead of *N* text-views; the attributed
///   string is rebuilt only when cues, annotations, or font size change.
/// - **Selection**: drag anywhere across cue boundaries; the selection is
///   reported as a `CrossCueTextSelection` split by cue.
/// - **Annotations**: annotation colours are applied inline; clearing the
///   selection restores them correctly.
/// - **Scrolling**: the view scrolls to the active cue automatically; a live-
///   scroll notification fires `onUserScrolled` so the view-model can pause
///   auto-scrolling.
struct TranscriptTextView: NSViewRepresentable {

  struct PopoverAnchors: Equatable {
    let bottom: CGPoint
    let top: CGPoint
  }

  // MARK: - Inputs

  let cues: [SubtitleCue]
  let fontSize: Double
  let activeCueID: UUID?
  let isUserScrolling: Bool
  let textSelection: SubtitleViewModel.TextSelectionState
  let annotationVersion: Int
  let annotationsProvider: (UUID) -> [AnnotationRenderData]

  // MARK: - Callbacks

  let onSelectionChanged: (CrossCueTextSelection?) -> Void
  let onPopoverAnchorChanged: (PopoverAnchors?) -> Void
  let onAnnotationTapped: (UUID, CrossCueTextSelection, AnnotationRenderData) -> Void
  let onCueTap: (UUID, Double) -> Void
  let onUserScrolled: () -> Void
  let onEditSubtitleRequested: (UUID) -> Void

  // MARK: - NSViewRepresentable

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.backgroundColor = .clear
    scrollView.drawsBackground = false
    scrollView.setAccessibilityIdentifier("subtitle-transcript-scroll-view")

    let layoutManager = TranscriptLayoutManager()
    let textContainer = NSTextContainer()
    layoutManager.addTextContainer(textContainer)

    let textStorage = NSTextStorage()
    textStorage.addLayoutManager(layoutManager)

    let textView = TranscriptNSTextView(frame: .zero, textContainer: textContainer)
    textView.isEditable = false
    textView.isSelectable = false      // We manage selection manually
    textView.backgroundColor = .clear
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 12, height: 8)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.coordinator = context.coordinator
    textView.setAccessibilityIdentifier("subtitle-transcript-text-view")

    scrollView.documentView = textView

    // Detect user live-scroll to pause auto-scroll
    NotificationCenter.default.addObserver(
      context.coordinator,
      selector: #selector(Coordinator.handleLiveScroll(_:)),
      name: NSScrollView.didLiveScrollNotification,
      object: scrollView
    )

    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let coordinator = context.coordinator
    guard let textView = scrollView.documentView as? TranscriptNSTextView else { return }

    // Snapshot old state before mutating
    let oldActiveCueID = coordinator.activeCueID
    let activeCueChanged = oldActiveCueID != activeCueID
    let wasUserScrolling = coordinator.isUserScrolling
    let resumingAutoScroll = wasUserScrolling && !isUserScrolling

    // Full rebuild needed when cues, font, or annotations change — but NOT
    // just because the active cue advanced. Active-cue changes use the fast
    // path below so the entire string is not reconstructed every second.
    let needsFullRebuild =
      coordinator.cachedAttributedString == nil
      || coordinator.cueIDs != cues.map(\.id)
      || coordinator.fontSize != fontSize
      || coordinator.annotationVersion != annotationVersion

    coordinator.cues = cues
    coordinator.cueIDs = cues.map(\.id)
    coordinator.fontSize = fontSize
    coordinator.activeCueID = activeCueID
    coordinator.isUserScrolling = isUserScrolling
    if !isUserScrolling {
      coordinator.didNotifyUserScroll = false
    }
    coordinator.textSelection = textSelection
    coordinator.annotationVersion = annotationVersion
    coordinator.annotationsProvider = annotationsProvider
    coordinator.onSelectionChanged = onSelectionChanged
    coordinator.onPopoverAnchorChanged = onPopoverAnchorChanged
    coordinator.onAnnotationTapped = onAnnotationTapped
    coordinator.onCueTap = onCueTap
    coordinator.onUserScrolled = onUserScrolled
    coordinator.onEditSubtitleRequested = onEditSubtitleRequested

    if needsFullRebuild {
      coordinator.rebuildAttributedString(in: textView)
    } else if activeCueChanged {
      // Fast path: swap highlight on old and new paragraphs only
      coordinator.updateActiveCueHighlight(
        from: oldActiveCueID, to: activeCueID, in: textView)
    }

    // Sync selection highlight from SwiftUI state → NSTextView
    coordinator.syncSelectionHighlight(in: textView)

    // When auto-scroll resumes (button tapped), force an immediate re-scroll
    if resumingAutoScroll {
      coordinator.lastScrolledCueID = nil
    }

    // Auto-scroll to active cue when not user-scrolling
    if !isUserScrolling, let cueID = activeCueID {
      coordinator.scrollToActiveCue(cueID, in: scrollView)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      cues: cues,
      fontSize: fontSize,
      activeCueID: activeCueID,
      annotationVersion: annotationVersion,
      annotationsProvider: annotationsProvider,
      onSelectionChanged: onSelectionChanged,
      onPopoverAnchorChanged: onPopoverAnchorChanged,
      onAnnotationTapped: onAnnotationTapped,
      onCueTap: onCueTap,
      onUserScrolled: onUserScrolled,
      onEditSubtitleRequested: onEditSubtitleRequested
    )
  }

  // MARK: - Coordinator

  @MainActor
  final class Coordinator: NSObject {
    // Inputs (mirrored from the struct so we can diff)
    var cues: [SubtitleCue]
    var cueIDs: [UUID]
    var fontSize: Double
    var activeCueID: UUID?
    var isUserScrolling = false
    var textSelection: SubtitleViewModel.TextSelectionState = .none
    var annotationVersion: Int
    var annotationsProvider: (UUID) -> [AnnotationRenderData]

    // Callbacks
    var onSelectionChanged: (CrossCueTextSelection?) -> Void
    var onPopoverAnchorChanged: (PopoverAnchors?) -> Void
    var onAnnotationTapped: (UUID, CrossCueTextSelection, AnnotationRenderData) -> Void
    var onCueTap: (UUID, Double) -> Void
    var onUserScrolled: () -> Void
    var onEditSubtitleRequested: (UUID) -> Void

    // Build cache
    var layouts: [CueLayout] = []
    var cachedAttributedString: NSAttributedString?

    // Drag-selection state
    var dragAnchorIndex: Int?
    var isDragging = false
    var activeSelectionRange: NSRange?

    // Highlight book-keeping
    var selectionHighlightRange: NSRange?

    // Scroll deduplication
    var lastScrolledCueID: UUID?
    var didNotifyUserScroll = false

    // MARK: Init

    init(
      cues: [SubtitleCue],
      fontSize: Double,
      activeCueID: UUID?,
      annotationVersion: Int,
      annotationsProvider: @escaping (UUID) -> [AnnotationRenderData],
      onSelectionChanged: @escaping (CrossCueTextSelection?) -> Void,
      onPopoverAnchorChanged: @escaping (PopoverAnchors?) -> Void,
      onAnnotationTapped: @escaping (UUID, CrossCueTextSelection, AnnotationRenderData) -> Void,
      onCueTap: @escaping (UUID, Double) -> Void,
      onUserScrolled: @escaping () -> Void,
      onEditSubtitleRequested: @escaping (UUID) -> Void
    ) {
      self.cues = cues
      self.cueIDs = cues.map(\.id)
      self.fontSize = fontSize
      self.activeCueID = activeCueID
      self.annotationVersion = annotationVersion
      self.annotationsProvider = annotationsProvider
      self.onSelectionChanged = onSelectionChanged
      self.onPopoverAnchorChanged = onPopoverAnchorChanged
      self.onAnnotationTapped = onAnnotationTapped
      self.onCueTap = onCueTap
      self.onUserScrolled = onUserScrolled
      self.onEditSubtitleRequested = onEditSubtitleRequested
    }

    // MARK: - Build

    func rebuildAttributedString(in textView: TranscriptNSTextView) {
      let builder = UnifiedStringBuilder(
        cues: cues,
        fontSize: fontSize,
        activeCueID: activeCueID,
        annotationsProvider: annotationsProvider
      )
      let result = builder.build()
      cachedAttributedString = result.attributedString
      layouts = result.layouts

      textView.textStorage?.setAttributedString(result.attributedString)

      // Clear stale selection state after a full rebuild
      activeSelectionRange = nil
      selectionHighlightRange = nil
      lastScrolledCueID = nil
    }

    // MARK: - Selection sync

    /// Reflect the SwiftUI `textSelection` state into the NSTextView highlight.
    func syncSelectionHighlight(in textView: TranscriptNSTextView) {
      switch textSelection {
      case .none:
        if selectionHighlightRange != nil {
          textView.clearSelectionHighlight(coordinator: self)
          activeSelectionRange = nil
        }
      case let .selecting(selection), let .annotationSelected(_, selection):
        let globalRange = selection.globalRange
        if activeSelectionRange != globalRange {
          textView.clearSelectionHighlight(coordinator: self)
          textView.applySelectionHighlight(globalRange, coordinator: self)
          activeSelectionRange = globalRange
        }
      }
    }

    // MARK: - Active cue highlight (fast path)

    /// Swap the active-cue background and text colour for just the two affected
    /// paragraphs — no full string rebuild required.
    func updateActiveCueHighlight(
      from oldCueID: UUID?, to newCueID: UUID?,
      in textView: TranscriptNSTextView
    ) {
      guard let textStorage = textView.textStorage else { return }

      textStorage.beginEditing()
      defer { textStorage.endEditing() }

      if let oldID = oldCueID,
        let layout = layouts.first(where: { $0.cueID == oldID })
      {
        applyInactiveStyle(to: layout, in: textStorage)
      }
      if let newID = newCueID,
        let layout = layouts.first(where: { $0.cueID == newID })
      {
        applyActiveStyle(to: layout, in: textStorage)
      }
    }

    private func applyActiveStyle(to layout: CueLayout, in textStorage: NSTextStorage) {
      let strLen = textStorage.length
      guard layout.paragraphRange.location + layout.paragraphRange.length <= strLen else { return }

      textStorage.addAttribute(
        .backgroundColor,
        value: NSColor.controlAccentColor.withAlphaComponent(0.12),
        range: layout.paragraphRange
      )
      textStorage.addAttribute(
        .foregroundColor, value: NSColor.labelColor, range: layout.paragraphRange)
      reapplyAnnotationAttributesForCue(layout, in: textStorage)
    }

    private func applyInactiveStyle(to layout: CueLayout, in textStorage: NSTextStorage) {
      let strLen = textStorage.length
      guard layout.paragraphRange.location + layout.paragraphRange.length <= strLen else { return }

      textStorage.removeAttribute(.backgroundColor, range: layout.paragraphRange)
      textStorage.addAttribute(
        .foregroundColor, value: NSColor.secondaryLabelColor, range: layout.paragraphRange)
      reapplyAnnotationAttributesForCue(layout, in: textStorage)
    }

    /// Re-apply annotation foreground, background and underline so they are not
    /// lost when the base text colour is changed.
    private func reapplyAnnotationAttributesForCue(
      _ layout: CueLayout, in textStorage: NSTextStorage
    ) {
      let strLen = textStorage.length
      for annotation in annotationsProvider(layout.cueID).sorted(by: { $0.range.location < $1.range.location }) {
        let globalRange = layout.globalRange(from: annotation.range)
        guard globalRange.location >= 0,
          globalRange.location + globalRange.length <= strLen
        else { continue }

        let style = AnnotationStyleResolver.resolve(annotation)
        AnnotationAttributeApplicator.apply(
          style: style,
          to: textStorage,
          range: globalRange
        )
      }
    }

    // MARK: - Scroll

    func scrollToActiveCue(_ cueID: UUID, in scrollView: NSScrollView) {
      guard cueID != lastScrolledCueID,
        let layout = layouts.first(where: { $0.cueID == cueID }),
        let textView = scrollView.documentView as? TranscriptNSTextView,
        let layoutManager = textView.layoutManager,
        let textContainer = textView.textContainer
      else { return }

      lastScrolledCueID = cueID

      // Ensure layout is up to date before measuring
      layoutManager.ensureLayout(for: textContainer)

      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: layout.paragraphRange, actualCharacterRange: nil)
      guard glyphRange.length > 0 else { return }

      var paraRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
      let inset = textView.textContainerInset
      paraRect.origin.x += inset.width
      paraRect.origin.y += inset.height

      // Center the paragraph in the visible clip area
      let visibleHeight = scrollView.contentView.bounds.height
      let targetY = paraRect.midY - visibleHeight / 2
      let maxY = max(0, textView.frame.height - visibleHeight)
      let centeredY = max(0, min(targetY, maxY))

      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.3
        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: centeredY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
    }

    // MARK: - Selection building

    /// Build a `CrossCueTextSelection` from a raw global character range.
    func buildSelection(from globalRange: NSRange) -> CrossCueTextSelection? {
      guard let attrStr = cachedAttributedString else { return nil }
      let fullStr = attrStr.string as NSString
      let strLen = fullStr.length
      guard globalRange.location >= 0,
        globalRange.location + globalRange.length <= strLen,
        globalRange.length > 0
      else { return nil }

      let fullText = fullStr.substring(with: globalRange)

      var segments: [CrossCueTextSelection.CueSegment] = []
      for layout in layouts {
        guard let localRange = layout.localRange(from: globalRange) else { continue }
        let segText = (layout.cueText as NSString).substring(with: localRange)
        segments.append(
          CrossCueTextSelection.CueSegment(
            cueID: layout.cueID,
            cueStartTime: layout.startTime,
            cueEndTime: layout.endTime,
            localRange: localRange,
            text: segText
          )
        )
      }

      guard !segments.isEmpty else { return nil }
      return CrossCueTextSelection(
        segments: segments,
        fullText: fullText,
        globalRange: globalRange
      )
    }

    // MARK: - Layout lookup

    /// Find the `CueLayout` whose paragraph range contains `charIndex`.
    func cueLayout(at charIndex: Int) -> CueLayout? {
      // Binary search for performance with large transcripts
      var lo = 0, hi = layouts.count - 1
      while lo <= hi {
        let mid = (lo + hi) / 2
        let layout = layouts[mid]
        if charIndex < layout.paragraphRange.location {
          hi = mid - 1
        } else if charIndex >= layout.paragraphRange.location + layout.paragraphRange.length {
          lo = mid + 1
        } else {
          return layout
        }
      }
      return nil
    }

    /// Find an existing annotation at a global character index.
    struct AnnotationHit {
      let annotation: AnnotationRenderData
      let selection: CrossCueTextSelection
      let globalRange: NSRange
    }

    func findAnnotationHit(
      at charIndex: Int
    ) -> AnnotationHit? {
      guard let layout = cueLayout(at: charIndex),
        layout.containsTextIndex(charIndex)
      else { return nil }

      let localIndex = charIndex - layout.textRange.location
      for annotation in annotationsProvider(layout.cueID) {
        let r = annotation.range
        if localIndex >= r.location && localIndex < r.location + r.length {
          return buildAnnotationHit(
            for: annotation,
            fallbackLayout: layout
          )
        }
      }
      return nil
    }

    private func buildAnnotationHit(
      for tappedAnnotation: AnnotationRenderData,
      fallbackLayout: CueLayout
    ) -> AnnotationHit? {
      var ranges: [(layout: CueLayout, annotation: AnnotationRenderData)] = []

      for layout in layouts {
        for annotation in annotationsProvider(layout.cueID) where annotation.groupID == tappedAnnotation.groupID {
          ranges.append((layout, annotation))
        }
      }

      guard !ranges.isEmpty else {
        let fallbackRange = fallbackLayout.globalRange(from: tappedAnnotation.range)
        let fallbackSelection = CrossCueTextSelection(
          segments: [
            .init(
              cueID: fallbackLayout.cueID,
              cueStartTime: fallbackLayout.startTime,
              cueEndTime: fallbackLayout.endTime,
              localRange: tappedAnnotation.range,
              text: tappedAnnotation.selectedText
            )
          ],
          fullText: tappedAnnotation.selectedText,
          globalRange: fallbackRange
        )
        return AnnotationHit(
          annotation: tappedAnnotation,
          selection: fallbackSelection,
          globalRange: fallbackRange
        )
      }

      ranges.sort {
        if $0.layout.textRange.location == $1.layout.textRange.location {
          return $0.annotation.range.location < $1.annotation.range.location
        }
        return $0.layout.textRange.location < $1.layout.textRange.location
      }

      var segments: [CrossCueTextSelection.CueSegment] = []
      var minStart = Int.max
      var maxEnd = Int.min

      for (layout, annotation) in ranges {
        let localRange = annotation.range
        let globalRange = layout.globalRange(from: localRange)
        minStart = min(minStart, globalRange.location)
        maxEnd = max(maxEnd, globalRange.location + globalRange.length)

        let cueNSString = layout.cueText as NSString
        guard localRange.location >= 0,
          localRange.location + localRange.length <= cueNSString.length
        else { continue }

        let text = cueNSString.substring(with: localRange)
        segments.append(
          .init(
            cueID: layout.cueID,
            cueStartTime: layout.startTime,
            cueEndTime: layout.endTime,
            localRange: localRange,
            text: text
          )
        )
      }

      guard !segments.isEmpty,
        minStart <= maxEnd
      else { return nil }

      let mergedRange = NSRange(location: minStart, length: maxEnd - minStart)
      let fullText = segments.map(\.text).joined(separator: "\n")
      let selection = CrossCueTextSelection(
        segments: segments,
        fullText: fullText,
        globalRange: mergedRange
      )

      return AnnotationHit(
        annotation: tappedAnnotation,
        selection: selection,
        globalRange: mergedRange
      )
    }

    func popoverAnchors(for globalRange: NSRange, in textView: NSTextView) -> PopoverAnchors? {
      guard let textStorage = textView.textStorage,
        let layoutManager = textView.layoutManager,
        let textContainer = textView.textContainer,
        let scrollView = textView.enclosingScrollView
      else { return nil }

      let strLen = textStorage.length
      guard globalRange.location >= 0,
        globalRange.length > 0,
        globalRange.location + globalRange.length <= strLen
      else { return nil }

      layoutManager.ensureLayout(for: textContainer)
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: globalRange,
        actualCharacterRange: nil
      )
      guard glyphRange.length > 0 else { return nil }

      let clipView = scrollView.contentView
      let clipBounds = clipView.bounds

      func distanceFromTop(y: CGFloat) -> CGFloat {
        if clipView.isFlipped {
          return y - clipBounds.minY
        }
        return clipBounds.maxY - y
      }

      func rectInClipCoordinates(from textContainerRect: CGRect) -> CGRect {
        let rectInTextView = textContainerRect.offsetBy(
          dx: textView.textContainerInset.width,
          dy: textView.textContainerInset.height
        )
        let rectInWindow = textView.convert(rectInTextView, to: nil)
        return clipView.convert(rectInWindow, from: nil)
      }

      var bottomLineMidDistance = -CGFloat.greatestFiniteMagnitude
      var bottomMinX = CGFloat.greatestFiniteMagnitude
      var bottomMaxX = -CGFloat.greatestFiniteMagnitude
      var bottomEdgeDistance = -CGFloat.greatestFiniteMagnitude

      var topLineMidDistance = CGFloat.greatestFiniteMagnitude
      var topMinX = CGFloat.greatestFiniteMagnitude
      var topMaxX = -CGFloat.greatestFiniteMagnitude
      var topEdgeDistance = CGFloat.greatestFiniteMagnitude

      for layout in layouts {
        let textIntersection = NSIntersectionRange(globalRange, layout.textRange)
        guard textIntersection.length > 0 else { continue }

        let textGlyphRange = layoutManager.glyphRange(
          forCharacterRange: textIntersection,
          actualCharacterRange: nil
        )
        guard textGlyphRange.length > 0 else { continue }

        layoutManager.enumerateEnclosingRects(
          forGlyphRange: textGlyphRange,
          withinSelectedGlyphRange: textGlyphRange,
          in: textContainer
        ) { rect, _ in
          guard rect.width > 0, rect.height > 0 else { return }
          let rectInClip = rectInClipCoordinates(from: rect)

          let midDistance = distanceFromTop(y: rectInClip.midY)
          let edgeDistance = clipView.isFlipped
            ? distanceFromTop(y: rectInClip.maxY)
            : distanceFromTop(y: rectInClip.minY)
          let topEdge = clipView.isFlipped
            ? distanceFromTop(y: rectInClip.minY)
            : distanceFromTop(y: rectInClip.maxY)

          if midDistance > bottomLineMidDistance + 0.5 {
            bottomLineMidDistance = midDistance
            bottomMinX = rectInClip.minX
            bottomMaxX = rectInClip.maxX
            bottomEdgeDistance = edgeDistance
          } else if abs(midDistance - bottomLineMidDistance) <= 0.5 {
            bottomMinX = min(bottomMinX, rectInClip.minX)
            bottomMaxX = max(bottomMaxX, rectInClip.maxX)
            bottomEdgeDistance = max(bottomEdgeDistance, edgeDistance)
          }

          if midDistance < topLineMidDistance - 0.5 {
            topLineMidDistance = midDistance
            topMinX = rectInClip.minX
            topMaxX = rectInClip.maxX
            topEdgeDistance = topEdge
          } else if abs(midDistance - topLineMidDistance) <= 0.5 {
            topMinX = min(topMinX, rectInClip.minX)
            topMaxX = max(topMaxX, rectInClip.maxX)
            topEdgeDistance = min(topEdgeDistance, topEdge)
          }
        }
      }

      guard bottomLineMidDistance > -CGFloat.greatestFiniteMagnitude,
        bottomMinX < bottomMaxX,
        topLineMidDistance < CGFloat.greatestFiniteMagnitude,
        topMinX < topMaxX
      else { return nil }

      let bottomX = min(max((bottomMinX + bottomMaxX) / 2 - clipBounds.minX, 0), clipBounds.width)
      let bottomY = min(max(bottomEdgeDistance + 2, 0), clipBounds.height)
      let topX = min(max((topMinX + topMaxX) / 2 - clipBounds.minX, 0), clipBounds.width)
      let topY = min(max(topEdgeDistance, 0), clipBounds.height)

      return PopoverAnchors(
        bottom: CGPoint(x: bottomX, y: bottomY),
        top: CGPoint(x: topX, y: topY)
      )
    }

    // MARK: - Scroll notification

    @objc func handleLiveScroll(_ notification: Notification) {
      guard !didNotifyUserScroll else { return }
      didNotifyUserScroll = true
      onUserScrolled()
    }
  }
}

// MARK: - TranscriptNSTextView

final class TranscriptLayoutManager: NSLayoutManager {
  private func underlineOffset(forGlyphRange glyphRange: NSRange, in textStorage: NSTextStorage) -> CGFloat {
    guard glyphRange.length > 0 else { return 0 }

    let charRange = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    guard charRange.length > 0 else { return 0 }

    let end = charRange.location + charRange.length
    var index = charRange.location

    while index < end {
      var effectiveRange = NSRange(location: 0, length: 0)
      let value = textStorage.attribute(
        AnnotationAttributeApplicator.underlineDrawYOffsetAttribute,
        at: index,
        effectiveRange: &effectiveRange
      ) as? NSNumber

      if let value {
        let offset = CGFloat(truncating: value)
        if offset != 0 {
          return offset
        }
      }

      let next = effectiveRange.location + effectiveRange.length
      index = next > index ? next : index + 1
    }

    return 0
  }

  private func underlineColor(forGlyphRange glyphRange: NSRange, in textStorage: NSTextStorage) -> NSColor {
    guard glyphRange.length > 0 else { return .systemRed }

    let charRange = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    guard charRange.length > 0 else { return .systemRed }

    let end = charRange.location + charRange.length
    var index = charRange.location

    while index < end {
      var effectiveRange = NSRange(location: 0, length: 0)
      let value = textStorage.attribute(
        .underlineColor,
        at: index,
        effectiveRange: &effectiveRange
      ) as? NSColor

      if let value {
        return value
      }

      let next = effectiveRange.location + effectiveRange.length
      index = next > index ? next : index + 1
    }

    return .systemRed
  }

  override func drawUnderline(
    forGlyphRange glyphRange: NSRange,
    underlineType underlineVal: NSUnderlineStyle,
    baselineOffset: CGFloat,
    lineFragmentRect lineRect: NSRect,
    lineFragmentGlyphRange lineGlyphRange: NSRange,
    containerOrigin: NSPoint
  ) {
    let extraOffset: CGFloat
    if let textStorage {
      extraOffset = underlineOffset(forGlyphRange: glyphRange, in: textStorage)
    } else {
      extraOffset = 0
    }

    guard extraOffset != 0,
      let cgContext = NSGraphicsContext.current?.cgContext,
      let textStorage,
      let textContainer = textContainers.first
    else {
      super.drawUnderline(
        forGlyphRange: glyphRange,
        underlineType: underlineVal,
        baselineOffset: baselineOffset,
        lineFragmentRect: lineRect,
        lineFragmentGlyphRange: lineGlyphRange,
        containerOrigin: containerOrigin
      )
      return
    }

    let underlineColor = underlineColor(forGlyphRange: glyphRange, in: textStorage)
    let glyphRect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
    let startX = glyphRect.minX + containerOrigin.x
    let endX = glyphRect.maxX + containerOrigin.x
    let y = lineRect.maxY + containerOrigin.y + extraOffset

    guard endX > startX else { return }

    cgContext.saveGState()
    cgContext.setStrokeColor(underlineColor.cgColor)
    cgContext.setLineWidth(1.5)
    cgContext.setLineCap(.round)
    cgContext.move(to: CGPoint(x: startX, y: y))
    cgContext.addLine(to: CGPoint(x: endX, y: y))
    cgContext.strokePath()
    cgContext.restoreGState()
  }
}

final class TranscriptNSTextView: NSTextView {

  private enum CursorKind {
    case arrow
    case iBeam
  }

  weak var coordinator: TranscriptTextView.Coordinator?
  private var trackingArea: NSTrackingArea?
  private var currentCursorKind: CursorKind?
  private var pendingSelectionRange: NSRange?
  private var isSelectionApplyScheduled = false

  // MARK: - Tracking area

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let options: NSTrackingArea.Options = [
      .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow,
    ]
    trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
    addTrackingArea(trackingArea!)
  }

  // MARK: - Cursor

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    updateCursor(for: point)
  }

  override func mouseEntered(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    updateCursor(for: point)
  }

  override func mouseExited(with event: NSEvent) {
    setCursor(.arrow)
  }

  private func updateCursor(for point: NSPoint) {
    let charIndex = characterIndex(at: point)
    let strLen = textStorage?.length ?? 0
    guard charIndex >= 0, charIndex < strLen, let coordinator else {
      setCursor(.arrow)
      return
    }
    // Show arrow over timestamp prefix, IBeam over cue text
    let isInPrefix: Bool
    if let layout = coordinator.cueLayout(at: charIndex) {
      isInPrefix = charIndex >= layout.prefixRange.location
        && charIndex < layout.prefixRange.location + layout.prefixRange.length
    } else {
      isInPrefix = false
    }
    setCursor(isInPrefix ? .arrow : .iBeam)
  }

  private func setCursor(_ kind: CursorKind) {
    guard currentCursorKind != kind else { return }
    currentCursorKind = kind
    switch kind {
    case .arrow:
      NSCursor.arrow.set()
    case .iBeam:
      NSCursor.iBeam.set()
    }
  }

  // MARK: - Mouse handling

  override func mouseDown(with event: NSEvent) {
    guard let coordinator else { return }

    let point = convert(event.locationInWindow, from: nil)
    let charIndex = characterIndex(at: point)
    guard charIndex >= 0, charIndex < (textStorage?.length ?? 0) else {
      coordinator.onPopoverAnchorChanged(nil)
      coordinator.onSelectionChanged(nil)
      return
    }

    // Tap on an existing annotation → show annotation menu
    if event.clickCount == 1, !event.modifierFlags.contains(.shift) {
      if let hit = coordinator.findAnnotationHit(at: charIndex) {
        coordinator.onPopoverAnchorChanged(
          coordinator.popoverAnchors(for: hit.globalRange, in: self)
        )
        coordinator.onAnnotationTapped(hit.annotation.groupID, hit.selection, hit.annotation)
        return
      }
    }

    // Start drag-selection
    coordinator.onPopoverAnchorChanged(nil)
    coordinator.dragAnchorIndex = charIndex
    coordinator.isDragging = true
    coordinator.activeSelectionRange = nil
    pendingSelectionRange = nil
    isSelectionApplyScheduled = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let coordinator, coordinator.isDragging,
      let anchorIndex = coordinator.dragAnchorIndex
    else { return }

    let point = convert(event.locationInWindow, from: nil)
    let currentIndex = characterIndex(at: point)
    guard currentIndex >= 0, currentIndex < (textStorage?.length ?? 0) else { return }

    // Clamp newline characters out of the selection end so the selection
    // doesn't visually bleed into the next cue's prefix.
    let start = min(anchorIndex, currentIndex)
    let rawEnd = max(anchorIndex, currentIndex)
    let end = clampedEnd(rawEnd)
    guard end > start else { return }

    let range = NSRange(location: start, length: end - start)
    if coordinator.selectionHighlightRange == range {
      coordinator.activeSelectionRange = range
      return
    }
    coordinator.activeSelectionRange = range
    scheduleSelectionHighlightUpdate(range)
  }

  override func mouseUp(with event: NSEvent) {
    guard let coordinator, coordinator.isDragging else { return }
    coordinator.isDragging = false
    flushPendingSelectionHighlightIfNeeded()

    if let selectionRange = coordinator.activeSelectionRange, selectionRange.length > 0 {
      // Drag ended — report cross-cue selection
      if let selection = coordinator.buildSelection(from: selectionRange) {
        coordinator.onPopoverAnchorChanged(
          coordinator.popoverAnchors(for: selectionRange, in: self)
        )
        coordinator.onSelectionChanged(selection)
      } else {
        coordinator.activeSelectionRange = nil
        coordinator.onPopoverAnchorChanged(nil)
        coordinator.onSelectionChanged(nil)
      }
    } else {
      // Pure click (no drag) — report cue tap
      if let anchorIndex = coordinator.dragAnchorIndex,
        let layout = coordinator.cueLayout(at: anchorIndex)
      {
        coordinator.onCueTap(layout.cueID, layout.startTime)
      }
      coordinator.activeSelectionRange = nil
      coordinator.onPopoverAnchorChanged(nil)
      coordinator.onSelectionChanged(nil)
    }

    coordinator.dragAnchorIndex = nil
  }

  // MARK: - Right-click: edit subtitle

  override func rightMouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let charIndex = characterIndex(at: point)

    guard let coordinator,
      let layout = coordinator.cueLayout(at: charIndex)
    else {
      super.rightMouseDown(with: event)
      return
    }

    let menu = NSMenu(title: "")
    let editItem = NSMenuItem(
      title: "Edit Subtitle",
      action: #selector(handleEditSubtitle(_:)),
      keyEquivalent: ""
    )
    editItem.representedObject = layout.cueID
    editItem.target = self
    menu.addItem(editItem)
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }

  @objc private func handleEditSubtitle(_ sender: NSMenuItem) {
    guard let cueID = sender.representedObject as? UUID else { return }
    coordinator?.onEditSubtitleRequested(cueID)
  }

  // MARK: - Selection highlight

  /// Apply a new selection highlight, atomically replacing any previous one.
  ///
  /// Both the clear and the apply are batched inside one
  /// `beginEditing / endEditing` block so the layout manager only performs
  /// a single pass — preventing the "next line flickers" artefact that appears
  /// when two separate attribute mutations trigger two redraws per drag event.
  func applySelectionHighlight(_ range: NSRange, coordinator: TranscriptTextView.Coordinator) {
    guard let textStorage else { return }
    if coordinator.selectionHighlightRange == range { return }

    textStorage.beginEditing()
    defer { textStorage.endEditing() }

    // 1. Clear old highlight (inline so it's batched with step 2)
    if let prev = coordinator.selectionHighlightRange,
      prev.location + prev.length <= textStorage.length
    {
      textStorage.removeAttribute(.backgroundColor, range: prev)
      reapplyAnnotationColors(in: prev, coordinator: coordinator)
      reapplyActiveCueBackground(in: prev, coordinator: coordinator)
    }
    coordinator.selectionHighlightRange = nil

    // 2. Apply new highlight — text ranges only (skip timestamp prefixes)
    let strLen = textStorage.length
    for layout in coordinator.layouts {
      let intersection = NSIntersectionRange(range, layout.textRange)
      guard intersection.length > 0,
        intersection.location + intersection.length <= strLen
      else { continue }
      textStorage.addAttribute(
        .backgroundColor,
        value: NSColor.controlAccentColor.withAlphaComponent(0.25),
        range: intersection
      )
    }
    coordinator.selectionHighlightRange = range
  }

  func clearSelectionHighlight(coordinator: TranscriptTextView.Coordinator) {
    guard let textStorage,
      let prev = coordinator.selectionHighlightRange
    else { return }

    guard prev.location + prev.length <= textStorage.length else {
      coordinator.selectionHighlightRange = nil
      return
    }

    textStorage.beginEditing()
    defer { textStorage.endEditing() }

    textStorage.removeAttribute(.backgroundColor, range: prev)
    reapplyAnnotationColors(in: prev, coordinator: coordinator)
    reapplyActiveCueBackground(in: prev, coordinator: coordinator)

    coordinator.selectionHighlightRange = nil
    pendingSelectionRange = nil
    isSelectionApplyScheduled = false
  }

  // MARK: - Private

  private func characterIndex(at point: NSPoint) -> Int {
    guard let layoutManager, let textContainer else { return -1 }
    let tp = NSPoint(
      x: point.x - textContainerInset.width,
      y: point.y - textContainerInset.height
    )
    return layoutManager.characterIndex(
      for: tp,
      in: textContainer,
      fractionOfDistanceBetweenInsertionPoints: nil
    )
  }

  private func scheduleSelectionHighlightUpdate(_ range: NSRange) {
    pendingSelectionRange = range
    guard !isSelectionApplyScheduled else { return }
    isSelectionApplyScheduled = true

    DispatchQueue.main.async { [weak self] in
      self?.isSelectionApplyScheduled = false
      self?.flushPendingSelectionHighlightIfNeeded()
    }
  }

  private func flushPendingSelectionHighlightIfNeeded() {
    guard let coordinator,
      let pendingSelectionRange
    else { return }
    self.pendingSelectionRange = nil
    applySelectionHighlight(pendingSelectionRange, coordinator: coordinator)
  }

  /// Clamp `end` so it never lands inside a newline or prefix segment, keeping
  /// the selection within actual cue text.
  private func clampedEnd(_ end: Int) -> Int {
    guard let coordinator else { return end }
    guard let layout = coordinator.cueLayout(at: end) else { return end }
    if end >= layout.prefixRange.location
      && end < layout.prefixRange.location + layout.prefixRange.length
    {
      return layout.prefixRange.location
    }
    return end
  }

  private func reapplyAnnotationColors(
    in range: NSRange, coordinator: TranscriptTextView.Coordinator
  ) {
    guard let textStorage else { return }

    for layout in coordinator.layouts {
      guard NSIntersectionRange(range, layout.textRange).length > 0 else { continue }

      for annotation in coordinator.annotationsProvider(layout.cueID) {
        let globalAnnotRange = layout.globalRange(from: annotation.range)
        let intersection = NSIntersectionRange(range, globalAnnotRange)
        guard intersection.length > 0 else { continue }

        let style = AnnotationStyleResolver.resolve(annotation)
        AnnotationAttributeApplicator.reapplyBackgroundOnly(
          style: style,
          to: textStorage,
          range: intersection
        )
      }
    }
  }

  private func reapplyActiveCueBackground(
    in range: NSRange, coordinator: TranscriptTextView.Coordinator
  ) {
    guard let textStorage,
      let activeCueID = coordinator.activeCueID,
      let activeLayout = coordinator.layouts.first(where: { $0.cueID == activeCueID })
    else { return }

    let intersection = NSIntersectionRange(range, activeLayout.paragraphRange)
    guard intersection.length > 0 else { return }

    textStorage.addAttribute(
      .backgroundColor,
      value: NSColor.controlAccentColor.withAlphaComponent(0.12),
      range: intersection
    )
  }

}

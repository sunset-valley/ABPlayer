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
  let colorConfig: AnnotationColorConfig
  let annotationVersion: Int
  let annotationsProvider: (UUID) -> [AnnotationDisplayData]

  // MARK: - Callbacks

  let onSelectionChanged: (CrossCueTextSelection?) -> Void
  let onPopoverAnchorChanged: (PopoverAnchors?) -> Void
  let onAnnotationTapped: (UUID, AnnotationDisplayData) -> Void
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

    let textView = TranscriptNSTextView()
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
    coordinator.textSelection = textSelection
    coordinator.colorConfig = colorConfig
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
      colorConfig: colorConfig,
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
    var colorConfig: AnnotationColorConfig
    var annotationVersion: Int
    var annotationsProvider: (UUID) -> [AnnotationDisplayData]

    // Callbacks
    var onSelectionChanged: (CrossCueTextSelection?) -> Void
    var onPopoverAnchorChanged: (PopoverAnchors?) -> Void
    var onAnnotationTapped: (UUID, AnnotationDisplayData) -> Void
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

    // MARK: Init

    init(
      cues: [SubtitleCue],
      fontSize: Double,
      activeCueID: UUID?,
      colorConfig: AnnotationColorConfig,
      annotationVersion: Int,
      annotationsProvider: @escaping (UUID) -> [AnnotationDisplayData],
      onSelectionChanged: @escaping (CrossCueTextSelection?) -> Void,
      onPopoverAnchorChanged: @escaping (PopoverAnchors?) -> Void,
      onAnnotationTapped: @escaping (UUID, AnnotationDisplayData) -> Void,
      onCueTap: @escaping (UUID, Double) -> Void,
      onUserScrolled: @escaping () -> Void,
      onEditSubtitleRequested: @escaping (UUID) -> Void
    ) {
      self.cues = cues
      self.cueIDs = cues.map(\.id)
      self.fontSize = fontSize
      self.activeCueID = activeCueID
      self.colorConfig = colorConfig
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
        annotationsProvider: annotationsProvider,
        colorConfig: colorConfig
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
      case .none, .annotationSelected:
        if selectionHighlightRange != nil {
          textView.clearSelectionHighlight(coordinator: self)
          activeSelectionRange = nil
        }
      case let .selecting(selection):
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

        let color = colorConfig.color(for: annotation.type)
        textStorage.addAttribute(.foregroundColor, value: color, range: globalRange)
        textStorage.addAttribute(
          .backgroundColor, value: color.withAlphaComponent(0.15), range: globalRange)
        textStorage.addAttribute(
          .underlineStyle, value: NSUnderlineStyle.single.rawValue, range: globalRange)
        textStorage.addAttribute(
          .underlineColor, value: color.withAlphaComponent(0.6), range: globalRange)
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
    func findAnnotation(
      at charIndex: Int
    ) -> (cueID: UUID, annotation: AnnotationDisplayData, globalRange: NSRange)? {
      guard let layout = cueLayout(at: charIndex),
        layout.containsTextIndex(charIndex)
      else { return nil }

      let localIndex = charIndex - layout.textRange.location
      for annotation in annotationsProvider(layout.cueID) {
        let r = annotation.range
        if localIndex >= r.location && localIndex < r.location + r.length {
          return (
            cueID: layout.cueID,
            annotation: annotation,
            globalRange: layout.globalRange(from: annotation.range)
          )
        }
      }
      return nil
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
      onUserScrolled()
    }
  }
}

// MARK: - TranscriptNSTextView

final class TranscriptNSTextView: NSTextView {

  weak var coordinator: TranscriptTextView.Coordinator?
  private var trackingArea: NSTrackingArea?

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
    NSCursor.arrow.set()
  }

  private func updateCursor(for point: NSPoint) {
    let charIndex = characterIndex(at: point)
    let strLen = textStorage?.length ?? 0
    guard charIndex >= 0, charIndex < strLen, let coordinator else {
      NSCursor.arrow.set()
      return
    }
    // Show arrow over timestamp prefix, IBeam over cue text
    let isInPrefix = coordinator.layouts.contains {
      charIndex >= $0.prefixRange.location
        && charIndex < $0.prefixRange.location + $0.prefixRange.length
    }
    (isInPrefix ? NSCursor.arrow : NSCursor.iBeam).set()
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
      if let hit = coordinator.findAnnotation(at: charIndex) {
        coordinator.onPopoverAnchorChanged(
          coordinator.popoverAnchors(for: hit.globalRange, in: self)
        )
        coordinator.onAnnotationTapped(hit.cueID, hit.annotation)
        return
      }
    }

    // Start drag-selection
    coordinator.onPopoverAnchorChanged(nil)
    coordinator.dragAnchorIndex = charIndex
    coordinator.isDragging = true
    coordinator.activeSelectionRange = nil
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
    coordinator.activeSelectionRange = range
    applySelectionHighlight(range, coordinator: coordinator)
  }

  override func mouseUp(with event: NSEvent) {
    guard let coordinator, coordinator.isDragging else { return }
    coordinator.isDragging = false

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

  /// Clamp `end` so it never lands inside a newline or prefix segment, keeping
  /// the selection within actual cue text.
  private func clampedEnd(_ end: Int) -> Int {
    guard let coordinator else { return end }
    // If end is inside a prefix range, clamp to the previous text range end
    for layout in coordinator.layouts {
      if end >= layout.prefixRange.location
        && end < layout.prefixRange.location + layout.prefixRange.length
      {
        return layout.prefixRange.location
      }
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

        let color = coordinator.colorConfig.color(for: annotation.type)
        textStorage.addAttribute(
          .backgroundColor,
          value: color.withAlphaComponent(0.15),
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

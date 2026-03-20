import AppKit
import OSLog
import SwiftUI

/// A reusable NSViewRepresentable for rendering subtitle text with
/// range selection support and annotation highlighting
struct AnnotatedTextView: NSViewRepresentable {
  let cueID: UUID
  let text: String
  let fontSize: Double
  let isActive: Bool
  let isScrolling: Bool
  let annotations: [AnnotationDisplayData]
  let colorConfig: AnnotationColorConfig
  let annotationVersion: Int
  let onSelectionChanged: (TextSelectionRange?) -> Void
  let onAnnotationTapped: (AnnotationDisplayData) -> Void
  let onHeightChanged: (CGFloat) -> Void

  func makeNSView(context: Context) -> AnnotatedNSTextView {
    let textView = AnnotatedNSTextView()
    textView.isEditable = false
    textView.isSelectable = false
    textView.backgroundColor = .clear
    textView.textContainerInset = NSSize(width: 2, height: 1)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.heightTracksTextView = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.coordinator = context.coordinator

    textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
    textView.setContentCompressionResistancePriority(.required, for: .vertical)

    return textView
  }

  func updateNSView(_ textView: AnnotatedNSTextView, context: Context) {
    let coordinator = context.coordinator
    let needsContentUpdate = coordinator.cachedAttributedString == nil
      || coordinator.cueID != cueID
      || coordinator.fontSize != fontSize
      || coordinator.text != text
      || coordinator.annotationVersion != annotationVersion
      || coordinator.isActive != isActive

    coordinator.cueID = cueID
    coordinator.text = text
    coordinator.fontSize = fontSize
    coordinator.isActive = isActive
    coordinator.isScrolling = isScrolling
    coordinator.annotations = annotations
    coordinator.colorConfig = colorConfig
    coordinator.annotationVersion = annotationVersion
    coordinator.onSelectionChanged = onSelectionChanged
    coordinator.onAnnotationTapped = onAnnotationTapped

    if needsContentUpdate {
      coordinator.cachedSize = nil
      let result = coordinator.buildAttributedString()
      textView.textStorage?.setAttributedString(result)
      textView.invalidateIntrinsicContentSize()
    }

    // Update selection highlight if active
    if let selectionRange = coordinator.activeSelectionRange {
      textView.highlightSelection(selectionRange)
    } else {
      textView.clearSelectionHighlight()
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    nsView: AnnotatedNSTextView,
    context: Context
  ) -> CGSize? {
    guard let layoutManager = nsView.layoutManager,
          let textContainer = nsView.textContainer
    else { return nil }

    guard let width = proposal.width, width.isFinite, width > 0 else {
      assertionFailure("AnnotatedTextView requires a valid proposed width")
      return nil
    }

    if let cachedWidth = context.coordinator.cachedWidth,
       let cachedSize = context.coordinator.cachedSize,
       abs(cachedWidth - width) < 1.0
    {
      return cachedSize
    }

    textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    if usedRect.isEmpty { return nil }

    let inset = nsView.textContainerInset
    let height = usedRect.height + inset.height * 2

    let size = CGSize(width: width, height: height)
    if width.isNormal && height.isNormal {
      context.coordinator.cachedWidth = width
      context.coordinator.cachedSize = size
    }

    DispatchQueue.main.async {
      onHeightChanged(height)
    }

    return size
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      cueID: cueID,
      text: text,
      fontSize: fontSize,
      isActive: isActive,
      annotations: annotations,
      colorConfig: colorConfig,
      annotationVersion: annotationVersion,
      onSelectionChanged: onSelectionChanged,
      onAnnotationTapped: onAnnotationTapped
    )
  }

  // MARK: - Coordinator

  @MainActor
  class Coordinator: NSObject {
    var cueID: UUID
    var text: String
    var fontSize: Double
    var isActive: Bool
    var isScrolling = false
    var annotations: [AnnotationDisplayData]
    var colorConfig: AnnotationColorConfig
    var annotationVersion: Int
    var onSelectionChanged: (TextSelectionRange?) -> Void
    var onAnnotationTapped: (AnnotationDisplayData) -> Void

    var cachedAttributedString: NSAttributedString?
    var cachedWidth: CGFloat?
    var cachedSize: CGSize?
    var activeSelectionRange: NSRange?

    // Drag selection state
    var dragAnchorIndex: Int?
    var isDragging = false

    init(
      cueID: UUID,
      text: String,
      fontSize: Double,
      isActive: Bool,
      annotations: [AnnotationDisplayData],
      colorConfig: AnnotationColorConfig,
      annotationVersion: Int,
      onSelectionChanged: @escaping (TextSelectionRange?) -> Void,
      onAnnotationTapped: @escaping (AnnotationDisplayData) -> Void
    ) {
      self.cueID = cueID
      self.text = text
      self.fontSize = fontSize
      self.isActive = isActive
      self.annotations = annotations
      self.colorConfig = colorConfig
      self.annotationVersion = annotationVersion
      self.onSelectionChanged = onSelectionChanged
      self.onAnnotationTapped = onAnnotationTapped
    }

    func buildAttributedString() -> NSAttributedString {
      if let cached = cachedAttributedString { return cached }

      let defaultColor: NSColor = isActive ? .labelColor : .secondaryLabelColor
      let builder = AnnotatedStringBuilder(
        fontSize: fontSize,
        defaultTextColor: defaultColor,
        annotations: annotations,
        colorConfig: colorConfig
      )
      let result = builder.build(text: text)
      cachedAttributedString = result.attributedString
      return result.attributedString
    }

    func invalidateCache() {
      cachedAttributedString = nil
      cachedSize = nil
    }

    /// Expand a character range to word boundaries
    func expandToWordBoundaries(_ range: NSRange, in text: String) -> NSRange {
      let nsString = text as NSString
      guard range.location >= 0, range.location + range.length <= nsString.length else {
        return range
      }

      let startWordRange = nsString.rangeOfWord(at: range.location)
      let endIndex = range.location + range.length
      let endWordRange = endIndex > 0
        ? nsString.rangeOfWord(at: max(0, endIndex - 1))
        : startWordRange

      let expandedStart = startWordRange.location
      let expandedEnd = endWordRange.location + endWordRange.length
      return NSRange(location: expandedStart, length: expandedEnd - expandedStart)
    }

    /// Find an annotation at a character index
    func findAnnotation(at index: Int) -> AnnotationDisplayData? {
      for annotation in annotations {
        let range = annotation.range
        if index >= range.location && index < range.location + range.length {
          return annotation
        }
      }
      return nil
    }
  }
}

// MARK: - NSString word boundary helper

extension NSString {
  /// Find the word range at a given character index
  func rangeOfWord(at index: Int) -> NSRange {
    guard index >= 0, index < length else {
      return NSRange(location: max(0, index), length: 0)
    }

    var start = index
    var end = index

    // Expand backwards to word start
    while start > 0 {
      let char = character(at: start - 1)
      if CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(char)!) {
        break
      }
      start -= 1
    }

    // Expand forwards to word end
    while end < length {
      let char = character(at: end)
      if CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(char)!) {
        break
      }
      end += 1
    }

    return NSRange(location: start, length: end - start)
  }
}

// MARK: - AnnotatedNSTextView

class AnnotatedNSTextView: NSTextView {
  private static let logger = Logger(subsystem: "com.abplayer", category: "AnnotatedNSTextView")

  weak var coordinator: AnnotatedTextView.Coordinator?
  private var trackingArea: NSTrackingArea?
  private var selectionHighlightRange: NSRange?

  override var firstBaselineOffsetFromTop: CGFloat {
    guard let layoutManager, let textContainer, let textStorage,
          textStorage.length > 0
    else {
      return textContainerInset.height
    }

    let glyphRange = layoutManager.glyphRange(for: textContainer)
    guard glyphRange.length > 0 else { return textContainerInset.height }

    let firstLineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
    let firstLineBaselineOffset = layoutManager.typesetter.baselineOffset(
      in: layoutManager,
      glyphIndex: 0
    )
    return textContainerInset.height + firstLineFragmentRect.origin.y + firstLineBaselineOffset
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    if let trackingArea {
      removeTrackingArea(trackingArea)
    }

    let options: NSTrackingArea.Options = [
      .mouseEnteredAndExited, .activeInKeyWindow,
    ]
    trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
    addTrackingArea(trackingArea!)
  }

  // MARK: - Mouse handling for drag selection

  override func mouseDown(with event: NSEvent) {
    guard let coordinator, !coordinator.isScrolling else { return }

    let point = convert(event.locationInWindow, from: nil)
    let charIndex = characterIndex(at: point)

    guard charIndex >= 0, charIndex < (textStorage?.length ?? 0) else {
      coordinator.onSelectionChanged(nil)
      return
    }

    // Check if tapping an existing annotation
    if event.clickCount == 1, !event.modifierFlags.contains(.shift) {
      if let annotation = coordinator.findAnnotation(at: charIndex) {
        coordinator.onAnnotationTapped(annotation)
        return
      }
    }

    // Begin drag selection
    coordinator.dragAnchorIndex = charIndex
    coordinator.isDragging = true
    coordinator.activeSelectionRange = nil
    clearSelectionHighlight()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let coordinator, coordinator.isDragging,
          let anchorIndex = coordinator.dragAnchorIndex
    else { return }

    let point = convert(event.locationInWindow, from: nil)
    let currentIndex = characterIndex(at: point)

    guard currentIndex >= 0, currentIndex < (textStorage?.length ?? 0) else { return }

    let start = min(anchorIndex, currentIndex)
    let end = max(anchorIndex, currentIndex)
    let rawRange = NSRange(location: start, length: end - start + 1)

    // Expand to word boundaries during drag
    let expandedRange = coordinator.expandToWordBoundaries(rawRange, in: coordinator.text)
    coordinator.activeSelectionRange = expandedRange
    highlightSelection(expandedRange)
  }

  override func mouseUp(with event: NSEvent) {
    guard let coordinator, coordinator.isDragging else { return }
    coordinator.isDragging = false

    guard let selectionRange = coordinator.activeSelectionRange else {
      // Single click without drag — check if we should dismiss
      if let anchorIndex = coordinator.dragAnchorIndex {
        let point = convert(event.locationInWindow, from: nil)
        let currentIndex = characterIndex(at: point)

        // If click didn't move, try single-word selection
        if abs(currentIndex - anchorIndex) <= 1 {
          let wordRange = coordinator.expandToWordBoundaries(
            NSRange(location: anchorIndex, length: 1),
            in: coordinator.text
          )
          if wordRange.length > 0 {
            let nsString = coordinator.text as NSString
            let selectedText = nsString.substring(with: wordRange)
            coordinator.activeSelectionRange = wordRange
            highlightSelection(wordRange)
            coordinator.onSelectionChanged(
              TextSelectionRange(
                cueID: coordinator.cueID,
                range: wordRange,
                selectedText: selectedText
              )
            )
            coordinator.dragAnchorIndex = nil
            return
          }
        }
      }

      coordinator.dragAnchorIndex = nil
      coordinator.onSelectionChanged(nil)
      return
    }

    // Finalize selection
    let nsString = coordinator.text as NSString
    guard selectionRange.location + selectionRange.length <= nsString.length else {
      coordinator.activeSelectionRange = nil
      coordinator.dragAnchorIndex = nil
      clearSelectionHighlight()
      return
    }

    let selectedText = nsString.substring(with: selectionRange)

    coordinator.onSelectionChanged(
      TextSelectionRange(
        cueID: coordinator.cueID,
        range: selectionRange,
        selectedText: selectedText
      )
    )

    coordinator.dragAnchorIndex = nil
  }

  // MARK: - Selection Highlight

  func highlightSelection(_ range: NSRange) {
    guard let textStorage else { return }
    let nsString = textStorage.string as NSString

    // Clear previous selection highlight
    if let prev = selectionHighlightRange, prev.location + prev.length <= nsString.length {
      textStorage.removeAttribute(.backgroundColor, range: prev)
      // Re-apply annotation colors for cleared range
      reapplyAnnotationColors(in: prev)
    }

    guard range.location + range.length <= nsString.length else { return }

    textStorage.addAttribute(
      .backgroundColor,
      value: NSColor.controlAccentColor.withAlphaComponent(0.2),
      range: range
    )

    selectionHighlightRange = range
  }

  func clearSelectionHighlight() {
    guard let textStorage, let prev = selectionHighlightRange else { return }
    let nsString = textStorage.string as NSString
    guard prev.location + prev.length <= nsString.length else {
      selectionHighlightRange = nil
      return
    }

    textStorage.removeAttribute(.backgroundColor, range: prev)
    reapplyAnnotationColors(in: prev)
    selectionHighlightRange = nil
  }

  /// Clear active selection and notify coordinator
  func dismissSelection() {
    coordinator?.activeSelectionRange = nil
    clearSelectionHighlight()
  }

  // MARK: - Private

  private func characterIndex(at point: NSPoint) -> Int {
    guard let layoutManager, let textContainer else { return -1 }
    let textPoint = NSPoint(
      x: point.x - textContainerInset.width,
      y: point.y - textContainerInset.height
    )
    return layoutManager.characterIndex(
      for: textPoint,
      in: textContainer,
      fractionOfDistanceBetweenInsertionPoints: nil
    )
  }

  private func reapplyAnnotationColors(in range: NSRange) {
    guard let coordinator, let textStorage else { return }

    for annotation in coordinator.annotations {
      let annotationRange = annotation.range
      let intersection = NSIntersectionRange(annotationRange, range)
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

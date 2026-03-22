import AppKit
import Foundation

/// Builds a single `NSAttributedString` that concatenates every subtitle cue
/// so that a single `NSTextView` can render the full transcript.
///
/// Each cue occupies one paragraph with the format:
/// ```
///   "0:01\t<cue text>\n"
/// ```
/// A tab-stop at ``timestampColumnWidth`` points aligns cue text into a
/// consistent left column, mirroring the visual layout of the previous
/// per-row implementation.
///
/// Annotation styling (background, underline, coloured text) is layered on top
/// of the base attributes. The active-cue paragraph receives a subtle tinted
/// background.
struct UnifiedStringBuilder {

  // MARK: - Constants

  /// X-position of the tab stop used to align cue text past the timestamp.
  static let timestampColumnWidth: CGFloat = 64

  // MARK: - Inputs

  let cues: [SubtitleCue]
  let fontSize: Double
  let activeCueID: UUID?
  let annotationsProvider: (UUID) -> [AnnotationRenderData]

  // MARK: - Result

  struct BuildResult {
    let attributedString: NSAttributedString
    let layouts: [CueLayout]
  }

  // MARK: - Build

  func build() -> BuildResult {
    let output = NSMutableAttributedString()
    var layouts: [CueLayout] = []
    var offset = 0

    for (index, cue) in cues.enumerated() {
      let layout = appendCue(
        cue,
        at: offset,
        isFirst: index == 0,
        appendingTo: output
      )
      layouts.append(layout)
      offset += layout.paragraphRange.length
    }

    return BuildResult(attributedString: output, layouts: layouts)
  }

  // MARK: - Private helpers

  private func appendCue(
    _ cue: SubtitleCue,
    at offset: Int,
    isFirst: Bool,
    appendingTo result: NSMutableAttributedString
  ) -> CueLayout {
    let isActive = cue.id == activeCueID

    let prefix = timeString(from: cue.startTime) + "\t"
    let text = cue.text
    let newline = "\n"

    // Use NSString lengths for correct UTF-16 code-unit counts.
    let prefixLen = (prefix as NSString).length
    let textLen = (text as NSString).length
    let newlineLen = (newline as NSString).length

    let prefixRange = NSRange(location: offset, length: prefixLen)
    let textRange = NSRange(location: offset + prefixLen, length: textLen)
    let paragraphRange = NSRange(location: offset, length: prefixLen + textLen + newlineLen)

    // MARK: Paragraph style

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 2
    paragraphStyle.tabStops = [
      NSTextTab(textAlignment: .left, location: Self.timestampColumnWidth)
    ]
    paragraphStyle.headIndent = Self.timestampColumnWidth
    if !isFirst {
      paragraphStyle.paragraphSpacingBefore = 8
    }

    // MARK: Timestamp attributes

    let timestampFont = NSFont.monospacedDigitSystemFont(
      ofSize: max(11, fontSize - 4),
      weight: .regular
    )
    let timestampColor: NSColor = isActive ? .labelColor : .secondaryLabelColor

    let prefixAttrs: [NSAttributedString.Key: Any] = [
      .font: timestampFont,
      .foregroundColor: timestampColor,
      .paragraphStyle: paragraphStyle,
    ]

    // MARK: Cue-text attributes

    let textFont = NSFont.systemFont(ofSize: fontSize)
    let textColor: NSColor = isActive ? .labelColor : .secondaryLabelColor

    let textAttrs: [NSAttributedString.Key: Any] = [
      .font: textFont,
      .foregroundColor: textColor,
      .paragraphStyle: paragraphStyle,
    ]

    // MARK: Build mutable pieces

    let prefixStr = NSAttributedString(string: prefix, attributes: prefixAttrs)
    let textStr = NSMutableAttributedString(string: text, attributes: textAttrs)
    let newlineStr = NSAttributedString(string: newline, attributes: textAttrs)

    // MARK: Apply annotation styling to the cue text

    let cueAnnotations = annotationsProvider(cue.id)
      .sorted { $0.range.location < $1.range.location }

    for annotation in cueAnnotations {
      let r = annotation.range
      guard r.location >= 0, r.location + r.length <= textLen else { continue }

      let style = AnnotationStyleResolver.resolve(annotation)
      AnnotationAttributeApplicator.apply(style: style, to: textStr, range: r)
    }

    // MARK: Append to result

    result.append(prefixStr)
    result.append(textStr)
    result.append(newlineStr)

    // MARK: Active-cue paragraph background

    if isActive {
      result.addAttribute(
        .backgroundColor,
        value: NSColor.controlAccentColor.withAlphaComponent(0.12),
        range: paragraphRange
      )
    }

    return CueLayout(
      cueID: cue.id,
      endTime: cue.endTime,
      startTime: cue.startTime,
      cueText: text,
      prefixRange: prefixRange,
      textRange: textRange,
      paragraphRange: paragraphRange
    )
  }

  private func timeString(from value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "0:00" }
    let totalSeconds = Int(value.rounded())
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
  }
}

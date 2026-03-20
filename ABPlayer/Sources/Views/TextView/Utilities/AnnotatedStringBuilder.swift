import AppKit
import Foundation

/// Builds attributed strings for subtitle text with annotation highlighting
struct AnnotatedStringBuilder {
  let fontSize: Double
  let defaultTextColor: NSColor
  let annotations: [AnnotationDisplayData]
  let colorConfig: AnnotationColorConfig

  struct Result {
    let attributedString: NSAttributedString
  }

  /// Build attributed string from full cue text with annotation overlays
  func build(text: String) -> Result {
    let font = NSFont.systemFont(ofSize: fontSize)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 2

    let baseAttributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: defaultTextColor,
      .paragraphStyle: paragraphStyle,
    ]

    let result = NSMutableAttributedString(string: text, attributes: baseAttributes)

    // Apply annotation styling sorted by location (earlier first)
    let sortedAnnotations = annotations.sorted { $0.range.location < $1.range.location }

    for annotation in sortedAnnotations {
      let range = annotation.range
      let nsString = text as NSString

      // Validate range is within bounds
      guard range.location >= 0,
            range.location + range.length <= nsString.length
      else { continue }

      let color = colorConfig.color(for: annotation.type)

      result.addAttribute(
        .backgroundColor,
        value: color.withAlphaComponent(0.15),
        range: range
      )
      result.addAttribute(
        .underlineStyle,
        value: NSUnderlineStyle.single.rawValue,
        range: range
      )
      result.addAttribute(
        .underlineColor,
        value: color.withAlphaComponent(0.6),
        range: range
      )
      result.addAttribute(
        .foregroundColor,
        value: color,
        range: range
      )
    }

    return Result(attributedString: result)
  }
}

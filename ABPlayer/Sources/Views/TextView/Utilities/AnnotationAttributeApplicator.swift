import AppKit
import Foundation

enum AnnotationAttributeApplicator {
  static func apply(
    style: ResolvedAnnotationStyle,
    to textStorage: NSMutableAttributedString,
    range: NSRange
  ) {
    switch style.kind {
    case .underline:
      textStorage.addAttribute(
        .underlineStyle,
        value: NSUnderlineStyle.single.rawValue,
        range: range
      )
      textStorage.addAttribute(
        .underlineColor,
        value: style.underlineColor,
        range: range
      )
    case .background:
      textStorage.addAttribute(
        .backgroundColor,
        value: style.backgroundColor.withAlphaComponent(0.22),
        range: range
      )
    case .underlineAndBackground:
      textStorage.addAttribute(
        .underlineStyle,
        value: NSUnderlineStyle.single.rawValue,
        range: range
      )
      textStorage.addAttribute(
        .underlineColor,
        value: style.underlineColor,
        range: range
      )
      textStorage.addAttribute(
        .backgroundColor,
        value: style.backgroundColor.withAlphaComponent(0.22),
        range: range
      )
    }
  }

  static func reapplyBackgroundOnly(
    style: ResolvedAnnotationStyle,
    to textStorage: NSTextStorage,
    range: NSRange
  ) {
    switch style.kind {
    case .background, .underlineAndBackground:
      textStorage.addAttribute(
        .backgroundColor,
        value: style.backgroundColor.withAlphaComponent(0.22),
        range: range
      )
    case .underline:
      break
    }
  }
}

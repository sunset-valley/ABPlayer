import AppKit
import Foundation

/// Configuration for annotation display colors, customizable per type
struct AnnotationColorConfig: Equatable, Sendable {
  var vocabulary: NSColor
  var collocation: NSColor
  var goodSentence: NSColor

  static let `default` = AnnotationColorConfig(
    vocabulary: .systemRed,
    collocation: .systemBlue,
    goodSentence: .systemYellow
  )

  func color(for type: AnnotationType) -> NSColor {
    switch type {
    case .vocabulary: return vocabulary
    case .collocation: return collocation
    case .goodSentence: return goodSentence
    }
  }
}

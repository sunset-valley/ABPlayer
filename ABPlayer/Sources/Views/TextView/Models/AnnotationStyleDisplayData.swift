import AppKit
import Foundation

struct AnnotationStyleDisplayData: Identifiable, Equatable, Sendable {
  let id: UUID
  let name: String
  let kind: AnnotationStyleKind
  let underlineColorHex: String
  let backgroundColorHex: String
  let sortOrder: Int

  var underlineColor: NSColor {
    NSColor(abHex: underlineColorHex) ?? .systemRed
  }

  var backgroundColor: NSColor {
    NSColor(abHex: backgroundColorHex) ?? .systemBlue
  }
}

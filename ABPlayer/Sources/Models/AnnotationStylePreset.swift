import Foundation
import SwiftData

enum AnnotationStyleKind: String, Codable, CaseIterable, Sendable {
  case underline
  case background
  case underlineAndBackground
}

@Model
final class AnnotationStylePreset {
  var id: UUID
  var name: String
  var kindRawValue: String
  var underlineColorHex: String
  var backgroundColorHex: String
  var sortOrder: Int
  var createdAt: Date
  var updatedAt: Date

  var kind: AnnotationStyleKind {
    get { AnnotationStyleKind(rawValue: kindRawValue) ?? .underlineAndBackground }
    set { kindRawValue = newValue.rawValue }
  }

  init(
    id: UUID = UUID(),
    name: String,
    kind: AnnotationStyleKind,
    underlineColorHex: String,
    backgroundColorHex: String,
    sortOrder: Int,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.kindRawValue = kind.rawValue
    self.underlineColorHex = underlineColorHex
    self.backgroundColorHex = backgroundColorHex
    self.sortOrder = sortOrder
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

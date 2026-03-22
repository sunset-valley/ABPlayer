import AppKit
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AnnotationStyleService {
  private let modelContext: ModelContext
  private var stylesByID: [UUID: AnnotationStylePreset] = [:]

  private(set) var version = 0

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
    refreshCache()
    ensureDefaultPresets()
  }

  func allStyles() -> [AnnotationStyleDisplayData] {
    stylesByID.values
      .sorted {
        if $0.sortOrder == $1.sortOrder {
          return $0.createdAt < $1.createdAt
        }
        return $0.sortOrder < $1.sortOrder
      }
      .map { preset in
        AnnotationStyleDisplayData(
          id: preset.id,
          name: preset.name,
          kind: preset.kind,
          underlineColorHex: preset.underlineColorHex,
          backgroundColorHex: preset.backgroundColorHex,
          sortOrder: preset.sortOrder
        )
      }
  }

  func defaultStyle() -> AnnotationStyleDisplayData {
    guard let style = allStyles().first else {
      let created = addStyle(name: "Style", kind: .underlineAndBackground)
      return created
    }
    return style
  }

  func style(id: UUID) -> AnnotationStyleDisplayData? {
    guard let preset = stylesByID[id] else { return nil }
    return AnnotationStyleDisplayData(
      id: preset.id,
      name: preset.name,
      kind: preset.kind,
      underlineColorHex: preset.underlineColorHex,
      backgroundColorHex: preset.backgroundColorHex,
      sortOrder: preset.sortOrder
    )
  }

  @discardableResult
  func addStyle(
    name: String,
    kind: AnnotationStyleKind,
    underlineColor: NSColor = .systemBlue,
    backgroundColor: NSColor = .systemBlue
  ) -> AnnotationStyleDisplayData {
    let nextSortOrder = (stylesByID.values.map(\.sortOrder).max() ?? -1) + 1
    let now = Date()
    let preset = AnnotationStylePreset(
      name: name,
      kind: kind,
      underlineColorHex: underlineColor.abHexString,
      backgroundColorHex: backgroundColor.abHexString,
      sortOrder: nextSortOrder,
      createdAt: now,
      updatedAt: now
    )
    modelContext.insert(preset)
    stylesByID[preset.id] = preset
    version += 1
    return AnnotationStyleDisplayData(
      id: preset.id,
      name: preset.name,
      kind: preset.kind,
      underlineColorHex: preset.underlineColorHex,
      backgroundColorHex: preset.backgroundColorHex,
      sortOrder: preset.sortOrder
    )
  }

  func updateStyleName(styleID: UUID, name: String) {
    guard let preset = stylesByID[styleID] else { return }
    preset.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "Style"
      : name.trimmingCharacters(in: .whitespacesAndNewlines)
    preset.updatedAt = Date()
    version += 1
  }

  func updateStyleKind(styleID: UUID, kind: AnnotationStyleKind) {
    guard let preset = stylesByID[styleID] else { return }
    preset.kind = kind
    preset.updatedAt = Date()
    version += 1
  }

  func updateUnderlineColor(styleID: UUID, color: NSColor) {
    guard let preset = stylesByID[styleID] else { return }
    preset.underlineColorHex = color.abHexString
    preset.updatedAt = Date()
    version += 1
  }

  func updateBackgroundColor(styleID: UUID, color: NSColor) {
    guard let preset = stylesByID[styleID] else { return }
    preset.backgroundColorHex = color.abHexString
    preset.updatedAt = Date()
    version += 1
  }

  func refreshCache() {
    let descriptor = FetchDescriptor<AnnotationStylePreset>()
    let styles = (try? modelContext.fetch(descriptor)) ?? []
    stylesByID = Dictionary(uniqueKeysWithValues: styles.map { ($0.id, $0) })
    version += 1
  }

  @discardableResult
  func deleteStyle(styleID: UUID, usageCount: Int) -> Bool {
    guard usageCount == 0 else { return false }
    guard stylesByID.count > 1 else { return false }
    guard let preset = stylesByID[styleID] else { return false }

    modelContext.delete(preset)
    stylesByID.removeValue(forKey: styleID)
    version += 1
    return true
  }

  private func ensureDefaultPresets() {
    guard stylesByID.isEmpty else { return }
    let defaults: [(String, AnnotationStyleKind, NSColor, NSColor)] = [
      ("Underline", .underline, .systemRed, .systemRed),
      ("Background", .background, .systemBlue, .systemBlue),
      ("Underline + Background", .underlineAndBackground, .systemYellow, .systemYellow),
    ]
    for (index, item) in defaults.enumerated() {
      let now = Date()
      let preset = AnnotationStylePreset(
        name: item.0,
        kind: item.1,
        underlineColorHex: item.2.abHexString,
        backgroundColorHex: item.3.abHexString,
        sortOrder: index,
        createdAt: now,
        updatedAt: now
      )
      modelContext.insert(preset)
      stylesByID[preset.id] = preset
    }
    version += 1
  }
}

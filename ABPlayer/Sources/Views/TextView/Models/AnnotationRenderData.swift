import Foundation

struct AnnotationRenderData: Identifiable, Equatable, Sendable {
  let id: UUID
  let groupID: UUID
  let stylePresetID: UUID
  let styleName: String
  let styleKind: AnnotationStyleKind
  let underlineColorHex: String
  let backgroundColorHex: String
  let range: NSRange
  let selectedText: String
  let comment: String?

  var styleDisplay: AnnotationStyleDisplayData {
    AnnotationStyleDisplayData(
      id: stylePresetID,
      name: styleName,
      kind: styleKind,
      underlineColorHex: underlineColorHex,
      backgroundColorHex: backgroundColorHex,
      sortOrder: 0
    )
  }

  var resolvedStyle: ResolvedAnnotationStyle {
    ResolvedAnnotationStyle(
      kind: styleKind,
      underlineColor: styleDisplay.underlineColor,
      backgroundColor: styleDisplay.backgroundColor
    )
  }

  init(
    id: UUID,
    groupID: UUID,
    stylePresetID: UUID,
    styleName: String,
    styleKind: AnnotationStyleKind,
    underlineColorHex: String,
    backgroundColorHex: String,
    range: NSRange,
    selectedText: String,
    comment: String?
  ) {
    self.id = id
    self.groupID = groupID
    self.stylePresetID = stylePresetID
    self.styleName = styleName
    self.styleKind = styleKind
    self.underlineColorHex = underlineColorHex
    self.backgroundColorHex = backgroundColorHex
    self.range = range
    self.selectedText = selectedText
    self.comment = comment
  }
}

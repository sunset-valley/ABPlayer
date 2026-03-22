import Foundation
import Observation
import SwiftData

/// Service responsible for managing text annotations on subtitle cues
/// Provides centralized CRUD operations and cache management
@Observable
@MainActor
final class AnnotationService {
  private let modelContext: ModelContext
  private let styleService: AnnotationStyleService

  /// Internal cache mapping cueID to annotation spans
  private var spansByCue: [UUID: [TextAnnotationSpanV2]] = [:]
  private var groupsByID: [UUID: TextAnnotationGroupV2] = [:]

  /// Version counter for cache invalidation - incremented on mutations
  private(set) var version = 0

  init(modelContext: ModelContext, styleService: AnnotationStyleService) {
    self.modelContext = modelContext
    self.styleService = styleService
    refreshCache()
  }

  // MARK: - Public API

  /// Get display data for all annotations in a cue
  func annotations(for cueID: UUID) -> [AnnotationRenderData] {
    let spans = spansByCue[cueID] ?? []
    return spans
      .sorted { $0.rangeLocation < $1.rangeLocation }
      .compactMap(displayData(from:))
  }

  /// Add one logical annotation group and one span per touched cue segment.
  @discardableResult
  func addAnnotation(
    audioFileID: UUID,
    selection: CrossCueTextSelection,
    stylePresetID: UUID
  ) -> [AnnotationRenderData] {
    let now = Date()
    let group = TextAnnotationGroupV2(
      audioFileID: audioFileID,
      stylePresetID: stylePresetID,
      selectedTextSnapshot: selection.fullText,
      createdAt: now,
      updatedAt: now
    )
    modelContext.insert(group)
    groupsByID[group.id] = group

    for (index, segment) in selection.segments.enumerated() {
      let span = TextAnnotationSpanV2(
        groupID: group.id,
        audioFileID: audioFileID,
        cueID: segment.cueID,
        cueStartTime: segment.cueStartTime,
        cueEndTime: segment.cueEndTime,
        rangeLocation: segment.localRange.location,
        rangeLength: segment.localRange.length,
        segmentOrder: index,
        createdAt: now,
        updatedAt: now
      )
      modelContext.insert(span)
      spansByCue[segment.cueID, default: []].append(span)
    }

    version += 1
    return annotations(inGroup: group.id)
  }

  func annotations(inGroup groupID: UUID) -> [AnnotationRenderData] {
    spansByCue.values
      .flatMap { $0 }
      .filter { $0.groupID == groupID }
      .sorted {
        if $0.cueID == $1.cueID {
          return $0.rangeLocation < $1.rangeLocation
        }
        return $0.createdAt < $1.createdAt
      }
      .compactMap(displayData(from:))
  }

  /// Update the comment on an annotation
  func updateComment(groupID: UUID, comment: String?) {
    guard let group = groupsByID[groupID] else { return }
    group.comment = comment
    group.updatedAt = Date()
    version += 1
  }

  func updateStyle(groupID: UUID, stylePresetID: UUID) {
    guard let group = groupsByID[groupID] else { return }
    group.stylePresetID = stylePresetID
    group.updatedAt = Date()
    version += 1
  }

  func styleUsageCount(stylePresetID: UUID) -> Int {
    groupsByID.values.filter { $0.stylePresetID == stylePresetID }.count
  }

  /// Remove an annotation
  func removeAnnotation(id: UUID) {
    guard let span = findSpan(by: id) else { return }
    removeAnnotationGroup(groupID: span.groupID)
  }

  func removeAnnotationGroup(groupID: UUID) {
    let spans = findSpans(groupID: groupID)
    guard !spans.isEmpty else { return }

    for span in spans {
      modelContext.delete(span)
      let cueID = span.cueID
      spansByCue[cueID]?.removeAll { $0.id == span.id }
      if spansByCue[cueID]?.isEmpty == true {
        spansByCue.removeValue(forKey: cueID)
      }
    }

    if let group = groupsByID[groupID] {
      modelContext.delete(group)
      groupsByID.removeValue(forKey: groupID)
    }

    version += 1
  }

  /// Refresh the cache from ModelContext
  func refreshCache() {
    let groupDescriptor = FetchDescriptor<TextAnnotationGroupV2>()
    let spanDescriptor = FetchDescriptor<TextAnnotationSpanV2>()
    let groups = (try? modelContext.fetch(groupDescriptor)) ?? []
    let spans = (try? modelContext.fetch(spanDescriptor)) ?? []

    groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
    spansByCue = Dictionary(grouping: spans, by: \.cueID)
    version += 1
  }

  // MARK: - Private

  private func findSpan(by id: UUID) -> TextAnnotationSpanV2? {
    for spans in spansByCue.values {
      if let span = spans.first(where: { $0.id == id }) {
        return span
      }
    }
    return nil
  }

  private func findSpans(groupID: UUID) -> [TextAnnotationSpanV2] {
    spansByCue.values
      .flatMap { $0 }
      .filter { $0.groupID == groupID }
  }

  private func displayData(from span: TextAnnotationSpanV2) -> AnnotationRenderData? {
    guard let group = groupsByID[span.groupID] else { return nil }
    let style = styleService.style(id: group.stylePresetID) ?? styleService.defaultStyle()

    return AnnotationRenderData(
      id: span.id,
      groupID: span.groupID,
      stylePresetID: style.id,
      styleName: style.name,
      styleKind: style.kind,
      underlineColorHex: style.underlineColorHex,
      backgroundColorHex: style.backgroundColorHex,
      range: span.range,
      selectedText: group.selectedTextSnapshot,
      comment: group.comment
    )
  }
}

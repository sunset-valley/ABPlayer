import Foundation
import Observation
import SwiftData

/// Service responsible for managing text annotations on subtitle cues
/// Provides centralized CRUD operations and cache management
@Observable
@MainActor
final class AnnotationService {
  private let modelContext: ModelContext

  /// Internal cache mapping cueID to annotations
  private var annotationsByCue: [UUID: [TextAnnotation]] = [:]

  /// Version counter for cache invalidation - incremented on mutations
  private(set) var version = 0

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
    refreshCache()
  }

  // MARK: - Public API

  /// Get display data for all annotations in a cue
  func annotations(for cueID: UUID) -> [AnnotationDisplayData] {
    let cached = annotationsByCue[cueID] ?? []
    return cached.map { AnnotationDisplayData(from: $0) }
  }

  /// Add a new annotation
  @discardableResult
  func addAnnotation(
    cueID: UUID,
    groupID: UUID? = nil,
    range: NSRange,
    selectedText: String,
    type: AnnotationType
  ) -> AnnotationDisplayData {
    let annotation = TextAnnotation(
      groupID: groupID,
      cueID: cueID,
      rangeLocation: range.location,
      rangeLength: range.length,
      type: type,
      selectedText: selectedText
    )
    modelContext.insert(annotation)

    if annotationsByCue[cueID] == nil {
      annotationsByCue[cueID] = []
    }
    annotationsByCue[cueID]?.append(annotation)
    version += 1

    return AnnotationDisplayData(from: annotation)
  }

  func annotations(inGroup groupID: UUID) -> [AnnotationDisplayData] {
    annotationsByCue.values
      .flatMap { $0 }
      .filter { $0.groupID == groupID }
      .sorted {
        if $0.cueID == $1.cueID {
          return $0.rangeLocation < $1.rangeLocation
        }
        return $0.createdAt < $1.createdAt
      }
      .map { AnnotationDisplayData(from: $0) }
  }

  /// Update the comment on an annotation
  func updateComment(annotationID: UUID, comment: String?) {
    guard let annotation = findAnnotation(by: annotationID) else { return }
    updateComment(groupID: annotation.groupID, comment: comment)
  }

  func updateComment(groupID: UUID, comment: String?) {
    let annotations = findAnnotations(groupID: groupID)
    guard !annotations.isEmpty else { return }
    let now = Date()
    for annotation in annotations {
      annotation.comment = comment
      annotation.updatedAt = now
    }
    version += 1
  }

  /// Change the type of an annotation
  func updateType(annotationID: UUID, type: AnnotationType) {
    guard let annotation = findAnnotation(by: annotationID) else { return }
    updateType(groupID: annotation.groupID, type: type)
  }

  func updateType(groupID: UUID, type: AnnotationType) {
    let annotations = findAnnotations(groupID: groupID)
    guard !annotations.isEmpty else { return }
    let now = Date()
    for annotation in annotations {
      annotation.type = type
      annotation.updatedAt = now
    }
    version += 1
  }

  /// Remove an annotation
  func removeAnnotation(id: UUID) {
    guard let annotation = findAnnotation(by: id) else { return }
    removeAnnotationGroup(groupID: annotation.groupID)
  }

  func removeAnnotationGroup(groupID: UUID) {
    let annotations = findAnnotations(groupID: groupID)
    guard !annotations.isEmpty else { return }

    for annotation in annotations {
      modelContext.delete(annotation)
      let cueID = annotation.cueID
      annotationsByCue[cueID]?.removeAll { $0.id == annotation.id }
      if annotationsByCue[cueID]?.isEmpty == true {
        annotationsByCue.removeValue(forKey: cueID)
      }
    }
    version += 1
  }

  /// Refresh the cache from ModelContext
  func refreshCache() {
    let descriptor = FetchDescriptor<TextAnnotation>()
    let annotations = (try? modelContext.fetch(descriptor)) ?? []

    annotationsByCue = Dictionary(grouping: annotations, by: \.cueID)
    version += 1
  }

  // MARK: - Private

  private func findAnnotation(by id: UUID) -> TextAnnotation? {
    for annotations in annotationsByCue.values {
      if let annotation = annotations.first(where: { $0.id == id }) {
        return annotation
      }
    }
    return nil
  }

  private func findAnnotations(groupID: UUID) -> [TextAnnotation] {
    annotationsByCue.values
      .flatMap { $0 }
      .filter { $0.groupID == groupID }
  }
}

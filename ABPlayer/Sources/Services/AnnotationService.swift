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

  /// Find annotation at a specific character index within a cue
  func annotation(at characterIndex: Int, in cueID: UUID) -> AnnotationDisplayData? {
    let cached = annotationsByCue[cueID] ?? []
    for annotation in cached {
      let range = annotation.range
      if characterIndex >= range.location && characterIndex < range.location + range.length {
        return AnnotationDisplayData(from: annotation)
      }
    }
    return nil
  }

  /// Add a new annotation
  @discardableResult
  func addAnnotation(
    cueID: UUID,
    range: NSRange,
    selectedText: String,
    type: AnnotationType
  ) -> AnnotationDisplayData {
    let annotation = TextAnnotation(
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

  /// Update the comment on an annotation
  func updateComment(annotationID: UUID, comment: String?) {
    guard let annotation = findAnnotation(by: annotationID) else { return }
    annotation.comment = comment
    annotation.updatedAt = Date()
    version += 1
  }

  /// Change the type of an annotation
  func updateType(annotationID: UUID, type: AnnotationType) {
    guard let annotation = findAnnotation(by: annotationID) else { return }
    annotation.type = type
    annotation.updatedAt = Date()
    version += 1
  }

  /// Remove an annotation
  func removeAnnotation(id: UUID) {
    guard let annotation = findAnnotation(by: id) else { return }
    let cueID = annotation.cueID
    modelContext.delete(annotation)
    annotationsByCue[cueID]?.removeAll { $0.id == id }
    if annotationsByCue[cueID]?.isEmpty == true {
      annotationsByCue.removeValue(forKey: cueID)
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
}

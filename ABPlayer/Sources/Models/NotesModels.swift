import Foundation
import SwiftData

@Model
final class NoteCollection {
  var id: UUID
  var name: String
  var createdAt: Date
  var updatedAt: Date

  @Relationship(deleteRule: .cascade, inverse: \Note.collection)
  var notes: [Note] = []

  init(
    id: UUID = UUID(),
    name: String,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

@Model
final class Note {
  var id: UUID
  var title: String
  var createdAt: Date
  var updatedAt: Date

  var collection: NoteCollection?

  @Relationship(deleteRule: .cascade, inverse: \NoteEntry.parentNote)
  var entries: [NoteEntry] = []

  @Relationship(deleteRule: .cascade, inverse: \NoteAnnotationLink.parentNote)
  var annotationLinks: [NoteAnnotationLink] = []

  init(
    id: UUID = UUID(),
    title: String,
    collection: NoteCollection? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.collection = collection
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

@Model
final class NoteEntry {
  var id: UUID
  var title: String
  var note: String?
  var sortOrder: Int
  var createdAt: Date
  var updatedAt: Date

  var parentNote: Note?

  init(
    id: UUID = UUID(),
    title: String,
    note: String? = nil,
    sortOrder: Int,
    parentNote: Note? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.note = note
    self.sortOrder = sortOrder
    self.parentNote = parentNote
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

@Model
final class NoteAnnotationLink {
  var id: UUID
  var sortOrder: Int
  var createdAt: Date

  var parentNote: Note?
  var annotationGroup: TextAnnotationGroupV2?

  init(
    id: UUID = UUID(),
    sortOrder: Int,
    parentNote: Note? = nil,
    annotationGroup: TextAnnotationGroupV2? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.sortOrder = sortOrder
    self.parentNote = parentNote
    self.annotationGroup = annotationGroup
    self.createdAt = createdAt
  }
}

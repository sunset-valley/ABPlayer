import Foundation
import Observation
import SwiftData

enum NotesBrowserServiceError: LocalizedError, Equatable {
  case invalidName
  case collectionNotFound
  case noteNotFound
  case mediaNotFound
  case customEntryNotFound
  case annotationNotFound
  case duplicateCollectionName
  case duplicateNoteTitle
  case duplicateAnnotationLink

  var errorDescription: String? {
    switch self {
    case .invalidName:
      return "Name cannot be empty"
    case .collectionNotFound:
      return "Collection not found"
    case .noteNotFound:
      return "Note not found"
    case .mediaNotFound:
      return "Media not found"
    case .customEntryNotFound:
      return "Custom entry not found"
    case .annotationNotFound:
      return "Annotation not found"
    case .duplicateCollectionName:
      return "Collection name already exists"
    case .duplicateNoteTitle:
      return "Note title already exists in collection"
    case .duplicateAnnotationLink:
      return "Annotation is already in note"
    }
  }
}

enum NotesBrowserEntryKind: Equatable, Sendable {
  case custom
  case annotation
}

enum NotesBrowserEntryFilter: Equatable, Sendable {
  case all
  case stylePreset(UUID)
}

struct NotesBrowserEntry: Identifiable, Equatable, Sendable {
  let id: UUID
  let kind: NotesBrowserEntryKind
  let sortOrder: Int
  let title: String
  let note: String?
  let mediaID: UUID?
  let mediaName: String?
  let stylePresetID: UUID?
  let stylePresetName: String?
  let annotationGroupID: UUID?
  let createdAt: Date
  let updatedAt: Date?
}

@Observable
@MainActor
final class NotesBrowserService {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  // MARK: - Collection

  func collections() -> [NoteCollection] {
    let descriptor = FetchDescriptor<NoteCollection>(
      sortBy: [SortDescriptor(\NoteCollection.updatedAt, order: .reverse)]
    )
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  @discardableResult
  func createCollection(name: String) throws -> NoteCollection {
    let normalizedName = try normalizeRequiredText(name)
    if hasCollectionNameConflict(normalizedName: normalizedName, excludingID: nil) {
      throw NotesBrowserServiceError.duplicateCollectionName
    }

    let now = Date()
    let collection = NoteCollection(name: normalizedName, createdAt: now, updatedAt: now)
    modelContext.insert(collection)
    try modelContext.save()
    return collection
  }

  func renameCollection(id: UUID, name: String) throws {
    let normalizedName = try normalizeRequiredText(name)
    guard let collection = findCollection(id: id) else {
      throw NotesBrowserServiceError.collectionNotFound
    }
    if hasCollectionNameConflict(normalizedName: normalizedName, excludingID: id) {
      throw NotesBrowserServiceError.duplicateCollectionName
    }

    collection.name = normalizedName
    collection.updatedAt = Date()
    try modelContext.save()
  }

  func deleteCollection(id: UUID) throws {
    guard let collection = findCollection(id: id) else {
      throw NotesBrowserServiceError.collectionNotFound
    }
    modelContext.delete(collection)
    try modelContext.save()
  }

  // MARK: - Note

  func notes(inCollectionID collectionID: UUID) throws -> [Note] {
    guard let collection = findCollection(id: collectionID) else {
      throw NotesBrowserServiceError.collectionNotFound
    }
    return collection.notes.sorted {
      if $0.updatedAt == $1.updatedAt {
        return $0.createdAt < $1.createdAt
      }
      return $0.updatedAt > $1.updatedAt
    }
  }

  @discardableResult
  func createNote(collectionID: UUID, title: String) throws -> Note {
    let normalizedTitle = try normalizeRequiredText(title)
    guard let collection = findCollection(id: collectionID) else {
      throw NotesBrowserServiceError.collectionNotFound
    }
    if hasNoteTitleConflict(in: collection, normalizedTitle: normalizedTitle, excludingID: nil) {
      throw NotesBrowserServiceError.duplicateNoteTitle
    }

    let now = Date()
    let note = Note(title: normalizedTitle, collection: collection, createdAt: now, updatedAt: now)
    modelContext.insert(note)
    collection.updatedAt = now
    try modelContext.save()
    return note
  }

  func renameNote(id: UUID, title: String) throws {
    let normalizedTitle = try normalizeRequiredText(title)
    guard let note = findNote(id: id) else {
      throw NotesBrowserServiceError.noteNotFound
    }
    guard let collection = note.collection else {
      throw NotesBrowserServiceError.collectionNotFound
    }
    if hasNoteTitleConflict(in: collection, normalizedTitle: normalizedTitle, excludingID: id) {
      throw NotesBrowserServiceError.duplicateNoteTitle
    }

    let now = Date()
    note.title = normalizedTitle
    note.updatedAt = now
    collection.updatedAt = now
    try modelContext.save()
  }

  func deleteNote(id: UUID) throws {
    guard let note = findNote(id: id) else {
      throw NotesBrowserServiceError.noteNotFound
    }
    note.collection?.updatedAt = Date()
    modelContext.delete(note)
    try modelContext.save()
  }

  // MARK: - Custom Entries

  @discardableResult
  func createCustomEntry(noteID: UUID, title: String, note: String?) throws -> NoteEntry {
    let normalizedTitle = try normalizeRequiredText(title)
    guard let parentNote = findNote(id: noteID) else {
      throw NotesBrowserServiceError.noteNotFound
    }

    let now = Date()
    let entry = NoteEntry(
      title: normalizedTitle,
      note: normalizeOptionalText(note),
      sortOrder: nextSortOrder(in: parentNote),
      parentNote: parentNote,
      createdAt: now,
      updatedAt: now
    )
    modelContext.insert(entry)
    parentNote.updatedAt = now
    parentNote.collection?.updatedAt = now
    try modelContext.save()
    return entry
  }

  func updateCustomEntry(entryID: UUID, title: String, note: String?) throws {
    let normalizedTitle = try normalizeRequiredText(title)
    guard let entry = findCustomEntry(id: entryID) else {
      throw NotesBrowserServiceError.customEntryNotFound
    }

    let now = Date()
    entry.title = normalizedTitle
    entry.note = normalizeOptionalText(note)
    entry.updatedAt = now
    entry.parentNote?.updatedAt = now
    entry.parentNote?.collection?.updatedAt = now
    try modelContext.save()
  }

  func deleteCustomEntry(entryID: UUID) throws {
    guard let entry = findCustomEntry(id: entryID) else {
      throw NotesBrowserServiceError.customEntryNotFound
    }
    let now = Date()
    let parentNote = entry.parentNote
    modelContext.delete(entry)
    if let parentNote {
      parentNote.updatedAt = now
      parentNote.collection?.updatedAt = now
      rebalanceSortOrder(in: parentNote)
    }
    try modelContext.save()
  }

  // MARK: - Annotation Links

  @discardableResult
  func addAnnotationToNote(noteID: UUID, annotationGroupID: UUID) throws -> NoteAnnotationLink {
    guard let parentNote = findNote(id: noteID) else {
      throw NotesBrowserServiceError.noteNotFound
    }
    guard let annotationGroup = findAnnotationGroup(id: annotationGroupID) else {
      throw NotesBrowserServiceError.annotationNotFound
    }
    if parentNote.annotationLinks.contains(where: { $0.annotationGroup?.id == annotationGroupID }) {
      throw NotesBrowserServiceError.duplicateAnnotationLink
    }

    let now = Date()
    let link = NoteAnnotationLink(
      sortOrder: nextSortOrder(in: parentNote),
      parentNote: parentNote,
      annotationGroup: annotationGroup,
      createdAt: now
    )
    modelContext.insert(link)
    parentNote.updatedAt = now
    parentNote.collection?.updatedAt = now
    try modelContext.save()
    return link
  }

  func removeAnnotationFromNote(noteID: UUID, annotationGroupID: UUID) throws {
    guard let parentNote = findNote(id: noteID) else {
      throw NotesBrowserServiceError.noteNotFound
    }
    guard
      let link = parentNote.annotationLinks.first(where: { $0.annotationGroup?.id == annotationGroupID })
    else {
      return
    }

    let now = Date()
    modelContext.delete(link)
    parentNote.updatedAt = now
    parentNote.collection?.updatedAt = now
    rebalanceSortOrder(in: parentNote)
    try modelContext.save()
  }

  // MARK: - Query Contracts

  func mediaWithAnnotations(fileType: FileType?) -> [ABFile] {
    let groups = (try? modelContext.fetch(FetchDescriptor<TextAnnotationGroupV2>())) ?? []
    if groups.isEmpty {
      return []
    }

    let mediaByID = Dictionary(uniqueKeysWithValues: allMedia().map { ($0.id, $0) })
    var counts: [UUID: Int] = [:]
    for group in groups {
      counts[group.audioFileID, default: 0] += 1
    }

    return counts
      .keys
      .compactMap { mediaByID[$0] }
      .filter { media in
        guard let fileType else { return true }
        return media.fileType == fileType
      }
      .sorted { lhs, rhs in
        if lhs.displayName == rhs.displayName {
          return lhs.createdAt < rhs.createdAt
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
  }

  func entries(forMediaID mediaID: UUID) -> [NotesBrowserEntry] {
    let styleNamesByID = annotationStyleNamesByID()
    let groups = allAnnotationGroups()
      .filter { $0.audioFileID == mediaID }
      .sorted {
        if $0.updatedAt == $1.updatedAt {
          return $0.createdAt < $1.createdAt
        }
        return $0.updatedAt > $1.updatedAt
      }
    let mediaName = findMedia(id: mediaID)?.displayName

    return groups.map { group in
      NotesBrowserEntry(
        id: group.id,
        kind: .annotation,
        sortOrder: 0,
        title: group.selectedTextSnapshot,
        note: group.comment,
        mediaID: group.audioFileID,
        mediaName: mediaName,
        stylePresetID: group.stylePresetID,
        stylePresetName: styleNamesByID[group.stylePresetID],
        annotationGroupID: group.id,
        createdAt: group.createdAt,
        updatedAt: group.updatedAt
      )
    }
  }

  func entries(forNoteID noteID: UUID) throws -> [NotesBrowserEntry] {
    guard let note = findNote(id: noteID) else {
      throw NotesBrowserServiceError.noteNotFound
    }

    let styleNamesByID = annotationStyleNamesByID()

    var merged: [NotesBrowserEntry] = []
    merged.reserveCapacity(note.entries.count + note.annotationLinks.count)

    for entry in note.entries {
      merged.append(
        NotesBrowserEntry(
          id: entry.id,
          kind: .custom,
          sortOrder: entry.sortOrder,
          title: entry.title,
          note: entry.note,
          mediaID: nil,
          mediaName: nil,
          stylePresetID: nil,
          stylePresetName: nil,
          annotationGroupID: nil,
          createdAt: entry.createdAt,
          updatedAt: entry.updatedAt
        )
      )
    }

    for link in note.annotationLinks {
      guard let group = link.annotationGroup else { continue }
      merged.append(
        NotesBrowserEntry(
          id: link.id,
          kind: .annotation,
          sortOrder: link.sortOrder,
          title: group.selectedTextSnapshot,
          note: group.comment,
          mediaID: group.audioFileID,
          mediaName: findMedia(id: group.audioFileID)?.displayName,
          stylePresetID: group.stylePresetID,
          stylePresetName: styleNamesByID[group.stylePresetID],
          annotationGroupID: group.id,
          createdAt: link.createdAt,
          updatedAt: group.updatedAt
        )
      )
    }

    return merged.sorted {
      if $0.sortOrder == $1.sortOrder {
        return $0.createdAt < $1.createdAt
      }
      return $0.sortOrder < $1.sortOrder
    }
  }

  func csvString(forNoteID noteID: UUID, filter: NotesBrowserEntryFilter = .all) throws -> String {
    let entries = try filteredEntries(forNoteID: noteID, filter: filter)
    var rows: [String] = ["title,note"]
    rows.reserveCapacity(entries.count + 1)

    for entry in entries {
      let title = escapeCSVField(entry.title)
      let note = escapeCSVField(entry.note ?? "")
      rows.append("\(title),\(note)")
    }

    return rows.joined(separator: "\n")
  }

  func csvString(forMediaID mediaID: UUID, filter: NotesBrowserEntryFilter = .all) throws -> String {
    guard findMedia(id: mediaID) != nil else {
      throw NotesBrowserServiceError.mediaNotFound
    }

    let entries = filteredEntries(forMediaID: mediaID, filter: filter)
    var rows: [String] = ["title,note"]
    rows.reserveCapacity(entries.count + 1)

    for entry in entries {
      let title = escapeCSVField(entry.title)
      let note = escapeCSVField(entry.note ?? "")
      rows.append("\(title),\(note)")
    }

    return rows.joined(separator: "\n")
  }

  func csvData(forNoteID noteID: UUID, filter: NotesBrowserEntryFilter = .all) throws -> Data {
    let csvContent = try csvString(forNoteID: noteID, filter: filter)
    return Data(csvContent.utf8)
  }

  func csvData(forMediaID mediaID: UUID, filter: NotesBrowserEntryFilter = .all) throws -> Data {
    let csvContent = try csvString(forMediaID: mediaID, filter: filter)
    return Data(csvContent.utf8)
  }

  // MARK: - Helpers

  private func findCollection(id: UUID) -> NoteCollection? {
    let descriptor = FetchDescriptor<NoteCollection>(
      predicate: #Predicate<NoteCollection> { $0.id == id }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func findNote(id: UUID) -> Note? {
    let descriptor = FetchDescriptor<Note>(
      predicate: #Predicate<Note> { $0.id == id }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func findCustomEntry(id: UUID) -> NoteEntry? {
    let descriptor = FetchDescriptor<NoteEntry>(
      predicate: #Predicate<NoteEntry> { $0.id == id }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func findAnnotationGroup(id: UUID) -> TextAnnotationGroupV2? {
    let descriptor = FetchDescriptor<TextAnnotationGroupV2>(
      predicate: #Predicate<TextAnnotationGroupV2> { $0.id == id }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func findMedia(id: UUID) -> ABFile? {
    let descriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { $0.id == id }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func allMedia() -> [ABFile] {
    (try? modelContext.fetch(FetchDescriptor<ABFile>())) ?? []
  }

  private func allAnnotationGroups() -> [TextAnnotationGroupV2] {
    (try? modelContext.fetch(FetchDescriptor<TextAnnotationGroupV2>())) ?? []
  }

  private func annotationStyleNamesByID() -> [UUID: String] {
    let styles = (try? modelContext.fetch(FetchDescriptor<AnnotationStylePreset>())) ?? []
    return Dictionary(uniqueKeysWithValues: styles.map { ($0.id, $0.name) })
  }

  private func filteredEntries(forNoteID noteID: UUID, filter: NotesBrowserEntryFilter) throws -> [NotesBrowserEntry] {
    let entries = try entries(forNoteID: noteID)
    return filterEntries(entries, using: filter)
  }

  private func filteredEntries(forMediaID mediaID: UUID, filter: NotesBrowserEntryFilter) -> [NotesBrowserEntry] {
    let entries = entries(forMediaID: mediaID)
    return filterEntries(entries, using: filter)
  }

  private func filterEntries(_ entries: [NotesBrowserEntry], using filter: NotesBrowserEntryFilter)
    -> [NotesBrowserEntry]
  {
    switch filter {
    case .all:
      return entries
    case .stylePreset(let stylePresetID):
      return entries.filter { $0.stylePresetID == stylePresetID }
    }
  }

  private func normalizeRequiredText(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      throw NotesBrowserServiceError.invalidName
    }
    return normalized
  }

  private func normalizeOptionalText(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  private func canonicalKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func escapeCSVField(_ value: String) -> String {
    let shouldQuote = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
    guard shouldQuote else {
      return value
    }

    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
  }

  private func hasCollectionNameConflict(normalizedName: String, excludingID: UUID?) -> Bool {
    let key = canonicalKey(normalizedName)
    return collections().contains { collection in
      if let excludingID, collection.id == excludingID {
        return false
      }
      return canonicalKey(collection.name) == key
    }
  }

  private func hasNoteTitleConflict(in collection: NoteCollection, normalizedTitle: String, excludingID: UUID?)
    -> Bool
  {
    let key = canonicalKey(normalizedTitle)
    return collection.notes.contains { note in
      if let excludingID, note.id == excludingID {
        return false
      }
      return canonicalKey(note.title) == key
    }
  }

  private func nextSortOrder(in note: Note) -> Int {
    let maxCustom = note.entries.map(\.sortOrder).max() ?? -1
    let maxAnnotation = note.annotationLinks.map(\.sortOrder).max() ?? -1
    return max(maxCustom, maxAnnotation) + 1
  }

  private func rebalanceSortOrder(in note: Note) {
    var sortables: [(sortOrder: Int, createdAt: Date, apply: (Int) -> Void)] = []

    for entry in note.entries {
      sortables.append((
        sortOrder: entry.sortOrder,
        createdAt: entry.createdAt,
        apply: { entry.sortOrder = $0 }
      ))
    }

    for link in note.annotationLinks {
      sortables.append((
        sortOrder: link.sortOrder,
        createdAt: link.createdAt,
        apply: { link.sortOrder = $0 }
      ))
    }

    let ordered = sortables.sorted {
      if $0.sortOrder == $1.sortOrder {
        return $0.createdAt < $1.createdAt
      }
      return $0.sortOrder < $1.sortOrder
    }

    for (index, sortable) in ordered.enumerated() {
      sortable.apply(index)
    }
  }
}

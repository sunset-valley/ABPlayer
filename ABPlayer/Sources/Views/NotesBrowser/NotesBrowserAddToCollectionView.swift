import SwiftUI

struct NotesBrowserAddToCollectionView: View {
  @Environment(\.dismiss) private var dismiss

  let collections: [NotesBrowserViewModel.CollectionWithNotes]
  let onAdd: (UUID) -> Void

  @State private var selectedCollectionID: UUID?
  @State private var selectedNoteID: UUID?
  @State private var searchText = ""

  private var isInNoteStep: Bool { selectedCollectionID != nil }

  private var selectedCollection: NotesBrowserViewModel.CollectionWithNotes? {
    guard let id = selectedCollectionID else { return nil }
    return collections.first { $0.id == id }
  }

  private var displayedCollections: [NotesBrowserViewModel.CollectionWithNotes] {
    guard !searchText.isEmpty else { return collections }
    return collections.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
  }

  private var displayedNotes: [NotesBrowserViewModel.CollectionWithNotes.NoteItem] {
    guard let collection = selectedCollection else { return [] }
    guard !searchText.isEmpty else { return collection.notes }
    return collection.notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headerView
      searchFieldView
      Divider()
      if isInNoteStep {
        noteListView
      } else {
        collectionListView
      }
      Divider()
      footerView
    }
    .frame(minWidth: 400, minHeight: 380)
  }

  private var headerView: some View {
    HStack(spacing: 8) {
      if isInNoteStep {
        Button {
          selectedCollectionID = nil
          selectedNoteID = nil
          searchText = ""
        } label: {
          Image(systemName: "chevron.left")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("notes-browser-add-to-collection-back")
        Text(selectedCollection?.name ?? "")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else {
        Text("Add to Collection")
          .font(.headline)
      }
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.top, 16)
    .padding(.bottom, 10)
  }

  private var searchFieldView: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .imageScale(.small)
      TextField(isInNoteStep ? "Search notes..." : "Search collections...", text: $searchText)
        .textFieldStyle(.plain)
      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .imageScale(.small)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var collectionListView: some View {
    List(displayedCollections, selection: $selectedCollectionID) { collection in
      Text(collection.name)
    }
    .listStyle(.plain)
    .overlay {
      if displayedCollections.isEmpty {
        ContentUnavailableView(
          "No Collections",
          systemImage: "folder",
          description: Text("Create a collection first.")
        )
      }
    }
    .onChange(of: selectedCollectionID) { _, newID in
      if newID != nil {
        searchText = ""
        selectedNoteID = nil
      }
    }
  }

  private var noteListView: some View {
    List(displayedNotes, selection: $selectedNoteID) { note in
      Text(note.title)
    }
    .listStyle(.plain)
    .overlay {
      if displayedNotes.isEmpty {
        ContentUnavailableView(
          "No Notes",
          systemImage: "note.text",
          description: Text("This collection has no notes.")
        )
      }
    }
  }

  private var footerView: some View {
    HStack {
      Spacer()
      Button("Cancel") { dismiss() }
        .accessibilityIdentifier("notes-browser-add-to-collection-cancel")
      Button("Add") {
        if let noteID = selectedNoteID {
          onAdd(noteID)
          dismiss()
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(selectedNoteID == nil)
      .accessibilityIdentifier("notes-browser-add-to-collection-add")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

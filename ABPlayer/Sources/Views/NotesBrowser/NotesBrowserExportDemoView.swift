import SwiftUI

@MainActor
struct NotesBrowserExportDemoView: View {
  @Environment(NotesBrowserService.self) private var notesService
  @Environment(\.modelContext) private var modelContext

  @State private var didSeedData = false
  @State private var seedErrorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Notes Browser Export Demo")
        .font(.title2)
        .accessibilityIdentifier("notes-browser-export-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-notes-export")
        .font(.caption)
        .foregroundStyle(.secondary)

      if let seedErrorMessage {
        ContentUnavailableView(
          "Failed to Seed Demo Data",
          systemImage: "exclamationmark.triangle",
          description: Text(seedErrorMessage)
        )
      } else if didSeedData {
        NotesBrowserView()
      } else {
        ProgressView("Preparing notes export demo...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(16)
    .frame(minWidth: 1280, minHeight: 820)
    .task {
      guard !didSeedData else { return }
      do {
        try seedDemoDataIfNeeded()
        didSeedData = true
      } catch {
        seedErrorMessage = error.localizedDescription
      }
    }
  }

  private func seedDemoDataIfNeeded() throws {
    if notesService.collections().contains(where: { $0.name == "UI Test Collection" }) {
      return
    }

    let now = Date()
    let media = ABFile(
      displayName: "UI Export Media.mp3",
      fileType: .audio,
      bookmarkData: Data([0x00]),
      createdAt: now
    )
    modelContext.insert(media)

    let annotationGroup = TextAnnotationGroupV2(
      audioFileID: media.id,
      stylePresetID: UUID(),
      selectedTextSnapshot: "Snapshot title",
      comment: "Annotation note",
      createdAt: now,
      updatedAt: now
    )
    modelContext.insert(annotationGroup)
    try modelContext.save()

    let collection = try notesService.createCollection(name: "UI Test Collection")
    let note = try notesService.createNote(collectionID: collection.id, title: "UI Test Note")
    _ = try notesService.createCustomEntry(noteID: note.id, title: "Custom item", note: "Custom note")
    _ = try notesService.addAnnotationToNote(noteID: note.id, annotationGroupID: annotationGroup.id)
  }
}

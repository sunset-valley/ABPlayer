import Foundation
#if os(macOS)
  import AppKit
#endif
import SwiftUI
#if os(macOS)
  import UniformTypeIdentifiers
#endif

@MainActor
struct NotesBrowserView: View {
  @Environment(NotesBrowserService.self) private var notesService

  @State private var viewModel = NotesBrowserViewModel()
  @State private var sourceSelection: NotesBrowserViewModel.Source?
  @State private var middleSelection: NotesBrowserViewModel.MiddleSelection?
  @State private var exportErrorMessage: String?

  var body: some View {
    NavigationSplitView {
      leftColumn
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    } content: {
      middleColumn
        .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 520)
    } detail: {
      rightColumn
    }
    .navigationTitle("Notes Browser")
    .onAppear {
      viewModel.configureIfNeeded(notesService: notesService)
      applyOutput(viewModel.transform(input: .init(event: .onAppear)))
    }
    .onChange(of: sourceSelection) { _, newValue in
      applyOutput(viewModel.transform(input: .init(event: .selectSource(newValue))))
    }
    .onChange(of: middleSelection) { _, newValue in
      applyOutput(viewModel.transform(input: .init(event: .selectMiddleItem(newValue))))
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          exportSelectedNoteToCSV()
        } label: {
          Label("Export CSV", systemImage: "square.and.arrow.down")
        }
        .disabled(viewModel.output.exportSelection == nil)
        .accessibilityIdentifier("notes-browser-export-csv-button")
      }
    }
    .alert(
      "Export Failed",
      isPresented: .constant(exportErrorMessage != nil),
      presenting: exportErrorMessage
    ) { _ in
      Button("OK", role: .cancel) {
        exportErrorMessage = nil
      }
    } message: { message in
      Text(message)
    }
  }

  private var leftColumn: some View {
    List(selection: $sourceSelection) {
      ForEach(viewModel.output.leftSections) { section in
        Section(section.title) {
          ForEach(section.items) { item in
            Label(item.title, systemImage: item.systemImage)
              .tag(Optional(item.source))
              .accessibilityIdentifier(accessibilityIdentifier(for: item.source))
          }
        }
      }
    }
    .accessibilityIdentifier("notes-browser-left-list")
    .listStyle(.sidebar)
    .overlay {
      if viewModel.output.leftSections.allSatisfy({ $0.items.isEmpty }) {
        ContentUnavailableView(
          "No Sources",
          systemImage: "sidebar.left",
          description: Text("Media and collections will appear here.")
        )
      }
    }
  }

  private var middleColumn: some View {
    List(selection: $middleSelection) {
      ForEach(viewModel.output.middleItems) { item in
        VStack(alignment: .leading, spacing: 2) {
          Label(item.title, systemImage: item.systemImage)
          if let subtitle = item.subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .tag(Optional(item.selection))
        .accessibilityIdentifier(accessibilityIdentifier(for: item.selection))
      }
    }
    .accessibilityIdentifier("notes-browser-middle-list")
    .overlay {
      if viewModel.output.middleItems.isEmpty {
        switch viewModel.output.middleMode {
        case .media:
          ContentUnavailableView(
            "No Annotated Media",
            systemImage: "waveform.slash",
            description: Text("Annotated videos or audios will appear here.")
          )
        case .notes:
          ContentUnavailableView(
            "No Notes",
            systemImage: "note.text",
            description: Text("Create notes in this collection to see them here.")
          )
        }
      }
    }
  }

  private var rightColumn: some View {
    List(viewModel.output.entries) { entry in
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: entry.kind == .annotation ? "highlighter" : "square.and.pencil")
            .foregroundStyle(.secondary)
          Text(entry.title)
            .font(.headline)
        }

        if let note = entry.note, !note.isEmpty {
          Text(note)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let mediaName = entry.mediaName {
          Label(mediaName, systemImage: "play.rectangle")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 4)
    }
    .accessibilityIdentifier("notes-browser-right-list")
    .overlay {
      if viewModel.output.entries.isEmpty {
        ContentUnavailableView(
          "No Entries",
          systemImage: "text.alignleft",
          description: Text("Select media or note to view entries.")
        )
      }
    }
  }

  private func applyOutput(_ output: NotesBrowserViewModel.Output) {
    sourceSelection = output.selectedSource
    middleSelection = output.selectedMiddleItem
  }

  private func accessibilityIdentifier(for source: NotesBrowserViewModel.Source) -> String {
    switch source {
    case .media(.allVideos):
      return "notes-browser-source-all-videos"
    case .media(.allAudios):
      return "notes-browser-source-all-audios"
    case .collection(let collectionID):
      return "notes-browser-source-collection-\(collectionID.uuidString.lowercased())"
    }
  }

  private func accessibilityIdentifier(for selection: NotesBrowserViewModel.MiddleSelection) -> String {
    switch selection {
    case .media(let mediaID):
      return "notes-browser-middle-media-\(mediaID.uuidString.lowercased())"
    case .note(let noteID):
      return "notes-browser-middle-note-\(noteID.uuidString.lowercased())"
    }
  }

  private func exportSelectedNoteToCSV() {
    guard let exportSelection = viewModel.output.exportSelection else {
      return
    }

    do {
      let csvData: Data
      let defaultFileName: String
      switch exportSelection.kind {
      case .note(let noteID, let noteTitle):
        csvData = try notesService.csvData(forNoteID: noteID)
        defaultFileName = defaultExportFileName(baseName: noteTitle)
      case .media(let mediaID, let mediaName):
        csvData = try notesService.csvData(forMediaID: mediaID)
        defaultFileName = defaultExportFileName(baseName: mediaName)
      }

      if let uiTestPath = uiTestExportPath() {
        let destinationURL = URL(fileURLWithPath: uiTestPath)
        try csvData.write(to: destinationURL, options: .atomic)
        return
      }

      #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = defaultFileName
        let result = savePanel.runModal()
        guard result == .OK, let saveURL = savePanel.url else {
          return
        }
        try csvData.write(to: saveURL, options: .atomic)
      #endif
    } catch {
      exportErrorMessage = error.localizedDescription
    }
  }

  private func defaultExportFileName(baseName: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
    let sanitized = baseName
      .components(separatedBy: invalidCharacters)
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let stem = sanitized.isEmpty ? "note" : sanitized
    return "\(stem).csv"
  }

  private func uiTestExportPath() -> String? {
    let rawValue = ProcessInfo.processInfo.environment["ABP_UI_TESTING_NOTES_EXPORT_OUTPUT_PATH"]
    guard let rawValue else {
      return nil
    }

    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }
}

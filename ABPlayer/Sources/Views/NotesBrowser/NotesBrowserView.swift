import SwiftUI

@MainActor
struct NotesBrowserView: View {
  @Environment(NotesBrowserService.self) private var notesService

  @State private var viewModel = NotesBrowserViewModel()
  @State private var sourceSelection: NotesBrowserViewModel.Source?
  @State private var middleSelection: NotesBrowserViewModel.MiddleSelection?

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
  }

  private var leftColumn: some View {
    List(selection: $sourceSelection) {
      ForEach(viewModel.output.leftSections) { section in
        Section(section.title) {
          ForEach(section.items) { item in
            Label(item.title, systemImage: item.systemImage)
              .tag(Optional(item.source))
          }
        }
      }
    }
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
      }
    }
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
}

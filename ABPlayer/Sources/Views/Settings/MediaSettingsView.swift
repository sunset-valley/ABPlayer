import SwiftUI

struct MediaSettingsView: View {
  @Environment(LibrarySettings.self) private var librarySettings
  @Environment(PlayerSettings.self) private var playerSettings

  @State private var isFileImporterPresented = false
  @State private var libraryPathError: String?

  var body: some View {
    Form {
      librarySection
      playerSection
    }
    .formStyle(.grouped)
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      handleLibraryDirectorySelection(result)
    }
    .alert("Library Path Error", isPresented: .constant(libraryPathError != nil)) {
      Button("OK") { libraryPathError = nil }
    } message: {
      if let error = libraryPathError {
        Text(error)
      }
    }
  }

  private var displayLibraryDirectory: String {
    if librarySettings.libraryPath.isEmpty {
      return LibrarySettings.defaultLibraryDirectory.path
    }
    return librarySettings.libraryPath
  }

  private var librarySection: some View {
    Section {
      LabeledContent("Library Directory") {
        HStack {
          Text(displayLibraryDirectory)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

          Button("Choose...") {
            isFileImporterPresented = true
          }
        }
      }
    } header: {
      Label("Library", systemImage: "books.vertical")
    } footer: {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 4) {
          Text("Library stored at:")
          Button {
            let url = librarySettings.libraryDirectoryURL
            NSWorkspace.shared.open(url)
          } label: {
            Text(displayLibraryDirectory)
              .underline()
              .foregroundStyle(.primary)
          }
          .buttonStyle(.plain)
          .onHover { inside in
            if inside {
              NSCursor.pointingHand.push()
            } else {
              NSCursor.pop()
            }
          }
        }
        .captionStyle()
      }
    }
  }

  private var playerSection: some View {
    Section {
      Toggle(
        "Prevent sleep during playback",
        isOn: Binding(
          get: { playerSettings.preventSleep },
          set: { playerSettings.preventSleep = $0 }
        ))
    } header: {
      Label("Player", systemImage: "play.circle")
    }
  }

  private func handleLibraryDirectorySelection(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      if (try? url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )) != nil {
        librarySettings.libraryPath = url.path
        do {
          try librarySettings.ensureLibraryDirectoryExists()
        } catch {
          libraryPathError = "Failed to create library directory: \(error.localizedDescription)"
        }
      } else {
        libraryPathError = "Unable to access selected folder."
      }
    case .failure(let error):
      libraryPathError = error.localizedDescription
    }
  }
}

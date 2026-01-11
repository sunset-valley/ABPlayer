import OSLog
import SwiftData
import SwiftUI

// MARK: - Sort Order

enum SortOrder: String, CaseIterable {
  case nameAZ = "Name (A-Z)"
  case nameZA = "Name (Z-A)"
  case numberAsc = "Number (Smallest First)"
  case numberDesc = "Number (Biggest First)"
  case dateCreatedNewestFirst = "Date Created (Newest First)"
  case dateCreatedOldestFirst = "Date Created (Oldest First)"
}

// MARK: - Selection Item

enum SelectionItem: Hashable {
  case folder(Folder)
  case audioFile(AudioFile)
  case empty
}

/// Hierarchical folder navigation view for the sidebar
struct FolderNavigationView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(AudioPlayerManager.self) private var playerManager

  @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.name)
  private var rootFolders: [Folder]

  @Query(filter: #Predicate<AudioFile> { $0.folder == nil }, sort: \AudioFile.createdAt)
  private var rootAudioFiles: [AudioFile]

  @Binding var selectedFile: AudioFile?
  @Binding var currentFolder: Folder?
  @Binding var navigationPath: [Folder]

  @State private var viewModel: FolderNavigationViewModel?

  let onSelectFile: (AudioFile) async -> Void

  var body: some View {
    VStack(spacing: 0) {
      navigationHeader
      fileList
    }
    .onAppear {
      if viewModel == nil {
        viewModel = FolderNavigationViewModel(
          modelContext: modelContext,
          playerManager: playerManager
        )
        
        if let savedSortOrder = UserDefaults.standard.string(forKey: "folderNavigationSortOrder"),
           let sortOrder = SortOrder(rawValue: savedSortOrder) {
          viewModel?.sortOrder = sortOrder
        }
      }
    }
    .onChange(of: viewModel?.selection) { _, newValue in
      guard let viewModel else { return }
      viewModel.handleSelectionChange(
        newValue,
        navigationPath: &navigationPath,
        currentFolder: &currentFolder,
        onSelectFile: onSelectFile
      )
    }
    .onChange(of: selectedFile) {
      if let file = selectedFile {
        viewModel?.selection = .audioFile(file)
      } else {
        viewModel?.selection = nil
      }
    }
    .onChange(of: viewModel?.sortOrder) { _, newValue in
      if let newValue {
        UserDefaults.standard.set(newValue.rawValue, forKey: "folderNavigationSortOrder")
      }
    }
  }

  // MARK: - Navigation Header

  private var navigationHeader: some View {
    Group {
      if let viewModel {
        FolderNavigationHeaderView(
          currentFolder: currentFolder,
          canNavigateBack: viewModel.canNavigateBack(navigationPath: navigationPath),
          isRescanningFolder: viewModel.isRescanningFolder,
          sortOrder: viewModel.sortOrder,
          onNavigateBack: {
            viewModel.navigateBack(navigationPath: &navigationPath, currentFolder: &currentFolder)
          },
          onRescan: {
            viewModel.rescanCurrentFolder(currentFolder)
          },
          onSortChange: { viewModel.sortOrder = $0 }
        )
      }
    }
  }

  // MARK: - File List

  private var fileList: some View {
    Group {
      if let viewModel {
        List(selection: Binding(
          get: { viewModel.selection },
          set: { viewModel.selection = $0 }
        )) {
          if !currentFolders.isEmpty {
            Section {
              ForEach(currentFolders) { folder in
                folderRow(for: folder)
                  .tag(SelectionItem.folder(folder))
              }
              .frame(height: 44)
              .padding(.horizontal, 16)
              .listRowSeparator(.hidden)
            }
          }

          if !currentAudioFiles.isEmpty {
            Section {
              ForEach(currentAudioFiles) { file in
                fileRow(for: file)
                  .tag(SelectionItem.audioFile(file))
                  .onHover {
                    if $0 {
                      viewModel.hovering = SelectionItem.audioFile(file)
                    } else {
                      viewModel.hovering = nil
                    }
                  }
                  .listRowBackground(
                    selectedFile == file
                    ? Color.asset.listHighlight
                    : viewModel.hovering == SelectionItem.audioFile(file)
                      ? Color.asset.listHighlight.opacity(0.5)
                      : .clear
                  )
              }
              .frame(height: 44)
              .padding(.horizontal, -8)
              .listRowSeparatorTint(Color.asset.bgPrimary)
              .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
          }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .scrollContentBackground(.hidden)
        .overlay {
          if currentFolders.isEmpty && currentAudioFiles.isEmpty {
            ContentUnavailableView(
              "No Content",
              systemImage: "folder",
              description: Text("Import a folder to get started")
            )
            .tag(SelectionItem.empty)
          }
        }
      }
    }
  }

  // MARK: - Selection Handling

  private var currentFolders: [Folder] {
    guard let viewModel else { return [] }
    let folders = currentFolder.map { Array($0.subfolders) } ?? rootFolders
    return viewModel.sortedFolders(folders)
  }

  private var currentAudioFiles: [AudioFile] {
    guard let viewModel else { return [] }
    let files = currentFolder.map { Array($0.audioFiles) } ?? rootAudioFiles
    return viewModel.sortedAudioFiles(files)
  }

  // MARK: - Folder Row

  private func folderRow(for folder: Folder) -> some View {
    FolderRowView(
      folder: folder,
      onDelete: {
        guard let viewModel else { return }
        viewModel.deleteFolder(
          folder,
          currentFolder: &currentFolder,
          selectedFile: &selectedFile,
          navigationPath: &navigationPath
        )
      }
    )
  }

  // MARK: - Audio File Row

  private func fileRow(for file: AudioFile) -> some View {
    FileRowView(
      file: file,
      isSelected: selectedFile?.id == file.id,
      onDelete: {
        guard let viewModel else { return }
        viewModel.deleteAudioFile(
          file,
          updateSelection: true,
          checkPlayback: true,
          selectedFile: &selectedFile
        )
      }
    )
  }
}

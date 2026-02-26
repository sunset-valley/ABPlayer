import Observation
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
  case audioFile(ABFile)
  case empty
}

/// Hierarchical folder navigation view for the sidebar
struct FolderNavigationView: View {
  init(
    viewModel: FolderNavigationViewModel,
    onSelectFile: @escaping @MainActor (ABFile) async -> Void
  ) {
    self.viewModel = viewModel
    self.onSelectFile = onSelectFile
  }

  @Bindable var viewModel: FolderNavigationViewModel

  let onSelectFile: @MainActor (ABFile) async -> Void

  var body: some View {
    let _ = Self._printChanges()

    VStack(spacing: 0) {
      navigationHeader
      fileList
    }
    .onAppear {
      viewModel.handleAppear()
    }
    .confirmationDialog(
      viewModel.deleteConfirmationTitle,
      isPresented: $viewModel.showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Move to Trash", role: .destructive) {
        viewModel.performDeleteConfirmation(deleteFromDisk: true)
      }
      Button("Remove from Library") {
        viewModel.performDeleteConfirmation(deleteFromDisk: false)
      }
      Button("Cancel", role: .cancel) {
        viewModel.cancelDeleteConfirmation()
      }
    } message: {
      Text(viewModel.deleteConfirmationMessage)
    }
    .onChange(of: viewModel.sortOrder) { _, newValue in
      viewModel.persistSortOrder(newValue)
    }
    .onChange(of: viewModel.selectedFile) { _, newValue in
      viewModel.syncSelectionWithSelectedFile(newValue)
    }
  }

  // MARK: - Navigation Header

  private var navigationHeader: some View {
    FolderNavigationHeaderView(
      currentFolder: viewModel.currentFolder,
      canNavigateBack: viewModel.canNavigateBack(),
      sortOrder: viewModel.sortOrder,
      onNavigateBack: {
        viewModel.navigateBack()
      },
      onSortChange: { viewModel.sortOrder = $0 }
    )
  }

  // MARK: - File List

  private var fileList: some View {
    let currentFolders = viewModel.currentFolders()
    let currentAudioFiles = viewModel.currentAudioFiles()

    return List(selection: listSelection) {
      if !currentFolders.isEmpty {
        Section {
          ForEach(currentFolders) { folder in
            GeometryReader { geometry in
              folderRow(for: folder)
                .contentShape(Rectangle())
                .gesture(
                  pressGesture(
                    for: .folder(folder),
                    rowSize: geometry.size
                  )
                )
            }
            .frame(height: 60)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())
            .listRowBackground(
              viewModel.pressing == SelectionItem.folder(folder)
                ? Color.asset.listHighlight
                : .clear
            )
            .tag(SelectionItem.folder(folder))
          }
        }
      }

      if !currentAudioFiles.isEmpty {
        Section {
          ForEach(currentAudioFiles) { file in
            GeometryReader { geometry in
              fileRow(for: file)
                .contentShape(Rectangle())
                .simultaneousGesture(
                  pressGesture(
                    for: .audioFile(file),
                    rowSize: geometry.size
                  )
                )
            }
            .frame(height: 60)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())
            .onHover {
              viewModel.setHovering(isHovering: $0, file: file)
            }
            .listRowBackground(viewModel.audioFileRowBackground(for: file))
            .tag(SelectionItem.audioFile(file))
          }
        }
      }
    }
    .onDeleteCommand {
      viewModel.handleDeleteCommand()
    }
    .padding(.horizontal, -8)
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

  private var listSelection: Binding<SelectionItem?> {
    Binding(
      get: {
        viewModel.selection
      },
      set: { newSelection in
        guard let newSelection, !viewModel.isDeselecting else { return }
        viewModel.selection = newSelection
        viewModel.handleSelectionChange(
          newSelection,
          onSelectFile: onSelectFile
        )
      }
    )
  }

  private func pressGesture(for selection: SelectionItem, rowSize: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { _ in
        viewModel.handlePressChanged(for: selection)
      }
      .onEnded { value in
        let isInsideRow = CGRect(origin: .zero, size: rowSize).contains(value.location)
        viewModel.handlePressEnded(
          for: selection,
          isInsideRow: isInsideRow,
          onSelectFile: onSelectFile
        )
      }
  }

  // MARK: - Folder Row

  private func folderRow(for folder: Folder) -> some View {
    FolderRowView(
      folder: folder,
      onDelete: {
        viewModel.requestDelete(.folder(folder))
      }
    )
  }

  // MARK: - Audio File Row

  private func fileRow(for file: ABFile) -> some View {
    FileRowView(
      file: file,
      isSelected: viewModel.selection == .audioFile(file),
      isFailed: file.loadError != nil,
      onDelete: {
        viewModel.requestDelete(.audioFile(file))
      }
    )
  }
}

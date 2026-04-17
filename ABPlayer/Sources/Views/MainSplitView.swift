import Combine
import Observation
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#endif

@MainActor
public struct MainSplitView: View {
  public enum ImportType {
    case file
    case folder

    var allowedContentTypes: [UTType] {
      switch self {
      case .file:
        return [.audio, .movie]
      case .folder:
        return [.folder]
      }
    }
  }

  @Environment(PlayerManager.self) private var playerManager: PlayerManager
  @Environment(SessionTracker.self) private var sessionTracker: SessionTracker
  @Environment(LibrarySettings.self) private var librarySettings
  @Environment(\.modelContext) private var modelContext

  @State private var mainSplitViewModel = MainSplitViewModel()

  public init() {}

  public var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 400)
    } detail: {
      if let selectedFile = mainSplitViewModel.folderNavigationViewModel?.selectedFile {
        MainSplitDetailView(
          selectedFile: selectedFile,
          viewModel: mainSplitViewModel,
          sessionTracker: sessionTracker
        )
      } else {
        EmptyStateView()
      }
    }
    .frame(minWidth: 1000, minHeight: 600)
    .toolbar {
      if let folderNavigationViewModel = mainSplitViewModel.folderNavigationViewModel {
        ToolbarItem(placement: .automatic) {
          ContinueWatchingToolbarMenuView(
            loadItems: {
              folderNavigationViewModel.globalContinueWatchingItems()
            },
            onPlayItem: { file in
              await folderNavigationViewModel.playContinueWatching(file)
            }
          )
        }
      }
    }
    .onAppear {
      mainSplitViewModel.configureIfNeeded(
        modelContext: modelContext,
        playerManager: playerManager,
        librarySettings: librarySettings,
        sessionTracker: sessionTracker
      )
    }
    .task {
      mainSplitViewModel.restorePlaybackQueueIfNeeded()
    }
    .onChange(of: mainSplitViewModel.folderNavigationViewModel?.sortOrder) { _, _ in
      mainSplitViewModel.syncQueueIfCurrentListMatchesSource()
    }
    .onChange(of: mainSplitViewModel.folderNavigationViewModel?.refreshToken) { _, _ in
      mainSplitViewModel.syncQueueIfCurrentListMatchesSource()
    }
    .onChange(of: librarySettings.libraryPath) { _, _ in
      Task { @MainActor in
        await mainSplitViewModel.folderNavigationViewModel?.handleLibraryPathChanged()
      }
    }
    .onChange(of: mainSplitViewModel.folderNavigationViewModel?.selectedFile?.isVideo) { _, isVideo in
      guard let isVideo else { return }
      mainSplitViewModel.switchMediaType(to: isVideo ? .video : .audio)
    }
    .onChange(of: playerManager.currentFile?.id) { _, _ in
      mainSplitViewModel.folderNavigationViewModel?.syncSelectedFileWithPlayer()
    }
    #if os(macOS)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
      sessionTracker.handlePlaybackStateChanged(isPlaying: false)
      let semaphore = DispatchSemaphore(value: 0)
      Task {
        await sessionTracker.shutdownAndWait()
        semaphore.signal()
      }
      _ = semaphore.wait(timeout: .now() + 1)
    }
    #endif
    .fileImporter(
      isPresented: Binding(
        get: { mainSplitViewModel.folderNavigationViewModel?.pendingImportType != nil },
        set: { presented in
          if !presented {
            mainSplitViewModel.folderNavigationViewModel?.pendingImportType = nil
          }
        }
      ),
      allowedContentTypes: mainSplitViewModel.folderNavigationViewModel?.importType?.allowedContentTypes ?? [],
      allowsMultipleSelection: false,
      onCompletion: { result in
        mainSplitViewModel.folderNavigationViewModel?.handleImportResult(result)
      }
    )
    .alert(
      "Import Failed",
      isPresented: .constant(mainSplitViewModel.folderNavigationViewModel?.importErrorMessage != nil),
      presenting: mainSplitViewModel.folderNavigationViewModel?.importErrorMessage
    ) { _ in
      Button("OK", role: .cancel) {
        mainSplitViewModel.folderNavigationViewModel?.importErrorMessage = nil
      }
    } message: { message in
      Text(message)
    }
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    Group {
      if let folderNavigationViewModel = mainSplitViewModel.folderNavigationViewModel {
        MainSplitSidebarView(
          viewModel: folderNavigationViewModel,
          isClearingData: mainSplitViewModel.isClearingData,
          onSelectFile: { file in
            await mainSplitViewModel.handleFileSelection(file)
          },
          onImportFile: {
            mainSplitViewModel.folderNavigationViewModel?.importType = .file
            mainSplitViewModel.folderNavigationViewModel?.pendingImportType = .file
          },
          onImportFolder: {
            mainSplitViewModel.folderNavigationViewModel?.importType = .folder
            mainSplitViewModel.folderNavigationViewModel?.pendingImportType = .folder
          },
          onRefresh: {
            await mainSplitViewModel.folderNavigationViewModel?.refreshCurrentFolder()
            mainSplitViewModel.syncQueueIfCurrentListMatchesSource()
          },
          onPlayContinueWatching: { file in
            await mainSplitViewModel.folderNavigationViewModel?.playContinueWatching(file)
          },
          onClearAllData: {
            mainSplitViewModel.isClearingData = true
            try? await Task.sleep(nanoseconds: 200_000_000)
            await mainSplitViewModel.clearAllData()
            mainSplitViewModel.isClearingData = false
          }
        )
      }
    }
  }
}

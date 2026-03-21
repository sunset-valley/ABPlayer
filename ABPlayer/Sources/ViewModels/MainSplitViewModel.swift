import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class MainSplitViewModel {
  typealias MediaType = MainSplitPaneAllocationState.MediaType
  typealias Panel = MainSplitPaneAllocationState.Panel

  // MARK: - Layout State

  var folderNavigationViewModel: FolderNavigationViewModel?
  var isClearingData: Bool = false
  private var didAttemptRestoreNavigationPath = false

  private let paneAllocationState = MainSplitPaneAllocationState()

  private var modelContext: ModelContext?
  private var playerManager: PlayerManager?
  private var sessionTracker: SessionTracker?
  private var librarySettings: LibrarySettings?

  var showContentPanel: Bool {
    get { paneAllocationState.showContentPanel }
    set { paneAllocationState.showContentPanel = newValue }
  }

  var showBottomPanel: Bool {
    get { paneAllocationState.showBottomPanel }
    set { paneAllocationState.showBottomPanel = newValue }
  }

  var horizontalPersistenceKey: String {
    paneAllocationState.horizontalPersistenceKey
  }

  var verticalPersistenceKey: String {
    paneAllocationState.verticalPersistenceKey
  }

  // MARK: - Global Pane Allocation State (Persisted)

  var leftTabs: [PaneContent] {
    get { paneAllocationState.leftTabs }
    set { paneAllocationState.leftTabs = newValue }
  }

  var rightTabs: [PaneContent] {
    get { paneAllocationState.rightTabs }
    set { paneAllocationState.rightTabs = newValue }
  }

  var leftSelection: PaneContent? {
    get { paneAllocationState.leftSelection }
    set { paneAllocationState.leftSelection = newValue }
  }

  var rightSelection: PaneContent? {
    get { paneAllocationState.rightSelection }
    set { paneAllocationState.rightSelection = newValue }
  }

  var currentMediaType: MediaType {
    paneAllocationState.currentMediaType
  }

  // MARK: - Constants

  let minWidthOfPlayerSection: CGFloat = 480
  let minWidthOfContentPanel: CGFloat = 300
  let defaultPlayerSectionWidth: Double = 480
  let minHeightOfTopPanel: CGFloat = 200
  let minHeightOfBottomPanel: CGFloat = 150
  let defaultTopPanelHeight: Double = 400
  let dividerWidth: CGFloat = 8

  // MARK: - Initialization

  init() {}

  func configureIfNeeded(
    modelContext: ModelContext,
    playerManager: PlayerManager,
    librarySettings: LibrarySettings,
    sessionTracker: SessionTracker
  ) {
    self.modelContext = modelContext
    self.playerManager = playerManager
    self.librarySettings = librarySettings
    self.sessionTracker = sessionTracker

    sessionTracker.setModelContainer(modelContext.container)
    playerManager.sessionTracker = sessionTracker

    if folderNavigationViewModel == nil {
      folderNavigationViewModel = FolderNavigationViewModel(
        modelContext: modelContext,
        playerManager: playerManager,
        librarySettings: librarySettings
      )
    }

    setupPlaybackEndedHandler()
  }

  func updatePlaybackQueueForCurrentFolder() {
    guard let playerManager else { return }

    guard let folderNavigationViewModel else {
      playerManager.playbackQueue.updateQueue([])
      return
    }

    playerManager.playbackQueue.updateQueue(folderNavigationViewModel.currentAudioFiles())
  }

  func restoreLastSelectionIfNeeded() {
    guard
      let folderNavigationViewModel,
      let playerManager
    else {
      return
    }

    restoreNavigationPathIfNeeded(folderNavigationViewModel: folderNavigationViewModel)

    if let currentFile = playerManager.currentFile,
       let matchedFile = fetchAudioFile(withID: currentFile.id)
    {
      folderNavigationViewModel.selectedFile = matchedFile
      playerManager.currentFile = matchedFile
      return
    }

    if let selectedFile = folderNavigationViewModel.selectedFile {
      if playerManager.currentFile?.id != selectedFile.id {
        Task { await playerManager.selectFile(selectedFile, fromStart: false, debounce: true) }
      }
      return
    }

    if let lastSelectedAudioFileID = folderNavigationViewModel.lastSelectedAudioFileID,
       let lastID = UUID(uuidString: lastSelectedAudioFileID),
       let file = fetchAudioFile(withID: lastID)
    {
      Task { await playerManager.selectFile(file, fromStart: false, debounce: true) }
    }
  }

  private func restoreNavigationPathIfNeeded(folderNavigationViewModel: FolderNavigationViewModel) {
    guard !didAttemptRestoreNavigationPath else { return }
    defer { didAttemptRestoreNavigationPath = true }

    guard folderNavigationViewModel.currentFolder == nil,
      folderNavigationViewModel.navigationPath.isEmpty,
      let lastFolderID = folderNavigationViewModel.lastFolderID,
      let folderUUID = UUID(uuidString: lastFolderID),
      let folder = fetchFolder(withID: folderUUID)
    else {
      return
    }

    var path: [Folder] = []
    var currentFolder: Folder? = folder
    while let unwrappedFolder = currentFolder {
      path.insert(unwrappedFolder, at: 0)
      currentFolder = unwrappedFolder.parent
    }

    folderNavigationViewModel.navigationPath = path
    folderNavigationViewModel.currentFolder = folder
  }

  func availableContents(for panel: Panel) -> [PaneContent] {
    paneAllocationState.availableContents(for: panel)
  }

  func move(content: PaneContent, to panel: Panel) {
    paneAllocationState.move(content: content, to: panel)
  }

  func remove(content: PaneContent, from panel: Panel) {
    paneAllocationState.remove(content: content, from: panel)
  }

  // MARK: - Media Type Switching

  func switchMediaType(to mediaType: MediaType) {
    paneAllocationState.switchMediaType(to: mediaType)
  }

  private func fetchAudioFile(withID id: UUID) -> ABFile? {
    guard let modelContext else { return nil }

    let descriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { $0.id == id }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func fetchFolder(withID id: UUID) -> Folder? {
    guard let modelContext else { return nil }

    let descriptor = FetchDescriptor<Folder>(
      predicate: #Predicate<Folder> { $0.id == id }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func setupPlaybackEndedHandler() {
    guard let playerManager else { return }

    playerManager.onPlaybackEnded = { @MainActor [playerManager] currentFile in
      guard let currentFile else { return }

      playerManager.playbackQueue.loopMode = playerManager.loopMode
      playerManager.playbackQueue.setCurrentFile(currentFile)

      guard let nextFile = playerManager.playbackQueue.playNext() else { return }

      Task { @MainActor in
        await playerManager.playFile(nextFile, fromStart: true)
      }
    }
  }

  func clearAllData() async {
    guard
      let modelContext,
      let playerManager,
      let sessionTracker
    else {
      return
    }

    do {
      if playerManager.isPlaying {
        await playerManager.togglePlayPause()
      }
      resetNavigationAndPlayerState(playerManager: playerManager)
      try deleteAllEntities(of: ABFile.self, in: modelContext)
      try deleteAllEntities(of: Folder.self, in: modelContext)

      sessionTracker.endSessionIfIdle()

      try deleteAllEntities(of: ListeningSession.self, in: modelContext)
      try modelContext.save()
    } catch {
      folderNavigationViewModel?.importErrorMessage = "Failed to clear data: \(error.localizedDescription)"
    }
  }

  private func resetNavigationAndPlayerState(playerManager: PlayerManager) {
    folderNavigationViewModel?.selectedFile = nil
    folderNavigationViewModel?.currentFolder = nil
    folderNavigationViewModel?.navigationPath = []
    playerManager.currentFile = nil
  }

  private func deleteAllEntities<T: PersistentModel>(of type: T.Type, in modelContext: ModelContext) throws {
    let entities = try modelContext.fetch(FetchDescriptor<T>())
    for entity in entities {
      modelContext.delete(entity)
    }
  }
}

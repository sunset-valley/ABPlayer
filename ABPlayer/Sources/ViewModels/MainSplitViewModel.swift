import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class MainSplitViewModel {
  // MARK: - Media Type

  enum MediaType: String {
    case audio
    case video
  }

  enum Panel {
    case bottomLeft
    case right
  }

  // MARK: - Layout State

  var folderNavigationViewModel: FolderNavigationViewModel?
  var isClearingData: Bool = false

  private(set) var currentMediaType: MediaType = .audio
  private var didAttemptRestoreNavigationPath = false

  private var modelContext: ModelContext?
  private var playerManager: PlayerManager?
  private var sessionTracker: SessionTracker?
  private var librarySettings: LibrarySettings?

  var showContentPanel: Bool {
    didSet {
      UserDefaults.standard.set(showContentPanel, forKey: userDefaultsKey(for: "ShowContentPanel"))
    }
  }

  var showBottomPanel: Bool {
    didSet {
      UserDefaults.standard.set(showBottomPanel, forKey: userDefaultsKey(for: "ShowBottomPanel"))
    }
  }

  var horizontalPersistenceKey: String {
    userDefaultsKey(for: "PlayerSectionWidth")
  }

  var verticalPersistenceKey: String {
    userDefaultsKey(for: "TopPanelHeight")
  }

  // MARK: - Global Pane Allocation State (Persisted)

  var leftTabs: [PaneContent] {
    didSet {
      persistTabs(leftTabs, suffix: "LeftTabs")
    }
  }

  var rightTabs: [PaneContent] {
    didSet {
      persistTabs(rightTabs, suffix: "RightTabs")
    }
  }

  var leftSelection: PaneContent? {
    didSet {
      persistSelection(leftSelection, suffix: "LeftSelection")
    }
  }

  var rightSelection: PaneContent? {
    didSet {
      persistSelection(rightSelection, suffix: "RightSelection")
    }
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

  init() {
    self.showContentPanel = Self.loadShowContentPanel(for: .audio)
    self.showBottomPanel = Self.loadShowBottomPanel(for: .audio)

    let loadedLeftTabs = Self.loadTabs(
      for: .audio,
      suffix: "LeftTabs",
      default: [.transcription]
    )
    let loadedRightTabs = Self.loadTabs(
      for: .audio,
      suffix: "RightTabs",
      default: [.segments]
    )

    self.leftTabs = loadedLeftTabs
    self.rightTabs = loadedRightTabs

    self.leftSelection = Self.loadSelection(
      for: .audio,
      suffix: "LeftSelection",
      tabs: loadedLeftTabs
    )
    self.rightSelection = Self.loadSelection(
      for: .audio,
      suffix: "RightSelection",
      tabs: loadedRightTabs
    )

    sanitizeAllocations()
    normalizeSelection(for: .bottomLeft)
    normalizeSelection(for: .right)
  }

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

  func handleSelectedFileMediaTypeChange(_ isVideo: Bool?) {
    guard let isVideo else { return }
    switchMediaType(to: isVideo ? .video : .audio)
  }

  func syncSelectedFileWithPlayer() {
    folderNavigationViewModel?.syncSelectedFileWithPlayer()
  }

  func prepareImport(_ type: MainSplitView.ImportType) {
    folderNavigationViewModel?.importType = type
    folderNavigationViewModel?.presetnImportType = type
  }

  func refreshCurrentFolderAndQueue() async {
    await folderNavigationViewModel?.refreshCurrentFolder()
    updatePlaybackQueueForCurrentFolder()
  }

  func handleImportResult(_ result: Result<[URL], Error>) {
    folderNavigationViewModel?.handleImportResult(result)
  }

  var importErrorMessage: String? {
    get { folderNavigationViewModel?.importErrorMessage }
    set { folderNavigationViewModel?.importErrorMessage = newValue }
  }

  var isImporterPresented: Bool {
    folderNavigationViewModel?.presetnImportType != nil
  }

  func setImporterPresented(_ presented: Bool) {
    if !presented {
      folderNavigationViewModel?.presetnImportType = nil
    }
  }

  func restoreLastSelectionIfNeeded() {
    guard
      let folderNavigationViewModel,
      let playerManager
    else {
      return
    }

    if !didAttemptRestoreNavigationPath {
      defer { didAttemptRestoreNavigationPath = true }

      if folderNavigationViewModel.currentFolder == nil,
         folderNavigationViewModel.navigationPath.isEmpty,
         let lastFolderID = folderNavigationViewModel.lastFolderID,
         let folderUUID = UUID(uuidString: lastFolderID),
         let folder = fetchFolder(withID: folderUUID)
      {
        var path: [Folder] = []
        var currentFolder: Folder? = folder
        while let unwrappedFolder = currentFolder {
          path.insert(unwrappedFolder, at: 0)
          currentFolder = unwrappedFolder.parent
        }
        folderNavigationViewModel.navigationPath = path
        folderNavigationViewModel.currentFolder = folder
      }
    }

    guard folderNavigationViewModel.selectedFile == nil else {
      if let currentFile = playerManager.currentFile,
         let matchedFile = fetchAudioFile(withID: currentFile.id)
      {
        folderNavigationViewModel.selectedFile = matchedFile
        playerManager.currentFile = matchedFile
        return
      }

      if let selectedFile = folderNavigationViewModel.selectedFile,
         playerManager.currentFile?.id != selectedFile.id
      {
        Task { await selectFile(selectedFile) }
      }
      return
    }

    if let currentFile = playerManager.currentFile,
       let matchedFile = fetchAudioFile(withID: currentFile.id)
    {
      folderNavigationViewModel.selectedFile = matchedFile
      playerManager.currentFile = matchedFile
      return
    }

    if let lastSelectedAudioFileID = folderNavigationViewModel.lastSelectedAudioFileID,
       let lastID = UUID(uuidString: lastSelectedAudioFileID),
       let file = fetchAudioFile(withID: lastID)
    {
      Task { await selectFile(file) }
    }
  }

  func clearAllDataAsync() async {
    isClearingData = true
    try? await Task.sleep(nanoseconds: 200_000_000)
    await clearAllData()
    isClearingData = false
  }

  func availableContents(for panel: Panel) -> [PaneContent] {
    let currentTabs = tabs(for: panel)
    return PaneContent.allocatableCases.filter { !currentTabs.contains($0) }
  }

  func move(content: PaneContent, to panel: Panel) {
    switch panel {
    case .bottomLeft:
      remove(content: content, from: .right)
      if !leftTabs.contains(content) {
        leftTabs.append(content)
      }
      leftSelection = content
    case .right:
      remove(content: content, from: .bottomLeft)
      if !rightTabs.contains(content) {
        rightTabs.append(content)
      }
      rightSelection = content
    }
  }

  func remove(content: PaneContent, from panel: Panel) {
    switch panel {
    case .bottomLeft:
      leftTabs.removeAll { $0 == content }
      if leftSelection == content {
        leftSelection = nil
      }
    case .right:
      rightTabs.removeAll { $0 == content }
      if rightSelection == content {
        rightSelection = nil
      }
    }
    
    normalizeSelection(for: panel)
  }

  // MARK: - Media Type Switching

  func switchMediaType(to mediaType: MediaType) {
    guard currentMediaType != mediaType else { return }

    currentMediaType = mediaType

    showContentPanel = Self.loadShowContentPanel(for: mediaType)
    showBottomPanel = Self.loadShowBottomPanel(for: mediaType)

    let loadedLeftTabs = Self.loadTabs(
      for: mediaType,
      suffix: "LeftTabs",
      default: [.transcription]
    )
    let loadedRightTabs = Self.loadTabs(
      for: mediaType,
      suffix: "RightTabs",
      default: [.segments]
    )

    leftTabs = loadedLeftTabs
    rightTabs = loadedRightTabs

    leftSelection = Self.loadSelection(
      for: mediaType,
      suffix: "LeftSelection",
      tabs: loadedLeftTabs
    )
    rightSelection = Self.loadSelection(
      for: mediaType,
      suffix: "RightSelection",
      tabs: loadedRightTabs
    )

    sanitizeAllocations()
    normalizeSelection(for: .bottomLeft)
    normalizeSelection(for: .right)
  }

  // MARK: - Private Helpers (Allocation)

  private func tabs(for panel: Panel) -> [PaneContent] {
    switch panel {
    case .bottomLeft: return leftTabs
    case .right: return rightTabs
    }
  }

  private func normalizeSelection(for panel: Panel) {
    switch panel {
    case .bottomLeft:
      guard !leftTabs.isEmpty else {
        leftSelection = nil
        return
      }
      if let leftSelection, leftTabs.contains(leftSelection) {
        return
      }
      leftSelection = leftTabs.first

    case .right:
      guard !rightTabs.isEmpty else {
        rightSelection = nil
        return
      }
      if let rightSelection, rightTabs.contains(rightSelection) {
        return
      }
      rightSelection = rightTabs.first
    }
  }

  private func sanitizeAllocations() {
    // Ensure no duplicates within a panel.
    leftTabs = Self.deduped(leftTabs)
    rightTabs = Self.deduped(rightTabs)

    // Enforce global uniqueness: if overlap exists, right loses.
    let overlap = Set(leftTabs).intersection(Set(rightTabs))
    if !overlap.isEmpty {
      rightTabs.removeAll { overlap.contains($0) }
      if let rightSelection, overlap.contains(rightSelection) {
        self.rightSelection = nil
      }
    }
  }

  // MARK: - Persistence

  private func userDefaultsKey(for suffix: String) -> String {
    "mainSplit\(currentMediaType.rawValue.capitalized)\(suffix)"
  }

  private static func userDefaultsKey(for suffix: String, mediaType: MediaType) -> String {
    "mainSplit\(mediaType.rawValue.capitalized)\(suffix)"
  }

  private func persistTabs(_ tabs: [PaneContent], suffix: String) {
    let values = tabs.filter(\.isAllocatable).map(\.rawValue)
    UserDefaults.standard.set(values, forKey: userDefaultsKey(for: suffix))
  }

  private func persistSelection(_ selection: PaneContent?, suffix: String) {
    let key = userDefaultsKey(for: suffix)
    if let selection, selection.isAllocatable {
      UserDefaults.standard.set(selection.rawValue, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private static func loadShowContentPanel(for mediaType: MediaType) -> Bool {
    let key = userDefaultsKey(for: "ShowContentPanel", mediaType: mediaType)
    if UserDefaults.standard.object(forKey: key) == nil {
      return true
    }
    return UserDefaults.standard.bool(forKey: key)
  }

  private static func loadShowBottomPanel(for mediaType: MediaType) -> Bool {
    let key = userDefaultsKey(for: "ShowBottomPanel", mediaType: mediaType)
    if UserDefaults.standard.object(forKey: key) == nil {
      return true
    }
    return UserDefaults.standard.bool(forKey: key)
  }

  private static func loadTabs(
    for mediaType: MediaType,
    suffix: String,
    default defaultValue: [PaneContent]
  ) -> [PaneContent] {
    let key = userDefaultsKey(for: suffix, mediaType: mediaType)
    let rawValues = UserDefaults.standard.stringArray(forKey: key) ?? defaultValue.map(\.rawValue)

    let mapped = rawValues.compactMap(PaneContent.init(rawValue:)).filter(\.isAllocatable)
    let dedupedTabs = deduped(mapped)

    // If persisted array is empty/invalid, fall back to default.
    if dedupedTabs.isEmpty {
      return deduped(defaultValue.filter(\.isAllocatable))
    }
    return dedupedTabs
  }

  private static func loadSelection(
    for mediaType: MediaType,
    suffix: String,
    tabs: [PaneContent]
  ) -> PaneContent? {
    guard !tabs.isEmpty else { return nil }

    let key = userDefaultsKey(for: suffix, mediaType: mediaType)
    guard
      let rawValue = UserDefaults.standard.string(forKey: key),
      let value = PaneContent(rawValue: rawValue),
      value.isAllocatable,
      tabs.contains(value)
    else {
      return tabs.first
    }

    return value
  }

  private static func deduped(_ values: [PaneContent]) -> [PaneContent] {
    var seen = Set<PaneContent>()
    var result: [PaneContent] = []
    for value in values where value.isAllocatable {
      if seen.insert(value).inserted {
        result.append(value)
      }
    }
    return result
  }

  func selectFile(_ file: ABFile, fromStart: Bool = false, debounce: Bool = true) async {
    await playerManager?.selectFile(file, fromStart: fromStart, debounce: debounce)
  }

  private func playFile(_ file: ABFile, fromStart: Bool = false) async {
    await playerManager?.playFile(file, fromStart: fromStart)
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
        await self.playFile(nextFile, fromStart: true)
      }
    }
  }

  private func clearAllData() async {
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

      folderNavigationViewModel?.selectedFile = nil
      folderNavigationViewModel?.currentFolder = nil
      folderNavigationViewModel?.navigationPath = []
      playerManager.currentFile = nil

      let audioFiles = try modelContext.fetch(FetchDescriptor<ABFile>())
      for audioFile in audioFiles {
        modelContext.delete(audioFile)
      }

      let folders = try modelContext.fetch(FetchDescriptor<Folder>())
      for folder in folders {
        modelContext.delete(folder)
      }

      sessionTracker.endSessionIfIdle()

      let sessions = try modelContext.fetch(FetchDescriptor<ListeningSession>())
      for session in sessions {
        modelContext.delete(session)
      }

      try modelContext.save()
    } catch {
      folderNavigationViewModel?.importErrorMessage = "Failed to clear data: \(error.localizedDescription)"
    }
  }
}

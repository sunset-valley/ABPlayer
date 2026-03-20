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

  func restoreLastSelectionIfNeeded() {
    guard
      let folderNavigationViewModel,
      let playerManager
    else {
      return
    }

    restoreNavigationPathIfNeeded(folderNavigationViewModel: folderNavigationViewModel)

    guard folderNavigationViewModel.selectedFile == nil else {
      if syncSelectedFileWithCurrentPlayerFile(
        folderNavigationViewModel: folderNavigationViewModel,
        playerManager: playerManager
      ) {
        return
      }

      if let selectedFile = folderNavigationViewModel.selectedFile,
         playerManager.currentFile?.id != selectedFile.id
      {
        Task { await playerManager.selectFile(selectedFile, fromStart: false, debounce: true) }
      }
      return
    }

    if syncSelectedFileWithCurrentPlayerFile(
      folderNavigationViewModel: folderNavigationViewModel,
      playerManager: playerManager
    ) {
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

  private func syncSelectedFileWithCurrentPlayerFile(
    folderNavigationViewModel: FolderNavigationViewModel,
    playerManager: PlayerManager
  ) -> Bool {
    guard
      let currentFile = playerManager.currentFile,
      let matchedFile = fetchAudioFile(withID: currentFile.id)
    else {
      return false
    }

    folderNavigationViewModel.selectedFile = matchedFile
    playerManager.currentFile = matchedFile
    return true
  }

  func availableContents(for panel: Panel) -> [PaneContent] {
    let currentTabs = tabs(for: panel)
    return PaneContent.allocatableCases.filter { !currentTabs.contains($0) }
  }

  func move(content: PaneContent, to panel: Panel) {
    remove(content: content, from: panel == .bottomLeft ? .right : .bottomLeft)
    appendContentIfNeeded(content, to: panel)
    setSelection(content, for: panel)
  }

  func remove(content: PaneContent, from panel: Panel) {
    switch panel {
    case .bottomLeft:
      remove(content, from: &leftTabs, selection: &leftSelection)
    case .right:
      remove(content, from: &rightTabs, selection: &rightSelection)
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
      leftSelection = Self.normalizedSelection(for: leftTabs, current: leftSelection)

    case .right:
      rightSelection = Self.normalizedSelection(for: rightTabs, current: rightSelection)
    }
  }

  private func appendContentIfNeeded(_ content: PaneContent, to panel: Panel) {
    switch panel {
    case .bottomLeft:
      if !leftTabs.contains(content) {
        leftTabs.append(content)
      }
    case .right:
      if !rightTabs.contains(content) {
        rightTabs.append(content)
      }
    }
  }

  private func setSelection(_ content: PaneContent, for panel: Panel) {
    switch panel {
    case .bottomLeft:
      leftSelection = content
    case .right:
      rightSelection = content
    }
  }

  private func remove(
    _ content: PaneContent,
    from tabs: inout [PaneContent],
    selection: inout PaneContent?
  ) {
    tabs.removeAll { $0 == content }
    if selection == content {
      selection = nil
    }
  }

  private static func normalizedSelection(
    for tabs: [PaneContent],
    current: PaneContent?
  ) -> PaneContent? {
    guard !tabs.isEmpty else { return nil }
    if let current, tabs.contains(current) {
      return current
    }
    return tabs.first
  }

  private func sanitizeAllocations() {
    leftTabs = Self.deduped(leftTabs)
    rightTabs = Self.deduped(rightTabs)
    removeOverlapFromRightTabs()
  }

  private func removeOverlapFromRightTabs() {
    let overlap = Set(leftTabs).intersection(Set(rightTabs))
    guard !overlap.isEmpty else { return }

    rightTabs.removeAll { overlap.contains($0) }
    if let rightSelection, overlap.contains(rightSelection) {
      self.rightSelection = nil
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
    loadBoolFromUserDefaults(
      suffix: "ShowContentPanel",
      mediaType: mediaType,
      defaultValue: true
    )
  }

  private static func loadShowBottomPanel(for mediaType: MediaType) -> Bool {
    loadBoolFromUserDefaults(
      suffix: "ShowBottomPanel",
      mediaType: mediaType,
      defaultValue: true
    )
  }

  private static func loadBoolFromUserDefaults(
    suffix: String,
    mediaType: MediaType,
    defaultValue: Bool
  ) -> Bool {
    let key = userDefaultsKey(for: suffix, mediaType: mediaType)
    if UserDefaults.standard.object(forKey: key) == nil {
      return defaultValue
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
      await pausePlaybackIfNeeded(playerManager: playerManager)
      resetNavigationAndPlayerState(playerManager: playerManager)
      try deleteAllAudioFiles(in: modelContext)
      try deleteAllFolders(in: modelContext)

      sessionTracker.endSessionIfIdle()

      try deleteAllListeningSessions(in: modelContext)
      try modelContext.save()
    } catch {
      folderNavigationViewModel?.importErrorMessage = "Failed to clear data: \(error.localizedDescription)"
    }
  }

  private func pausePlaybackIfNeeded(playerManager: PlayerManager) async {
    if playerManager.isPlaying {
      await playerManager.togglePlayPause()
    }
  }

  private func resetNavigationAndPlayerState(playerManager: PlayerManager) {
    folderNavigationViewModel?.selectedFile = nil
    folderNavigationViewModel?.currentFolder = nil
    folderNavigationViewModel?.navigationPath = []
    playerManager.currentFile = nil
  }

  private func deleteAllAudioFiles(in modelContext: ModelContext) throws {
    let audioFiles = try modelContext.fetch(FetchDescriptor<ABFile>())
    for audioFile in audioFiles {
      modelContext.delete(audioFile)
    }
  }

  private func deleteAllFolders(in modelContext: ModelContext) throws {
    let folders = try modelContext.fetch(FetchDescriptor<Folder>())
    for folder in folders {
      modelContext.delete(folder)
    }
  }

  private func deleteAllListeningSessions(in modelContext: ModelContext) throws {
    let sessions = try modelContext.fetch(FetchDescriptor<ListeningSession>())
    for session in sessions {
      modelContext.delete(session)
    }
  }
}

import OSLog
import SwiftData
import SwiftUI

private struct RecentlyPlayedCandidate: Sendable {
  let fileID: UUID
  let directoryKey: String
  let relativePath: String
  let folderPathSummary: String
  let lastPlayedAt: Date
  let position: Double
  let duration: Double?
}

@MainActor
@Observable
final class FolderNavigationViewModel {
  struct SyncStatus {
    var isRunning: Bool = false
    var message: String?
  }

  struct RecentlyPlayedItem: Identifiable {
    let file: ABFile
    let folderPathSummary: String
    let lastPlayedAt: Date
    let position: Double
    let duration: Double?
    let isCurrentFile: Bool

    var id: UUID { file.id }

    var progress: Double? {
      guard let duration, duration > 0 else { return nil }
      return min(max(position / duration, 0), 1)
    }
  }

  private let modelContext: ModelContext
  private let playerManager: PlayerManager
  private let librarySettings: LibrarySettings
  
  private let navigationService: NavigationService
  private let selectionService: SelectionStateService
  private let deletionService: DeletionService
  private let importService: ImportService

  var sortOrder: SortOrder = .nameAZ {
    didSet {
      UserDefaults.standard.set(sortOrder.rawValue, forKey: UserDefaultsKey.folderNavigationSortOrder)
    }
  }
  var hovering: SelectionItem?
  var pressing: SelectionItem?
  var isDeselecting = false
  var selectionBeforePress: SelectionItem?

  var deleteTarget: SelectionItem?
  var showDeleteConfirmation = false
  
  var importType: MainSplitView.ImportType?
  var pendingImportType: MainSplitView.ImportType?
  
  /// Observation trigger: bumped after import/refresh to invalidate `currentFolders()` / `currentAudioFiles()`.
  private(set) var refreshToken = 0
  
  var currentFolder: Folder? {
    get { navigationService.currentFolder }
    set { navigationService.currentFolder = newValue }
  }
  
  var navigationPath: [Folder] {
    get { navigationService.navigationPath }
    set { navigationService.navigationPath = newValue }
  }
  
  var selectedFile: ABFile? {
    get { selectionService.selectedFile }
    set {
      selectionService.selectedFile = newValue

      if let newValue {
        selectionService.selection = .audioFile(newValue)
      } else if case .audioFile? = selectionService.selection {
        selectionService.selection = nil
      }
    }
  }
  
  var selection: SelectionItem? {
    get { selectionService.selection }
    set { selectionService.selection = newValue }
  }
  
  var lastSelectedAudioFileID: String? {
    get { selectionService.lastSelectedAudioFileID }
    set { selectionService.lastSelectedAudioFileID = newValue }
  }
  
  var lastFolderID: String? {
    get { selectionService.lastFolderID }
    set { selectionService.lastFolderID = newValue }
  }
  
  var lastSelectionItemID: String? {
    get { selectionService.lastSelectionItemID }
    set { selectionService.lastSelectionItemID = newValue }
  }
  
  var importErrorMessage: String? {
    get { importService.importErrorMessage }
    set { importService.importErrorMessage = newValue }
  }

  var syncStatus = SyncStatus()
  var recentlyPlayedItemInCurrentFolder: RecentlyPlayedItem?
  var globalRecentlyPlayedItems: [RecentlyPlayedItem] = []
  var isLoadingGlobalRecentlyPlayed = false

  private var recentlyPlayedRevision = 0
  private var loadedGlobalRecentlyPlayedRevision: Int?
  private var loadedGlobalRecentlyPlayedLimit: Int?
  private var currentFolderRecentlyPlayedRequestID: UUID?
  private var globalRecentlyPlayedRequestID: UUID?

  var lastKnownSortOrder: SortOrder {
    guard
      let rawValue = UserDefaults.standard.string(forKey: UserDefaultsKey.folderNavigationSortOrder),
      let restored = SortOrder(rawValue: rawValue)
    else {
      return .nameAZ
    }
    return restored
  }

  var restoredSelection: SelectionItem? {
    if let selectedFile {
      return .audioFile(selectedFile)
    }

    guard let lastSelectionItemID else { return nil }
    return selectionItem(for: lastSelectionItemID)
  }

  init(
    modelContext: ModelContext,
    playerManager: PlayerManager,
    librarySettings: LibrarySettings,
    selectedFile: ABFile? = nil
  ) {
    self.modelContext = modelContext
    self.playerManager = playerManager
    self.librarySettings = librarySettings
    
    self.navigationService = NavigationService()
    self.selectionService = SelectionStateService()
    self.deletionService = DeletionService(
      modelContext: modelContext,
      playerManager: playerManager,
      librarySettings: librarySettings
    )
    self.importService = ImportService(
      modelContext: modelContext,
      librarySettings: librarySettings
    )
    
    self.selectionService.selectedFile = selectedFile
    
    self.importService.onImportCompleted = { [weak self] in
      self?.rebindPersistentReferences()
      self?.refreshToken += 1
      self?.invalidateRecentlyPlayedData(refreshCurrentFolder: true)
    }
    self.importService.onSyncStateChanged = { [weak self] isRunning, message in
      self?.syncStatus = SyncStatus(isRunning: isRunning, message: message)
    }
  }
  
  func currentFolders() -> [Folder] {
    _ = refreshToken
    let folders = currentFolder.map { childFolders(in: $0) } ?? rootFolders()
    return SortingUtility.sortFolders(folders, by: sortOrder)
  }

  func currentAudioFiles() -> [ABFile] {
    _ = refreshToken
    let files = currentFolder.map { audioFiles(in: $0) } ?? rootAudioFiles()
    return SortingUtility.sortAudioFiles(files, by: sortOrder)
  }

  func refreshCurrentFolderRecentlyPlayed() async {
    let revision = recentlyPlayedRevision
    let requestID = UUID()
    currentFolderRecentlyPlayedRequestID = requestID
    let libraryDirectoryPath = librarySettings.libraryDirectoryURL.path
    let candidates = recentlyPlayedCandidates(from: currentAudioFiles())

    let resolved = await Task.detached(priority: .userInitiated) {
      Self.resolveRecentlyPlayedCandidates(
        candidates,
        libraryDirectoryPath: libraryDirectoryPath,
        limit: 1
      )
    }.value

    guard currentFolderRecentlyPlayedRequestID == requestID else { return }
    guard revision == recentlyPlayedRevision else { return }
    recentlyPlayedItemInCurrentFolder = makeRecentlyPlayedItems(from: resolved).first
  }

  func refreshGlobalRecentlyPlayedIfNeeded(limit: Int = 8) async {
    if loadedGlobalRecentlyPlayedRevision == recentlyPlayedRevision,
      loadedGlobalRecentlyPlayedLimit == limit
    {
      return
    }

    await refreshGlobalRecentlyPlayed(limit: limit)
  }

  func refreshGlobalRecentlyPlayed(limit: Int = 8) async {
    let revision = recentlyPlayedRevision

    guard limit > 0 else {
      globalRecentlyPlayedItems = []
      loadedGlobalRecentlyPlayedRevision = revision
      loadedGlobalRecentlyPlayedLimit = limit
      isLoadingGlobalRecentlyPlayed = false
      return
    }

    let requestID = UUID()
    globalRecentlyPlayedRequestID = requestID
    isLoadingGlobalRecentlyPlayed = true

    let libraryDirectoryPath = librarySettings.libraryDirectoryURL.path
    let candidates = recentlyPlayedCandidates(from: fetchAllAudioFiles())
    let resolved = await Task.detached(priority: .utility) {
      Self.resolveRecentlyPlayedCandidates(
        candidates,
        libraryDirectoryPath: libraryDirectoryPath,
        limit: limit
      )
    }.value

    defer {
      if globalRecentlyPlayedRequestID == requestID {
        isLoadingGlobalRecentlyPlayed = false
        globalRecentlyPlayedRequestID = nil
      }
    }

    guard globalRecentlyPlayedRequestID == requestID else { return }
    guard revision == recentlyPlayedRevision else { return }

    globalRecentlyPlayedItems = makeRecentlyPlayedItems(from: resolved)
    loadedGlobalRecentlyPlayedRevision = revision
    loadedGlobalRecentlyPlayedLimit = limit
  }

  func playRecentlyPlayed(_ file: ABFile) async {
    guard let resolvedFile = fetchAudioFile(id: file.id) else { return }

    navigateToFile(resolvedFile)
    prepareQueue(for: resolvedFile)
    await playerManager.playFile(resolvedFile, fromStart: false)

    invalidateRecentlyPlayedData(refreshCurrentFolder: false)
    await refreshCurrentFolderRecentlyPlayed()
  }

  func setHovering(isHovering: Bool, file: ABFile) {
    hovering = isHovering ? .audioFile(file) : nil
  }

  func audioFileRowBackground(for file: ABFile) -> Color {
    if pressing == .audioFile(file) {
      return Color.asset.listHighlight
    }

    if selection == .audioFile(file) {
      return Color.asset.listHighlight
    }

    if hovering == .audioFile(file) {
      return Color.asset.listHighlight.opacity(0.6)
    }

    return .clear
  }

  func handlePressChanged(for selection: SelectionItem) {
    if selectionBeforePress == nil {
      selectionBeforePress = self.selection
    }
    pressing = selection
  }

  func handlePressEnded(
    for selection: SelectionItem,
    isInsideRow: Bool,
    onSelectFile: @escaping @MainActor (ABFile) async -> Void
  ) {
    pressing = nil
    let previousSelection = selectionBeforePress
    selectionBeforePress = nil

    guard isInsideRow else {
      isDeselecting = true
      self.selection = previousSelection
      isDeselecting = false
      return
    }

    self.selection = selection
    handleSelectionChange(
      selection,
      onSelectFile: onSelectFile
    )
  }

  func requestDelete(_ target: SelectionItem) {
    deleteTarget = target
    showDeleteConfirmation = true
  }

  func cancelDeleteConfirmation() {
    deleteTarget = nil
    showDeleteConfirmation = false
  }

  var deleteConfirmationTitle: String {
    switch deleteTarget {
    case .folder:
      return "Delete Folder?"
    case .audioFile:
      return "Delete File?"
    case .empty, .none:
      return "Delete?"
    }
  }

  var deleteConfirmationMessage: String {
    switch deleteTarget {
    case .folder:
      return "Do you want to move the folder and its contents to the Trash or just remove them from the library?"
    case .audioFile:
      return "Do you want to move the file to the Trash or just remove it from the library?"
    default:
      return "This action cannot be undone."
    }
  }

  func performDeleteConfirmation(deleteFromDisk: Bool) {
    executeDelete(deleteTarget, deleteFromDisk: deleteFromDisk)

    cancelDeleteConfirmation()
  }

  func handleDeleteCommand() {
    guard let selection else { return }

    executeDelete(selection, deleteFromDisk: false)
  }
  
  func handleSelectionChange(
    _ newSelection: SelectionItem?,
    onSelectFile: @escaping @MainActor (ABFile) async -> Void
  ) {
    guard let newSelection else { return }

    selection = newSelection

    switch newSelection {
    case .folder(let folder):
      navigationService.navigateInto(folder)

    case .audioFile(let file):
      Task { @MainActor in
        await onSelectFile(file)
      }

    case .empty:
      break
    }
  }
  
  func deleteFolder(
    _ folder: Folder,
    deleteFromDisk: Bool = true
  ) {
    let folderIDs = collectFolderIDs(in: folder)
    let fileIDs = collectFileIDs(in: folder)
    clearReferences(fileIDs: fileIDs, folderIDs: folderIDs)

    updateSelectedFile { selectedFile in
      deletionService.deleteFolder(
        folder,
        deleteFromDisk: deleteFromDisk,
        selectedFile: &selectedFile
      )
    }

    if lastFolderID == folder.id.uuidString || folderIDs.contains(where: { $0.uuidString == lastFolderID }) {
      lastFolderID = nil
    }

    refreshToken += 1
    invalidateRecentlyPlayedData(refreshCurrentFolder: true)
  }
  
  func deleteAudioFile(
    _ file: ABFile,
    deleteFromDisk: Bool = true,
    updateSelection: Bool = true,
    checkPlayback: Bool = true,
    selectedFile: inout ABFile?
  ) {
    clearReferences(fileIDs: [file.id], folderIDs: [])
    if selectedFile?.id == file.id {
      selectedFile = nil
    }

    deletionService.deleteAudioFile(
      file,
      deleteFromDisk: deleteFromDisk,
      updateSelection: updateSelection,
      checkPlayback: checkPlayback,
      selectedFile: &selectedFile
    )
    
    if updateSelection && selectedFile == nil {
      selectionService.clearSelection()
    }

    refreshToken += 1
    invalidateRecentlyPlayedData(refreshCurrentFolder: true)
  }
  
  func handleImportResult(_ result: Result<[URL], Error>) {
    importService.handleImportResult(
      result,
      importType: importType,
      currentFolder: currentFolder
    )
  }
  
  func refreshCurrentFolder() async {
    let selectedFileIDBeforeRefresh = selectedFile?.id

    guard let currentFolder else {
      await importService.refreshLibraryRoot()
      reconcileAfterModelMutation(preferredSelectedFileID: selectedFileIDBeforeRefresh)
      invalidateRecentlyPlayedData(refreshCurrentFolder: false)
      await refreshCurrentFolderRecentlyPlayed()
      return
    }

    await importService.refreshFolder(currentFolder)
    reconcileAfterModelMutation(preferredSelectedFileID: selectedFileIDBeforeRefresh)

    invalidateRecentlyPlayedData(refreshCurrentFolder: false)
    await refreshCurrentFolderRecentlyPlayed()
  }

  func handleLibraryPathChanged() async {
    clearReferences(fileIDs: [], folderIDs: Set(navigationPath.map(\.id)))
    hovering = nil
    pressing = nil
    selectionBeforePress = nil
    deleteTarget = nil
    showDeleteConfirmation = false
    selectionService.clearSelection()
    navigationPath = []
    currentFolder = nil

    if playerManager.isPlaying {
      await playerManager.togglePlayPause()
    }
    playerManager.currentFile = nil
    playerManager.playbackQueue.clearQueue()

    await importService.refreshLibraryRoot()
    reconcileAfterModelMutation(preferredSelectedFileID: nil)

    invalidateRecentlyPlayedData(refreshCurrentFolder: false)
    await refreshCurrentFolderRecentlyPlayed()
  }
  
  func syncSelectedFileWithPlayer() {
    guard let newFileID = playerManager.currentFile?.id else { return }

    if selectedFile?.id == newFileID {
      return
    }

    guard let matchedFile = fetchAudioFile(id: newFileID) else {
      if selectedFile?.id == newFileID {
        selectedFile = nil
      }
      if case .audioFile(let file) = selection, file.id == newFileID {
        selection = nil
      }
      return
    }

    selectedFile = matchedFile
    invalidateRecentlyPlayedData(refreshCurrentFolder: true)
  }

  private func restoreSelectedFileIfPossible(_ id: UUID?) {
    guard let id, let file = fetchAudioFile(id: id) else { return }
    selectedFile = file
  }

  private func reconcileAfterModelMutation(preferredSelectedFileID: UUID?) {
    rebindPersistentReferences()

    if selectedFile == nil,
      let preferredSelectedFileID,
      let file = fetchAudioFile(id: preferredSelectedFileID)
    {
      selectedFile = file
    }

    let existingFileIDs = fetchAllAudioFileIDs()
    if let currentFileID = playerManager.currentFile?.id,
      !existingFileIDs.contains(currentFileID)
    {
      if playerManager.isPlaying {
        Task {
          await playerManager.togglePlayPause()
        }
      }
      playerManager.currentFile = nil
    }

    let queuedIDs = Set(playerManager.playbackQueue.queuedFiles.map(\.id))
    let missingQueuedIDs = queuedIDs.subtracting(existingFileIDs)
    if !missingQueuedIDs.isEmpty {
      _ = playerManager.playbackQueue.removeFiles(withIDs: missingQueuedIDs)
    }
  }

  private func rebindPersistentReferences() {
    if let currentFolder {
      if let reboundFolder = fetchFolder(id: currentFolder.id) {
        self.currentFolder = reboundFolder
      } else {
        self.currentFolder = nil
      }
    }

    let reboundPath = navigationPath.compactMap { fetchFolder(id: $0.id) }
    navigationPath = reboundPath
    if let currentFolder, !reboundPath.contains(where: { $0.id == currentFolder.id }) {
      navigationPath.append(currentFolder)
    }

    if let selectedFile {
      if let reboundFile = fetchAudioFile(id: selectedFile.id) {
        self.selectedFile = reboundFile
        if case .audioFile = selection {
          selection = .audioFile(reboundFile)
        }
      } else {
        self.selectedFile = nil
        if case .audioFile = selection {
          selection = nil
        }
      }
    }

    if case .folder(let selectedFolder) = selection,
      let reboundFolder = fetchFolder(id: selectedFolder.id)
    {
      selection = .folder(reboundFolder)
    } else if case .folder = selection {
      selection = nil
    }

    hovering = rebindSelectionItem(hovering)
    pressing = rebindSelectionItem(pressing)
    selectionBeforePress = rebindSelectionItem(selectionBeforePress)
    deleteTarget = rebindSelectionItem(deleteTarget)
    if deleteTarget == nil {
      showDeleteConfirmation = false
    }
  }

  private func rebindSelectionItem(_ item: SelectionItem?) -> SelectionItem? {
    guard let item else { return nil }

    switch item {
    case .folder(let folder):
      return fetchFolder(id: folder.id).map { .folder($0) }
    case .audioFile(let file):
      return fetchAudioFile(id: file.id).map { .audioFile($0) }
    case .empty:
      return .empty
    }
  }

  private func clearReferences(fileIDs: Set<UUID>, folderIDs: Set<UUID>) {
    if let selectedID = selectedFile?.id, fileIDs.contains(selectedID) {
      selectedFile = nil
    }

    if matchesDeleted(selection, fileIDs: fileIDs, folderIDs: folderIDs) {
      selection = nil
    }
    if matchesDeleted(hovering, fileIDs: fileIDs, folderIDs: folderIDs) {
      hovering = nil
    }
    if matchesDeleted(pressing, fileIDs: fileIDs, folderIDs: folderIDs) {
      pressing = nil
    }
    if matchesDeleted(selectionBeforePress, fileIDs: fileIDs, folderIDs: folderIDs) {
      selectionBeforePress = nil
    }
    if matchesDeleted(deleteTarget, fileIDs: fileIDs, folderIDs: folderIDs) {
      deleteTarget = nil
      showDeleteConfirmation = false
    }

    if let currentFolderValue = currentFolder, folderIDs.contains(currentFolderValue.id) {
      currentFolder = nil
    }

    if !folderIDs.isEmpty {
      navigationPath.removeAll { folderIDs.contains($0.id) }
      if currentFolder == nil {
        currentFolder = navigationPath.last
      }
    }
  }

  private func matchesDeleted(_ item: SelectionItem?, fileIDs: Set<UUID>, folderIDs: Set<UUID>) -> Bool {
    guard let item else { return false }

    switch item {
    case .folder(let folder):
      return folderIDs.contains(folder.id)
    case .audioFile(let file):
      return fileIDs.contains(file.id)
    case .empty:
      return false
    }
  }

  private func collectFolderIDs(in folder: Folder) -> Set<UUID> {
    var ids: Set<UUID> = [folder.id]
    for subfolder in folder.subfolders {
      ids.formUnion(collectFolderIDs(in: subfolder))
    }
    return ids
  }

  private func collectFileIDs(in folder: Folder) -> Set<UUID> {
    var ids = Set(folder.audioFiles.map(\.id))
    for subfolder in folder.subfolders {
      ids.formUnion(collectFileIDs(in: subfolder))
    }
    return ids
  }

  private func fetchAllAudioFileIDs() -> Set<UUID> {
    let files = (try? modelContext.fetch(FetchDescriptor<ABFile>())) ?? []
    return Set(files.map(\.id))
  }

  private func rootFolders() -> [Folder] {
    let descriptor = FetchDescriptor<Folder>(
      predicate: #Predicate<Folder> { $0.parent == nil },
      sortBy: [SortDescriptor(\Folder.name)]
    )
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  private func fetchAllAudioFiles() -> [ABFile] {
    (try? modelContext.fetch(FetchDescriptor<ABFile>())) ?? []
  }

  private func rootAudioFiles() -> [ABFile] {
    let descriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { $0.folder == nil },
      sortBy: [SortDescriptor(\ABFile.createdAt)]
    )
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  private func childFolders(in folder: Folder) -> [Folder] {
    let parentID = folder.id
    let descriptor = FetchDescriptor<Folder>(
      predicate: #Predicate<Folder> { candidate in
        candidate.parent?.id == parentID
      }
    )
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  private func audioFiles(in folder: Folder) -> [ABFile] {
    let folderID = folder.id
    let descriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { candidate in
        candidate.folder?.id == folderID
      }
    )
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  private func selectionItem(for idString: String) -> SelectionItem? {
    guard let id = UUID(uuidString: idString) else { return nil }

    if let folder = fetchFolder(id: id) {
      return .folder(folder)
    }

    if let file = fetchAudioFile(id: id) {
      return .audioFile(file)
    }

    return nil
  }

  private func fetchFolder(id: UUID) -> Folder? {
    let descriptor = FetchDescriptor<Folder>(
      predicate: #Predicate<Folder> { $0.id == id }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func fetchAudioFile(id: UUID) -> ABFile? {
    let descriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { $0.id == id }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func recentlyPlayedCandidates(from files: [ABFile]) -> [RecentlyPlayedCandidate] {
    files
      .compactMap { file in
        let position = max(file.currentPlaybackPosition, 0)
        guard let lastPlayedAt = file.playbackRecord?.lastPlayedAt,
          !file.relativePath.isEmpty
        else {
          return nil
        }

        return RecentlyPlayedCandidate(
          fileID: file.id,
          directoryKey: directoryKey(for: file.folder),
          relativePath: file.relativePath,
          folderPathSummary: folderPathSummary(for: file.folder),
          lastPlayedAt: lastPlayedAt,
          position: position,
          duration: file.cachedDuration
        )
      }
      .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
  }

  private func makeRecentlyPlayedItems(from candidates: [RecentlyPlayedCandidate]) -> [RecentlyPlayedItem] {
    candidates.compactMap { candidate in
      guard let file = fetchAudioFile(id: candidate.fileID) else { return nil }

      return RecentlyPlayedItem(
        file: file,
        folderPathSummary: candidate.folderPathSummary,
        lastPlayedAt: candidate.lastPlayedAt,
        position: candidate.position,
        duration: candidate.duration,
        isCurrentFile: playerManager.currentFile?.id == file.id
      )
    }
  }

  private func invalidateRecentlyPlayedData(refreshCurrentFolder: Bool) {
    recentlyPlayedRevision += 1
    loadedGlobalRecentlyPlayedRevision = nil
    loadedGlobalRecentlyPlayedLimit = nil
    currentFolderRecentlyPlayedRequestID = nil
    globalRecentlyPlayedRequestID = nil
    recentlyPlayedItemInCurrentFolder = nil
    globalRecentlyPlayedItems = []

    if refreshCurrentFolder {
      Task { @MainActor [weak self] in
        await self?.refreshCurrentFolderRecentlyPlayed()
      }
    }
  }

  nonisolated private static func resolveRecentlyPlayedCandidates(
    _ candidates: [RecentlyPlayedCandidate],
    libraryDirectoryPath: String,
    limit: Int
  ) -> [RecentlyPlayedCandidate] {
    guard limit > 0, !candidates.isEmpty else { return [] }

    let fileManager = FileManager.default
    let libraryDirectoryURL = URL(fileURLWithPath: libraryDirectoryPath)
    var latestByDirectory: [String: RecentlyPlayedCandidate] = [:]
    latestByDirectory.reserveCapacity(candidates.count)

    for candidate in candidates {
      let fileURL = libraryDirectoryURL.appendingPathComponent(candidate.relativePath)
      guard fileManager.fileExists(atPath: fileURL.path) else { continue }

      let existing = latestByDirectory[candidate.directoryKey]
      let existingLastPlayedAt = existing?.lastPlayedAt ?? .distantPast
      if existing == nil || candidate.lastPlayedAt > existingLastPlayedAt {
        latestByDirectory[candidate.directoryKey] = candidate
      }
    }

    return latestByDirectory.values
      .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
      .prefix(limit)
      .map(\.self)
  }

  private func directoryKey(for folder: Folder?) -> String {
    folder?.id.uuidString ?? "library-root"
  }

  private func folderPathSummary(for folder: Folder?) -> String {
    guard let folder else { return "Library" }

    var names: [String] = []
    var current: Folder? = folder
    while let value = current {
      names.insert(value.name, at: 0)
      current = value.parent
    }

    if names.count <= 2 {
      return names.joined(separator: " / ")
    }

    let suffix = names.suffix(2).joined(separator: " / ")
    return "... / \(suffix)"
  }

  private func navigateToFile(_ file: ABFile) {
    if let folder = file.folder {
      let path = folderPath(from: folder)
      navigationPath = path
      currentFolder = folder
    } else {
      navigationPath = []
      currentFolder = nil
    }

    selection = .audioFile(file)
    selectedFile = file
  }

  private func folderPath(from folder: Folder) -> [Folder] {
    var path: [Folder] = []
    var current: Folder? = folder

    while let value = current {
      path.insert(value, at: 0)
      current = value.parent
    }

    return path
  }

  private func prepareQueue(for file: ABFile) {
    let sourceFolderID = file.folder?.id
    let files = sortedFilesForQueue(sourceFolder: file.folder)
    let playbackQueue = playerManager.playbackQueue

    if !playbackQueue.hasQueue {
      playbackQueue.replaceQueue(
        files: files,
        currentFile: file,
        sourceFolderID: sourceFolderID
      )
      return
    }

    if playbackQueue.sourceFolderID == sourceFolderID {
      playbackQueue.syncQueue(files: files, sourceFolderID: sourceFolderID)
      playbackQueue.setCurrentFile(file)
      return
    }

    playbackQueue.replaceQueue(
      files: files,
      currentFile: file,
      sourceFolderID: sourceFolderID
    )
  }

  private func sortedFilesForQueue(sourceFolder: Folder?) -> [ABFile] {
    let files = sourceFolder.map { audioFiles(in: $0) } ?? rootAudioFiles()
    return SortingUtility.sortAudioFiles(files, by: sortOrder)
  }

  private func executeDelete(_ target: SelectionItem?, deleteFromDisk: Bool) {
    switch target {
    case let .folder(folder):
      deleteFolder(
        folder,
        deleteFromDisk: deleteFromDisk
      )

    case let .audioFile(file):
      updateSelectedFile { selectedFile in
        deleteAudioFile(
          file,
          deleteFromDisk: deleteFromDisk,
          updateSelection: true,
          checkPlayback: true,
          selectedFile: &selectedFile
        )
      }

    case .empty, .none:
      break
    }
  }

  private func updateSelectedFile(_ mutation: (inout ABFile?) -> Void) {
    var selectedFile = self.selectedFile
    mutation(&selectedFile)
    self.selectedFile = selectedFile
  }
}

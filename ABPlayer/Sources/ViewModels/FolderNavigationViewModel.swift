import OSLog
import SwiftData
import SwiftUI

@MainActor
@Observable
final class FolderNavigationViewModel {
  private let modelContext: ModelContext
  private let playerManager: PlayerManager
  
  private let navigationService: NavigationService
  private let selectionService: SelectionStateService
  private let deletionService: DeletionService
  private let importService: ImportService

  var sortOrder: SortOrder = .nameAZ
  var hovering: SelectionItem?
  var pressing: SelectionItem?
  var isDeselecting = false
  var selectionBeforePress: SelectionItem?

  var deleteTarget: SelectionItem?
  var showDeleteConfirmation = false
  
  var importType: MainSplitView.ImportType?
  var presetnImportType: MainSplitView.ImportType?
  
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
    set { selectionService.selectedFile = newValue }
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

  init(
    modelContext: ModelContext,
    playerManager: PlayerManager,
    librarySettings: LibrarySettings,
    selectedFile: ABFile? = nil
  ) {
    self.modelContext = modelContext
    self.playerManager = playerManager
    
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
      self?.refreshToken += 1
    }
  }
  
  func sortedFolders(_ folders: [Folder]) -> [Folder] {
    SortingUtility.sortFolders(folders, by: sortOrder)
  }
  
  func sortedAudioFiles(_ files: [ABFile]) -> [ABFile] {
    SortingUtility.sortAudioFiles(files, by: sortOrder)
  }

  func handleAppear() {
    restoreSortOrder()
    restoreSelection()
  }

  func persistSortOrder(_ newValue: SortOrder) {
    UserDefaults.standard.set(newValue.rawValue, forKey: "folderNavigationSortOrder")
  }

  func syncSelectionWithSelectedFile(_ newValue: ABFile?) {
    if let newValue {
      selection = .audioFile(newValue)
    } else if case .audioFile? = selection {
      selection = nil
    }
  }

  func currentFolders() -> [Folder] {
    _ = refreshToken
    let folders = currentFolder.map { Array($0.subfolders) } ?? rootFolders()
    return sortedFolders(folders)
  }

  func currentAudioFiles() -> [ABFile] {
    _ = refreshToken
    let files = currentFolder.map { Array($0.audioFiles) } ?? rootAudioFiles()
    return sortedAudioFiles(files)
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
    switch deleteTarget {
    case let .folder(folder):
      deleteFolder(
        folder,
        deleteFromDisk: deleteFromDisk
      )
    case let .audioFile(file):
      var selectedFile = self.selectedFile
      deleteAudioFile(
        file,
        deleteFromDisk: deleteFromDisk,
        updateSelection: true,
        checkPlayback: true,
        selectedFile: &selectedFile
      )
      self.selectedFile = selectedFile
    case .empty, .none:
      break
    }

    cancelDeleteConfirmation()
  }

  func handleDeleteCommand() {
    guard let selection else { return }

    switch selection {
    case let .folder(folder):
      deleteFolder(
        folder,
        deleteFromDisk: false
      )
    case let .audioFile(file):
      var selectedFile = self.selectedFile
      deleteAudioFile(
        file,
        deleteFromDisk: false,
        updateSelection: true,
        checkPlayback: true,
        selectedFile: &selectedFile
      )
      self.selectedFile = selectedFile
    case .empty:
      break
    }
  }
  
  func navigateInto(_ folder: Folder) {
    navigationService.navigateInto(folder)
  }
  
  func navigateBack() {
    navigationService.navigateBack()
  }
  
  func canNavigateBack() -> Bool {
    navigationService.canNavigateBack()
  }
  
  func handleSelectionChange(
    _ newSelection: SelectionItem?,
    onSelectFile: @escaping @MainActor (ABFile) async -> Void
  ) {
    guard let newSelection else { return }

    selection = newSelection

    switch newSelection {
    case .folder(let folder):
      navigateInto(folder)

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
    var selectedFileRef = selectedFile
    deletionService.deleteFolder(
      folder,
      deleteFromDisk: deleteFromDisk,
      selectedFile: &selectedFileRef
    )
    selectedFile = selectedFileRef

    if deletionService.isSelectedFileInFolder(folder, selectedFile: selectedFile) {
      selectionService.clearSelection()
    }

    if currentFolder?.id == folder.id {
      navigateBack()
    }

    if lastFolderID == folder.id.uuidString {
      lastFolderID = nil
    }
  }
  
  func deleteAudioFile(
    _ file: ABFile,
    deleteFromDisk: Bool = true,
    updateSelection: Bool = true,
    checkPlayback: Bool = true,
    selectedFile: inout ABFile?
  ) {
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
  }
  
  func handleImportResult(_ result: Result<[URL], Error>) {
    importService.handleImportResult(
      result,
      importType: importType,
      currentFolder: currentFolder
    )
  }
  
  func addAudioFile(from url: URL) {
    importService.addAudioFile(from: url, currentFolder: currentFolder)
  }
  
  func importFolder(from url: URL) {
    importService.importFolder(from: url, currentFolder: currentFolder)
  }
  
  func refreshCurrentFolder() async {
    guard let currentFolder else { return }
    await importService.refreshFolder(currentFolder)
  }
  
  func syncSelectedFileWithPlayer() {
    guard let newFileID = playerManager.currentFile?.id else { return }
    
    if selectedFile?.id == newFileID {
      return
    }
    
    let descriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { $0.id == newFileID }
    )

    guard let matchedFile = try? modelContext.fetch(descriptor).first else {
      return
    }
    
    selectedFile = matchedFile
  }

  private func restoreSortOrder() {
    if let savedSortOrder = UserDefaults.standard.string(forKey: "folderNavigationSortOrder"),
       let sortOrder = SortOrder(rawValue: savedSortOrder)
    {
      self.sortOrder = sortOrder
    }
  }

  private func restoreSelection() {
    if let selectedFile {
      selection = .audioFile(selectedFile)
      return
    }

    guard let lastSelectionItemID else { return }
    selection = selectionItem(for: lastSelectionItemID)
  }

  private func rootFolders() -> [Folder] {
    let descriptor = FetchDescriptor<Folder>(
      predicate: #Predicate<Folder> { $0.parent == nil },
      sortBy: [SortDescriptor(\Folder.name)]
    )
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  private func rootAudioFiles() -> [ABFile] {
    let descriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { $0.folder == nil },
      sortBy: [SortDescriptor(\ABFile.createdAt)]
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
}

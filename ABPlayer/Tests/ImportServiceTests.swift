import AVFoundation
import Foundation
import SwiftData
import Testing

@testable import ABPlayerDev

// MARK: - Helpers

@MainActor
private func makeImportTestContext() throws -> (ModelContainer, ModelContext, LibrarySettings, URL) {
  let config = ModelConfiguration(isStoredInMemoryOnly: true)
  let container = try ModelContainer(
    for: ABFile.self, LoopSegment.self, PlaybackRecord.self, Folder.self, SubtitleFile.self,
      Transcription.self,
    configurations: config
  )
  let context = ModelContext(container)
  let libraryDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("ImportServiceTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
  let settings = LibrarySettings()
  settings.libraryPath = libraryDir.path
  return (container, context, settings, libraryDir)
}

@MainActor
private func makeFolderNavigationViewModelTestContext() throws
  -> (ModelContainer, ModelContext, LibrarySettings, PlayerManager, FolderNavigationViewModel, URL)
{
  let (container, context, settings, libraryDir) = try makeImportTestContext()
  let playerManager = PlayerManager(librarySettings: settings, engine: SilentPlayerEngine())
  let viewModel = FolderNavigationViewModel(
    modelContext: context,
    playerManager: playerManager,
    librarySettings: settings
  )
  return (container, context, settings, playerManager, viewModel, libraryDir)
}

@MainActor
private func makeTempSourceFile(named name: String) throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
  try Data("audio".utf8).write(to: url)
  return url
}

@MainActor
private func makeTempRealMediaFile(named name: String) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("\(UUID().uuidString)-\(name)")
  try Data().write(to: url)
  return url
}

@MainActor
private func makeTempExternalFolder(named name: String) throws -> URL {
  let folderURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
  return folderURL
}

@MainActor
private func waitUntil(
  timeoutSteps: Int = 300,
  stepNanoseconds: UInt64 = 10_000_000,
  condition: @escaping @MainActor () -> Bool
) async -> Bool {
  for _ in 0..<timeoutSteps {
    if condition() {
      return true
    }
    await Task.yield()
    try? await Task.sleep(nanoseconds: stepNanoseconds)
  }
  return condition()
}

actor SilentPlayerEngine: PlayerEngineProtocol {
  var currentPlayer: AVPlayer? = AVPlayer()

  func load(
    fileURL: URL,
    resumeTime: Double,
    onDurationLoaded: @MainActor @Sendable @escaping (Double) -> Void,
    onTimeUpdate: @MainActor @Sendable @escaping (Double) -> Void,
    onLoopCheck: @MainActor @Sendable @escaping (Double) -> Void,
    onPlaybackStateChange: @MainActor @Sendable @escaping (Bool) -> Void,
    onPlayerReady: @MainActor @Sendable @escaping (AVPlayer) -> Void
  ) async throws -> AVPlayerItem? {
    return nil
  }

  func play() -> Bool { false }
  func pause() {}
  func syncPauseState() {}
  func syncPlayState() {}
  func seek(to time: Double) {}
  func setVolume(_ volume: Float) async {}
  func teardown() {}
}

actor AlwaysPlayEngine: PlayerEngineProtocol {
  var currentPlayer: AVPlayer? = AVPlayer()

  func load(
    fileURL: URL,
    resumeTime: Double,
    onDurationLoaded: @MainActor @Sendable @escaping (Double) -> Void,
    onTimeUpdate: @MainActor @Sendable @escaping (Double) -> Void,
    onLoopCheck: @MainActor @Sendable @escaping (Double) -> Void,
    onPlaybackStateChange: @MainActor @Sendable @escaping (Bool) -> Void,
    onPlayerReady: @MainActor @Sendable @escaping (AVPlayer) -> Void
  ) async throws -> AVPlayerItem? {
    if let currentPlayer {
      await onPlayerReady(currentPlayer)
    }
    return nil
  }

  func play() -> Bool { true }
  func pause() {}
  func syncPauseState() {}
  func syncPlayState() {}
  func seek(to time: Double) {}
  func setVolume(_ volume: Float) async {}
  func teardown() {}
}

// MARK: - Tests

@Suite("ImportService — auto-wrap")
@MainActor
struct ImportServiceAutoWrapTests {

  @Test("auto-wraps external file at root in a folder named after the file")
  func autoWrapsFileAtRoot() throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    let sourceFile = try makeTempSourceFile(named: "chapter1.mp3")
    defer { try? FileManager.default.removeItem(at: sourceFile) }

    service.addAudioFile(from: sourceFile, currentFolder: nil)

    // Wrapper folder named after the file should exist inside the library
    let wrapperDir = libraryDir.appendingPathComponent("chapter1")
    #expect(FileManager.default.fileExists(atPath: wrapperDir.path))

    // The file should be inside the wrapper
    let copiedFile = wrapperDir.appendingPathComponent("chapter1.mp3")
    #expect(FileManager.default.fileExists(atPath: copiedFile.path))

    // ABFile should be persisted
    let files = try ctx.fetch(FetchDescriptor<ABFile>())
    #expect(files.count == 1)

    // The file's folder should be named "chapter1"
    #expect(files.first?.folder?.name == "chapter1")

    // relativePath should be nested: chapter1/chapter1.mp3
    #expect(files.first?.relativePath == "chapter1/chapter1.mp3")
  }

  @Test("imports external file directly into currentFolder — no extra wrapper")
  func importsIntoCurrentFolderNoWrap() throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    // Pre-create the subfolder in the library
    let subfolderDir = libraryDir.appendingPathComponent("mybook")
    try FileManager.default.createDirectory(at: subfolderDir, withIntermediateDirectories: true)
    let targetFolder = Folder(name: "mybook", relativePath: "mybook")
    ctx.insert(targetFolder)

    let sourceFile = try makeTempSourceFile(named: "track.mp3")
    defer { try? FileManager.default.removeItem(at: sourceFile) }

    service.addAudioFile(from: sourceFile, currentFolder: targetFolder)

    // File goes directly into mybook/
    let copiedFile = subfolderDir.appendingPathComponent("track.mp3")
    #expect(FileManager.default.fileExists(atPath: copiedFile.path))

    // No spurious "track" subfolder at library root
    let spuriousSubfolder = libraryDir.appendingPathComponent("track")
    #expect(!FileManager.default.fileExists(atPath: spuriousSubfolder.path))

    // ABFile's folder should be the target folder
    let files = try ctx.fetch(FetchDescriptor<ABFile>())
    #expect(files.first?.folder?.id == targetFolder.id)
  }

  @Test("file already inside library uses its existing path — no copy, no wrap")
  func fileAlreadyInLibraryUsesExistingPath() throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    // Place file directly inside library root (simulates already-imported file)
    let fileInsideLibrary = libraryDir.appendingPathComponent("existing.mp3")
    try Data("audio".utf8).write(to: fileInsideLibrary)

    service.addAudioFile(from: fileInsideLibrary, currentFolder: nil)

    // Only one file — no copy was made
    let items = try FileManager.default.contentsOfDirectory(atPath: libraryDir.path)
    #expect(items == ["existing.mp3"])

    // ABFile should be created with no parent folder (file is at library root)
    let files = try ctx.fetch(FetchDescriptor<ABFile>())
    #expect(files.count == 1)
    #expect(files.first?.folder == nil)
  }
}

@Suite("ImportService — callbacks")
@MainActor
struct ImportServiceCallbackTests {

  @Test("onImportCompleted fires on successful addAudioFile")
  func completedCallbackFiresOnSuccess() throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    var completedCount = 0
    service.onImportCompleted = { completedCount += 1 }

    let sourceFile = try makeTempSourceFile(named: "success.mp3")
    defer { try? FileManager.default.removeItem(at: sourceFile) }

    service.addAudioFile(from: sourceFile, currentFolder: nil)

    #expect(completedCount == 1)
  }

  @Test("onImportCompleted fires on error in addAudioFile — isImporting never gets stuck")
  func completedCallbackFiresOnError() throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    var completedCount = 0
    service.onImportCompleted = { completedCount += 1 }

    // Non-existent source file forces a copyItem error
    let missing = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).mp3")
    service.addAudioFile(from: missing, currentFolder: nil)

    #expect(service.importErrorMessage != nil)
    // onImportCompleted MUST fire even on error so the loading indicator resets
    #expect(completedCount == 1)
  }

  @Test("onImportStarted fires synchronously when handleImportResult triggers file import")
  func startedCallbackFiresOnHandleImportResult() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    var startedCount = 0
    service.onImportStarted = { startedCount += 1 }

    let sourceFile = try makeTempSourceFile(named: "start_test.mp3")
    defer { try? FileManager.default.removeItem(at: sourceFile) }

    service.handleImportResult(
      .success([sourceFile]),
      importType: .file,
      currentFolder: nil
    )

    // onImportStarted is called synchronously before the import Task
    #expect(startedCount == 1)

    // Let the Task run so the test doesn't leak work
    await Task.yield()
  }

  @Test("onImportStarted not called when import result is a failure")
  func startedCallbackNotCalledOnFailure() {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    guard let container = try? ModelContainer(
      for: ABFile.self, LoopSegment.self, PlaybackRecord.self, Folder.self, SubtitleFile.self,
        Transcription.self,
      configurations: config
    ) else { return }
    let ctx = ModelContext(container)
    let settings = LibrarySettings()
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    var startedCount = 0
    service.onImportStarted = { startedCount += 1 }

    struct FakeError: Error {}
    service.handleImportResult(.failure(FakeError()), importType: .file, currentFolder: nil)

    #expect(startedCount == 0)
    #expect(service.importErrorMessage != nil)
  }

  @Test("refreshFolder emits sync state and completion")
  func refreshFolderEmitsStateAndCompletion() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    let folderDir = libraryDir.appendingPathComponent("book")
    try FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)

    let folder = Folder(name: "book", relativePath: "book")
    ctx.insert(folder)

    var startedCount = 0
    var completedCount = 0
    var states: [(Bool, String?)] = []

    service.onImportStarted = { startedCount += 1 }
    service.onImportCompleted = { completedCount += 1 }
    service.onSyncStateChanged = { isRunning, message in
      states.append((isRunning, message))
    }

    await service.refreshFolder(folder)

    #expect(startedCount == 1)
    #expect(completedCount == 1)
    #expect(states.first?.0 == true)
    #expect(states.first?.1 == "Refreshing book...")
    #expect(states.last?.0 == false)
    #expect(states.last?.1 == nil)
  }

  @Test("refreshFolder imports new media added under existing folder")
  func refreshFolderImportsNewMediaInExistingFolder() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    let folder = Folder(name: "test", relativePath: "test")
    ctx.insert(folder)

    let folderDir = libraryDir.appendingPathComponent("test")
    try FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)

    let mediaURL = try makeTempRealMediaFile(named: "new_track.mp4")
    defer { try? FileManager.default.removeItem(at: mediaURL) }
    let destinationURL = folderDir.appendingPathComponent("new_track.mp4")
    try FileManager.default.copyItem(at: mediaURL, to: destinationURL)

    await service.refreshFolder(folder)

    let descriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { $0.relativePath == "test/new_track.mp4" }
    )
    let files = try ctx.fetch(descriptor)

    #expect(files.count == 1)
    #expect(files.first?.folder?.id == folder.id)
  }

  @Test("refreshFolder removes audio records deleted from disk")
  func refreshFolderRemovesDeletedMediaFromDatabase() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    let folder = Folder(name: "test", relativePath: "test")
    ctx.insert(folder)

    let folderDir = libraryDir.appendingPathComponent("test")
    try FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)

    let mediaA = try makeTempRealMediaFile(named: "a.mp4")
    let mediaB = try makeTempRealMediaFile(named: "b.mp4")
    defer {
      try? FileManager.default.removeItem(at: mediaA)
      try? FileManager.default.removeItem(at: mediaB)
    }

    let fileA = folderDir.appendingPathComponent("a.mp4")
    let fileB = folderDir.appendingPathComponent("b.mp4")
    try FileManager.default.copyItem(at: mediaA, to: fileA)
    try FileManager.default.copyItem(at: mediaB, to: fileB)

    await service.refreshFolder(folder)

    var allFiles = try ctx.fetch(FetchDescriptor<ABFile>())
    #expect(allFiles.count == 2)

    try FileManager.default.removeItem(at: fileB)
    await service.refreshFolder(folder)

    allFiles = try ctx.fetch(FetchDescriptor<ABFile>())
    #expect(allFiles.count == 1)
    #expect(allFiles.first?.relativePath == "test/a.mp4")
  }

  @Test("refreshLibraryRoot does not import root-level media files")
  func refreshLibraryRootDoesNotImportRootLevelMediaFiles() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    let mediaURL = libraryDir.appendingPathComponent("root_track.mp3")
    try Data("audio".utf8).write(to: mediaURL)

    await service.refreshLibraryRoot()

    let files = try ctx.fetch(FetchDescriptor<ABFile>())
    #expect(files.isEmpty)
  }

  @Test("refreshLibraryRoot does not create suffixed duplicate root folders")
  func refreshLibraryRootDoesNotCreateSuffixedDuplicateRootFolders() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    let wooDir = libraryDir.appendingPathComponent("Woo")
    try FileManager.default.createDirectory(at: wooDir, withIntermediateDirectories: true)
    let mediaURL = try makeTempRealMediaFile(named: "track.mp4")
    defer { try? FileManager.default.removeItem(at: mediaURL) }
    try FileManager.default.copyItem(at: mediaURL, to: wooDir.appendingPathComponent("track.mp4"))

    await service.refreshLibraryRoot()

    let rootEntries = try FileManager.default.contentsOfDirectory(atPath: libraryDir.path)
    #expect(rootEntries.contains("Woo"))
    #expect(!rootEntries.contains("Woo 1"))
    #expect(!rootEntries.contains("Woo1"))

    let folders = try ctx.fetch(FetchDescriptor<Folder>())
    #expect(folders.filter { $0.relativePath == "Woo" }.count == 1)
  }

}

@Suite("ImportService — managed library semantics")
@MainActor
struct ImportServiceManagedLibraryTests {

  @Test("importFolder copies external folder into library and indexes copied contents")
  func importFolderCopiesExternalIntoLibrary() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    let externalFolder = try makeTempExternalFolder(named: "book")
    defer { try? FileManager.default.removeItem(at: externalFolder) }

    let media = try makeTempRealMediaFile(named: "chapter.mp4")
    defer { try? FileManager.default.removeItem(at: media) }
    let externalMedia = externalFolder.appendingPathComponent("chapter.mp4")
    try FileManager.default.copyItem(at: media, to: externalMedia)

    var completed = false
    service.onImportCompleted = { completed = true }
    service.importFolder(from: externalFolder, currentFolder: nil)

    let didComplete = await waitUntil { completed }
    #expect(didComplete)

    let copiedFolder = libraryDir.appendingPathComponent(externalFolder.lastPathComponent)
    let copiedMedia = copiedFolder.appendingPathComponent("chapter.mp4")
    #expect(FileManager.default.fileExists(atPath: copiedFolder.path))
    #expect(FileManager.default.fileExists(atPath: copiedMedia.path))

    let folders = try ctx.fetch(FetchDescriptor<Folder>())
    #expect(folders.contains { $0.relativePath == externalFolder.lastPathComponent })

    let expectedRelativePath = "\(externalFolder.lastPathComponent)/chapter.mp4"
    let files = try ctx.fetch(FetchDescriptor<ABFile>())
    #expect(files.contains { $0.relativePath == expectedRelativePath })
  }

  @Test("importFolder does not duplicate when source folder is already in library")
  func importFolderDoesNotDuplicateInLibrarySource() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let service = ImportService(modelContext: ctx, librarySettings: settings)

    let inLibraryFolder = libraryDir.appendingPathComponent("test")
    try FileManager.default.createDirectory(at: inLibraryFolder, withIntermediateDirectories: true)

    let media = try makeTempRealMediaFile(named: "track.mp4")
    defer { try? FileManager.default.removeItem(at: media) }
    try FileManager.default.copyItem(at: media, to: inLibraryFolder.appendingPathComponent("track.mp4"))

    var completed = false
    service.onImportCompleted = { completed = true }
    service.importFolder(from: inLibraryFolder, currentFolder: nil)

    let didComplete = await waitUntil { completed }
    #expect(didComplete)

    let rootEntries = try FileManager.default.contentsOfDirectory(atPath: libraryDir.path)
    #expect(rootEntries.contains("test"))
    #expect(!rootEntries.contains("test 1"))
    #expect(!rootEntries.contains("test1"))

    let folders = try ctx.fetch(FetchDescriptor<Folder>())
    #expect(folders.filter { $0.relativePath == "test" }.count == 1)
  }

  @Test("delete to trash then refresh does not resurrect removed file")
  func deleteToTrashThenRefreshDoesNotResurrectFile() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }
    let importService = ImportService(modelContext: ctx, librarySettings: settings)

    let externalFolder = try makeTempExternalFolder(named: "novel")
    defer { try? FileManager.default.removeItem(at: externalFolder) }

    let media = try makeTempRealMediaFile(named: "chapter.mp4")
    defer { try? FileManager.default.removeItem(at: media) }
    let externalMedia = externalFolder.appendingPathComponent("chapter.mp4")
    try FileManager.default.copyItem(at: media, to: externalMedia)

    var completed = false
    importService.onImportCompleted = { completed = true }
    importService.importFolder(from: externalFolder, currentFolder: nil)
    let didComplete = await waitUntil { completed }
    #expect(didComplete)

    let folderDescriptor = FetchDescriptor<Folder>(
      predicate: #Predicate<Folder> { $0.relativePath == externalFolder.lastPathComponent }
    )
    guard let folder = try ctx.fetch(folderDescriptor).first else {
      Issue.record("Expected imported folder not found")
      return
    }

    let expectedRelativePath = "\(externalFolder.lastPathComponent)/chapter.mp4"
    let fileDescriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { $0.relativePath == expectedRelativePath }
    )
    guard let importedFile = try ctx.fetch(fileDescriptor).first else {
      Issue.record("Expected imported file not found")
      return
    }

    let playerManager = PlayerManager(librarySettings: settings, engine: SilentPlayerEngine())
    let deletionService = DeletionService(
      modelContext: ctx,
      playerManager: playerManager,
      librarySettings: settings
    )

    var selectedFile: ABFile? = importedFile
    deletionService.deleteAudioFile(
      importedFile,
      deleteFromDisk: true,
      updateSelection: true,
      checkPlayback: true,
      selectedFile: &selectedFile
    )

    let copiedMedia = libraryDir
      .appendingPathComponent(externalFolder.lastPathComponent)
      .appendingPathComponent("chapter.mp4")
    #expect(!FileManager.default.fileExists(atPath: copiedMedia.path))

    await importService.refreshFolder(folder)

    let filesAfterRefresh = try ctx.fetch(fileDescriptor)
    #expect(filesAfterRefresh.isEmpty)
  }

  @Test("delete and refresh works even when bookmarkData is empty")
  func deleteAndRefreshWorksWithEmptyBookmarkData() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let folder = Folder(name: "book", relativePath: "book")
    ctx.insert(folder)

    let bookDir = libraryDir.appendingPathComponent("book")
    try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

    let mediaURL = bookDir.appendingPathComponent("chapter.mp3")
    try Data("audio".utf8).write(to: mediaURL)

    let file = ABFile(
      displayName: "chapter.mp3",
      bookmarkData: Data(),
      folder: folder,
      relativePath: "book/chapter.mp3"
    )
    ctx.insert(file)

    let importService = ImportService(modelContext: ctx, librarySettings: settings)
    let playerManager = PlayerManager(librarySettings: settings, engine: SilentPlayerEngine())
    let deletionService = DeletionService(
      modelContext: ctx,
      playerManager: playerManager,
      librarySettings: settings
    )

    var selected: ABFile? = file
    deletionService.deleteAudioFile(
      file,
      deleteFromDisk: true,
      updateSelection: true,
      checkPlayback: true,
      selectedFile: &selected
    )

    #expect(!FileManager.default.fileExists(atPath: mediaURL.path))

    await importService.refreshFolder(folder)

    let remaining = try ctx.fetch(FetchDescriptor<ABFile>())
    #expect(remaining.isEmpty)
  }

  @Test("refresh clears stale player and queue references for removed files")
  func refreshClearsStalePlayerAndQueueReferencesForRemovedFiles() async throws {
    let (_, ctx, settings, playerManager, viewModel, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let service = ImportService(modelContext: ctx, librarySettings: settings)

    let folder = Folder(name: "book", relativePath: "book")
    ctx.insert(folder)

    let bookDir = libraryDir.appendingPathComponent("book")
    try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

    let mediaA = bookDir.appendingPathComponent("a.mp4")
    let mediaB = bookDir.appendingPathComponent("b.mp4")
    try Data("a".utf8).write(to: mediaA)
    try Data("b".utf8).write(to: mediaB)

    await service.refreshFolder(folder)

    let files = try ctx.fetch(FetchDescriptor<ABFile>()).filter { $0.folder?.id == folder.id }
    #expect(files.count == 2)

    guard
      let fileA = files.first(where: { $0.relativePath == "book/a.mp4" }),
      let fileB = files.first(where: { $0.relativePath == "book/b.mp4" })
    else {
      Issue.record("Expected both imported files")
      return
    }

    viewModel.currentFolder = folder
    viewModel.selectedFile = fileB
    playerManager.currentFile = fileB
    playerManager.playbackQueue.updateQueue([fileA, fileB])
    playerManager.playbackQueue.setCurrentFile(fileB)

    try FileManager.default.removeItem(at: mediaB)

    await viewModel.refreshCurrentFolder()

    #expect(viewModel.selectedFile?.id == nil)
    #expect(playerManager.currentFile?.id == nil)
    #expect(playerManager.playbackQueue.queuedFiles.map(\.id) == [fileA.id])
    #expect(playerManager.playbackQueue.currentFile == nil)
  }

  @Test("library switch clears stale selection and transient row states")
  func librarySwitchClearsSelectionAndTransientStates() async throws {
    let (_, ctx, settings, playerManager, viewModel, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let oldRoot = libraryDir.appendingPathComponent("old-lib")
    let oldBook = oldRoot.appendingPathComponent("book")
    try FileManager.default.createDirectory(at: oldBook, withIntermediateDirectories: true)
    let oldMedia = oldBook.appendingPathComponent("old.mp4")
    try Data("old".utf8).write(to: oldMedia)

    let newRoot = libraryDir.appendingPathComponent("new-lib")
    try FileManager.default.createDirectory(at: newRoot, withIntermediateDirectories: true)

    settings.libraryPath = oldRoot.path

    let oldFolder = Folder(name: "book", relativePath: "book")
    let staleFile = ABFile(
      displayName: "old.mp4",
      bookmarkData: Data(),
      folder: oldFolder,
      relativePath: "book/old.mp4"
    )
    ctx.insert(oldFolder)
    ctx.insert(staleFile)

    viewModel.navigationPath = [oldFolder]
    viewModel.currentFolder = oldFolder
    viewModel.selection = .audioFile(staleFile)
    viewModel.selectedFile = staleFile
    viewModel.hovering = .audioFile(staleFile)
    viewModel.pressing = .audioFile(staleFile)
    viewModel.selectionBeforePress = .audioFile(staleFile)
    viewModel.requestDelete(.audioFile(staleFile))

    playerManager.currentFile = staleFile
    playerManager.playbackQueue.updateQueue([staleFile])
    playerManager.playbackQueue.setCurrentFile(staleFile)

    settings.libraryPath = newRoot.path
    await viewModel.handleLibraryPathChanged()

    #expect(viewModel.selectedFile == nil)
    #expect(viewModel.selection == nil)
    #expect(viewModel.hovering == nil)
    #expect(viewModel.pressing == nil)
    #expect(viewModel.selectionBeforePress == nil)
    #expect(viewModel.deleteTarget == nil)
    #expect(viewModel.showDeleteConfirmation == false)
    #expect(viewModel.currentFolder == nil)
    #expect(viewModel.navigationPath.isEmpty)

    #expect(playerManager.currentFile == nil)
    #expect(playerManager.playbackQueue.queuedFiles.isEmpty)
    #expect(playerManager.playbackQueue.currentFile == nil)
  }

  @Test("delete folder clears player and queue when selected file is inside")
  func deleteFolderClearsPlayerAndQueueWhenSelectionInside() async throws {
    let (_, ctx, _, playerManager, viewModel, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let root = Folder(name: "book", relativePath: "book")
    let keep = ABFile(
      displayName: "keep.mp4",
      bookmarkData: Data(),
      relativePath: "keep.mp4"
    )
    let doomed = ABFile(
      displayName: "doomed.mp4",
      bookmarkData: Data(),
      folder: root,
      relativePath: "book/doomed.mp4"
    )
    ctx.insert(root)
    ctx.insert(keep)
    ctx.insert(doomed)

    viewModel.currentFolder = root
    viewModel.navigationPath = [root]
    viewModel.selection = .audioFile(doomed)
    viewModel.selectedFile = doomed
    viewModel.hovering = .audioFile(doomed)
    viewModel.requestDelete(.folder(root))

    playerManager.currentFile = doomed
    playerManager.playbackQueue.updateQueue([keep, doomed])
    playerManager.playbackQueue.setCurrentFile(doomed)

    viewModel.deleteFolder(root, deleteFromDisk: false)

    #expect(viewModel.selectedFile == nil)
    #expect(viewModel.selection == nil)
    #expect(viewModel.hovering == nil)
    #expect(viewModel.deleteTarget == nil)
    #expect(viewModel.showDeleteConfirmation == false)
    #expect(viewModel.currentFolder == nil)
    #expect(viewModel.navigationPath.isEmpty)

    #expect(playerManager.currentFile == nil)
    #expect(playerManager.playbackQueue.queuedFiles.map(\.id) == [keep.id])
    #expect(playerManager.playbackQueue.currentFile == nil)
  }

  @Test("refreshLibraryRoot prunes stale root folders from previous library")
  func refreshLibraryRootPrunesStaleRootFolders() async throws {
    let (_, ctx, settings, _, _, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let oldRoot = libraryDir.appendingPathComponent("old-lib")
    let oldBook = oldRoot.appendingPathComponent("book")
    try FileManager.default.createDirectory(at: oldBook, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: oldBook.appendingPathComponent("old.mp4"))

    let newRoot = libraryDir.appendingPathComponent("new-lib")
    let newShelf = newRoot.appendingPathComponent("shelf")
    try FileManager.default.createDirectory(at: newShelf, withIntermediateDirectories: true)
    try Data("new".utf8).write(to: newShelf.appendingPathComponent("new.mp4"))

    settings.libraryPath = oldRoot.path
    let service = ImportService(modelContext: ctx, librarySettings: settings)
    await service.refreshLibraryRoot()

    var rootFolders = try ctx.fetch(
      FetchDescriptor<Folder>(predicate: #Predicate<Folder> { $0.parent == nil })
    )
    #expect(rootFolders.map(\.relativePath).contains("book"))

    settings.libraryPath = newRoot.path
    await service.refreshLibraryRoot()

    rootFolders = try ctx.fetch(
      FetchDescriptor<Folder>(predicate: #Predicate<Folder> { $0.parent == nil })
    )
    let rootPaths = Set(rootFolders.map(\.relativePath))
    #expect(rootPaths.contains("shelf"))
    #expect(rootPaths.contains("book") == false)
  }

  @Test("switch library then delete previously selected stale folder is safe")
  func switchLibraryThenDeletePreviouslySelectedStaleFolderIsSafe() async throws {
    let (_, ctx, settings, playerManager, viewModel, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let oldRoot = libraryDir.appendingPathComponent("old-lib")
    let oldBook = oldRoot.appendingPathComponent("book")
    try FileManager.default.createDirectory(at: oldBook, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: oldBook.appendingPathComponent("old.mp4"))

    let newRoot = libraryDir.appendingPathComponent("new-lib")
    let newShelf = newRoot.appendingPathComponent("shelf")
    try FileManager.default.createDirectory(at: newShelf, withIntermediateDirectories: true)
    try Data("new".utf8).write(to: newShelf.appendingPathComponent("new.mp4"))

    let oldFolder = Folder(name: "book", relativePath: "book")
    let staleFile = ABFile(
      displayName: "old.mp4",
      bookmarkData: Data(),
      folder: oldFolder,
      relativePath: "book/old.mp4"
    )
    ctx.insert(oldFolder)
    ctx.insert(staleFile)

    viewModel.navigationPath = [oldFolder]
    viewModel.currentFolder = oldFolder
    viewModel.selection = .audioFile(staleFile)
    viewModel.selectedFile = staleFile
    playerManager.currentFile = staleFile
    playerManager.playbackQueue.updateQueue([staleFile])
    playerManager.playbackQueue.setCurrentFile(staleFile)

    settings.libraryPath = newRoot.path
    await viewModel.handleLibraryPathChanged()

    // Simulate stale delete target kept by UI timing/race and ensure deletion path remains safe.
    viewModel.deleteFolder(oldFolder, deleteFromDisk: false)

    let allFolders = try ctx.fetch(FetchDescriptor<Folder>())
    #expect(allFolders.contains(where: { $0.relativePath == "book" }) == false)
    #expect(viewModel.selectedFile == nil)
    #expect(viewModel.selection == nil)
    #expect(playerManager.currentFile == nil)
    #expect(playerManager.playbackQueue.currentFile == nil)
  }
}

@Suite("Recently Played")
@MainActor
struct RecentlyPlayedTests {
  @Test("current folder recently played includes the most recent completed file")
  func currentFolderRecentlyPlayedIncludesMostRecentCompletedFile() async throws {
    let (_, ctx, settings, _, viewModel, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let folder = Folder(name: "Season 1", relativePath: "series/season1")
    ctx.insert(folder)
    try FileManager.default.createDirectory(
      at: libraryDir.appendingPathComponent("series/season1"),
      withIntermediateDirectories: true
    )

    let now = Date()

    let completed = ABFile(
      displayName: "ep01.mp4",
      bookmarkData: Data(),
      folder: folder,
      relativePath: "series/season1/ep01.mp4"
    )
    completed.cachedDuration = 100
    completed.currentPlaybackPosition = 95
    completed.playbackRecord?.lastPlayedAt = now

    let older = ABFile(
      displayName: "ep02.mp4",
      bookmarkData: Data(),
      folder: folder,
      relativePath: "series/season1/ep02.mp4"
    )
    older.cachedDuration = 100
    older.currentPlaybackPosition = 40
    older.playbackRecord?.lastPlayedAt = now.addingTimeInterval(-600)

    let latest = ABFile(
      displayName: "ep03.mp4",
      bookmarkData: Data(),
      folder: folder,
      relativePath: "series/season1/ep03.mp4"
    )
    latest.cachedDuration = 100
    latest.currentPlaybackPosition = 12
    latest.playbackRecord?.lastPlayedAt = now.addingTimeInterval(-120)

    ctx.insert(completed)
    ctx.insert(older)
    ctx.insert(latest)

    try Data("1".utf8).write(to: settings.mediaFileURL(for: completed))
    try Data("2".utf8).write(to: settings.mediaFileURL(for: older))
    try Data("3".utf8).write(to: settings.mediaFileURL(for: latest))

    viewModel.currentFolder = folder
    await viewModel.refreshCurrentFolderRecentlyPlayed()

    let item = viewModel.recentlyPlayedItemInCurrentFolder
    #expect(item != nil)
    #expect(item?.file.id == completed.id)
  }

  @Test("current folder recently played is empty without playback history")
  func currentFolderRecentlyPlayedIsEmptyWithoutPlaybackHistory() async throws {
    let (_, ctx, settings, _, viewModel, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let folder = Folder(name: "Season 2", relativePath: "series/season2")
    ctx.insert(folder)
    try FileManager.default.createDirectory(
      at: libraryDir.appendingPathComponent("series/season2"),
      withIntermediateDirectories: true
    )

    let file = ABFile(
      displayName: "ep04.mp4",
      bookmarkData: Data(),
      folder: folder,
      relativePath: "series/season2/ep04.mp4"
    )
    file.cachedDuration = 200
    file.currentPlaybackPosition = 190
    ctx.insert(file)

    try Data("4".utf8).write(to: settings.mediaFileURL(for: file))

    viewModel.currentFolder = folder
    await viewModel.refreshCurrentFolderRecentlyPlayed()

    #expect(viewModel.recentlyPlayedItemInCurrentFolder == nil)
  }

  @Test("global recently played groups by directory and filters invalid entries")
  func globalRecentlyPlayedGroupsByDirectoryAndFiltersInvalidEntries() async throws {
    let (_, ctx, settings, _, viewModel, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let now = Date()
    let season1 = Folder(name: "Season 1", relativePath: "series/season1")
    let season2 = Folder(name: "Season 2", relativePath: "series/season2")
    ctx.insert(season1)
    ctx.insert(season2)
    try FileManager.default.createDirectory(
      at: libraryDir.appendingPathComponent("series/season1"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: libraryDir.appendingPathComponent("series/season2"),
      withIntermediateDirectories: true
    )

    let season1Older = ABFile(
      displayName: "older.mp4",
      bookmarkData: Data(),
      folder: season1,
      relativePath: "series/season1/older.mp4"
    )
    season1Older.cachedDuration = 100
    season1Older.currentPlaybackPosition = 30
    season1Older.playbackRecord?.lastPlayedAt = now.addingTimeInterval(-1200)

    let season1Recent = ABFile(
      displayName: "recent.mp4",
      bookmarkData: Data(),
      folder: season1,
      relativePath: "series/season1/recent.mp4"
    )
    season1Recent.cachedDuration = 100
    season1Recent.currentPlaybackPosition = 20
    season1Recent.playbackRecord?.lastPlayedAt = now.addingTimeInterval(-300)

    let season2Completed = ABFile(
      displayName: "completed.mp4",
      bookmarkData: Data(),
      folder: season2,
      relativePath: "series/season2/completed.mp4"
    )
    season2Completed.cachedDuration = 100
    season2Completed.currentPlaybackPosition = 99
    season2Completed.playbackRecord?.lastPlayedAt = now

    let rootNoProgress = ABFile(
      displayName: "no-progress.mp4",
      bookmarkData: Data(),
      relativePath: "no-progress.mp4"
    )
    rootNoProgress.cachedDuration = 100
    rootNoProgress.currentPlaybackPosition = 0
    rootNoProgress.playbackRecord?.lastPlayedAt = now.addingTimeInterval(-100)

    let missing = ABFile(
      displayName: "missing.mp4",
      bookmarkData: Data(),
      relativePath: "missing.mp4"
    )
    missing.cachedDuration = 100
    missing.currentPlaybackPosition = 10
    missing.playbackRecord?.lastPlayedAt = now.addingTimeInterval(-50)

    ctx.insert(season1Older)
    ctx.insert(season1Recent)
    ctx.insert(season2Completed)
    ctx.insert(rootNoProgress)
    ctx.insert(missing)

    try Data("older".utf8).write(to: settings.mediaFileURL(for: season1Older))
    try Data("recent".utf8).write(to: settings.mediaFileURL(for: season1Recent))
    try Data("completed".utf8).write(to: settings.mediaFileURL(for: season2Completed))
    try Data("no-progress".utf8).write(to: settings.mediaFileURL(for: rootNoProgress))

    await viewModel.refreshGlobalRecentlyPlayed(limit: 3)
    let items = viewModel.globalRecentlyPlayedItems

    #expect(items.count == 3)
    #expect(items.map(\.file.id) == [season2Completed.id, rootNoProgress.id, season1Recent.id])
    #expect(items.contains(where: { $0.file.id == season1Older.id }) == false)
  }

  @Test("global recently played groups root-level files into one library bucket")
  func globalRecentlyPlayedGroupsRootLevelFilesIntoOneLibraryBucket() async throws {
    let (_, ctx, settings, _, viewModel, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let now = Date()

    let older = ABFile(
      displayName: "older.mp4",
      bookmarkData: Data(),
      relativePath: "older.mp4"
    )
    older.cachedDuration = 100
    older.currentPlaybackPosition = 25
    older.playbackRecord?.lastPlayedAt = now.addingTimeInterval(-600)

    let newer = ABFile(
      displayName: "newer.mp4",
      bookmarkData: Data(),
      relativePath: "newer.mp4"
    )
    newer.cachedDuration = 100
    newer.currentPlaybackPosition = 0
    newer.playbackRecord?.lastPlayedAt = now

    ctx.insert(older)
    ctx.insert(newer)

    try Data("older".utf8).write(to: settings.mediaFileURL(for: older))
    try Data("newer".utf8).write(to: settings.mediaFileURL(for: newer))

    await viewModel.refreshGlobalRecentlyPlayed(limit: 8)

    #expect(viewModel.globalRecentlyPlayedItems.count == 1)
    #expect(viewModel.globalRecentlyPlayedItems.first?.file.id == newer.id)
    #expect(viewModel.globalRecentlyPlayedItems.first?.folderPathSummary == "Library")
  }

  @Test("latest global recently played refresh wins")
  func latestGlobalRecentlyPlayedRefreshWins() async throws {
    let (_, ctx, settings, _, viewModel, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let now = Date()

    let existing = ABFile(
      displayName: "existing.mp4",
      bookmarkData: Data(),
      relativePath: "existing.mp4"
    )
    existing.cachedDuration = 100
    existing.currentPlaybackPosition = 30
    existing.playbackRecord?.lastPlayedAt = now
    ctx.insert(existing)
    try Data("existing".utf8).write(to: settings.mediaFileURL(for: existing))

    for index in 0..<1500 {
      let missing = ABFile(
        displayName: "missing-\(index).mp4",
        bookmarkData: Data(),
        relativePath: "missing-\(index).mp4"
      )
      missing.cachedDuration = 100
      missing.currentPlaybackPosition = 20
      missing.playbackRecord?.lastPlayedAt = now.addingTimeInterval(-Double(index + 1))
      ctx.insert(missing)
    }

    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        await viewModel.refreshGlobalRecentlyPlayed(limit: 2000)
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 5_000_000)
        await viewModel.refreshGlobalRecentlyPlayed(limit: 1)
      }
      await group.waitForAll()
    }

    #expect(viewModel.globalRecentlyPlayedItems.count == 1)
    #expect(viewModel.globalRecentlyPlayedItems.first?.file.id == existing.id)
  }

  @Test("file ordering is unchanged when playback history exists")
  func fileOrderingIsUnchangedWhenPlaybackHistoryExists() throws {
    let (_, ctx, settings, _, viewModel, libraryDir) = try makeFolderNavigationViewModelTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let folder = Folder(name: "Season 3", relativePath: "series/season3")
    ctx.insert(folder)
    try FileManager.default.createDirectory(
      at: libraryDir.appendingPathComponent("series/season3"),
      withIntermediateDirectories: true
    )

    let zed = ABFile(
      displayName: "Zed.mp4",
      bookmarkData: Data(),
      folder: folder,
      relativePath: "series/season3/Zed.mp4"
    )
    zed.cachedDuration = 100
    zed.currentPlaybackPosition = 90
    zed.playbackRecord?.lastPlayedAt = Date()

    let alpha = ABFile(
      displayName: "Alpha.mp4",
      bookmarkData: Data(),
      folder: folder,
      relativePath: "series/season3/Alpha.mp4"
    )
    alpha.cachedDuration = 100
    alpha.currentPlaybackPosition = 5
    alpha.playbackRecord?.lastPlayedAt = Date().addingTimeInterval(-300)

    ctx.insert(zed)
    ctx.insert(alpha)
    try Data("zed".utf8).write(to: settings.mediaFileURL(for: zed))
    try Data("alpha".utf8).write(to: settings.mediaFileURL(for: alpha))

    viewModel.currentFolder = folder
    viewModel.sortOrder = .nameAZ

    #expect(viewModel.currentAudioFiles().map(\.displayName) == ["Alpha", "Zed"])
  }

  @Test("playback progress requires positive position and valid duration")
  func playbackProgressRequiresPositivePositionAndValidDuration() {
    let file = ABFile(
      displayName: "episode.mp4",
      bookmarkData: Data(),
      relativePath: "episode.mp4"
    )

    #expect(file.playbackProgress == nil)

    file.currentPlaybackPosition = 15
    #expect(file.playbackProgress == nil)

    file.cachedDuration = 0
    #expect(file.playbackProgress == nil)

    file.cachedDuration = 60
    #expect(file.playbackProgress == 0.25)
  }

  @Test("play recently played restores navigation and auto-plays")
  func playRecentlyPlayedRestoresNavigationAndAutoPlays() async throws {
    let (_, ctx, settings, libraryDir) = try makeImportTestContext()
    defer { try? FileManager.default.removeItem(at: libraryDir) }

    let playerManager = PlayerManager(librarySettings: settings, engine: AlwaysPlayEngine())
    let viewModel = FolderNavigationViewModel(
      modelContext: ctx,
      playerManager: playerManager,
      librarySettings: settings
    )
    viewModel.sortOrder = .nameAZ

    let parentFolder = Folder(name: "Series", relativePath: "series")
    let seasonFolder = Folder(name: "Season 1", relativePath: "series/season1", parent: parentFolder)
    ctx.insert(parentFolder)
    ctx.insert(seasonFolder)

    let folderURL = libraryDir.appendingPathComponent("series/season1")
    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

    let fileA = ABFile(
      displayName: "01.mp4",
      bookmarkData: Data(),
      folder: seasonFolder,
      relativePath: "series/season1/01.mp4"
    )
    fileA.cachedDuration = 100

    let fileB = ABFile(
      displayName: "02.mp4",
      bookmarkData: Data(),
      folder: seasonFolder,
      relativePath: "series/season1/02.mp4"
    )
    fileB.cachedDuration = 100
    fileB.currentPlaybackPosition = 42
    fileB.playbackRecord?.lastPlayedAt = Date()

    ctx.insert(fileA)
    ctx.insert(fileB)

    try Data("a".utf8).write(to: settings.mediaFileURL(for: fileA))
    try Data("b".utf8).write(to: settings.mediaFileURL(for: fileB))

    await viewModel.playRecentlyPlayed(fileB)

    #expect(viewModel.currentFolder?.id == seasonFolder.id)
    #expect(viewModel.navigationPath.map(\.id) == [parentFolder.id, seasonFolder.id])
    #expect(viewModel.selectedFile?.id == fileB.id)

    #expect(playerManager.currentFile?.id == fileB.id)
    #expect(playerManager.isPlaying)
    #expect(playerManager.playbackQueue.sourceFolderID == seasonFolder.id)
    #expect(playerManager.playbackQueue.queuedFiles.map(\.id) == [fileA.id, fileB.id])
    #expect(playerManager.playbackQueue.currentFile?.id == fileB.id)
  }
}

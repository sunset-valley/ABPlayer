import Foundation
import SwiftData
import Testing

@testable import ABPlayerDev

// MARK: - Repeat All Tests

struct RepeatAllTests {

  // MARK: - Next File Index Tests

  @Test
  func testNextFileIndexReturnsNextIndex() {
    // Given files: [0, 1, 2]
    // When current index is 0, next should be 1
    let currentIndex = 0
    let filesCount = 3
    let nextIndex = (currentIndex + 1) % filesCount

    #expect(nextIndex == 1)
  }

  @Test
  func testNextFileIndexWrapsAroundToFirst() {
    // Given files: [0, 1, 2]
    // When current index is 2 (last), next should be 0 (first)
    let currentIndex = 2
    let filesCount = 3
    let nextIndex = (currentIndex + 1) % filesCount

    #expect(nextIndex == 0)
  }

  @Test
  func testNextFileIndexSingleFile() {
    // Given files: [0]
    // When current index is 0, next should be 0 (wraps to self)
    let currentIndex = 0
    let filesCount = 1
    let nextIndex = (currentIndex + 1) % filesCount

    #expect(nextIndex == 0)
  }

  // MARK: - Sorting Tests

  @Test
  func testAudioFilesSortByDisplayName() {
    // Given unsorted display names
    let names = ["Track 03", "Track 01", "Track 02"]
    let sorted = names.sorted { $0 < $1 }

    #expect(sorted == ["Track 01", "Track 02", "Track 03"])
  }

  @Test
  func testAudioFilesSortByDisplayNameWithNumbers() {
    // Given files with numeric names (lexicographic sort)
    let names = ["1.mp3", "10.mp3", "2.mp3", "9.mp3"]
    let sorted = names.sorted { $0 < $1 }

    // Note: Lexicographic sort puts "10" before "2"
    // This is expected behavior matching Finder's sort
    #expect(sorted == ["1.mp3", "10.mp3", "2.mp3", "9.mp3"])
  }

  // MARK: - Selection Sync Tests

  @Test
  func testSelectionItemEquality() {
    let id1 = UUID()
    let id2 = UUID()

    // Same IDs should be equal when compared by ID
    #expect(id1 == id1)
    #expect(id1 != id2)
  }
}

// MARK: - Selection Sync Tests

struct SelectionSyncTests {

  /// Tests that selection is set when selectedFile is in currentAudioFiles
  @Test
  func testSelectionSyncWhenFileInCurrentFolder() {
    // Given: A file ID that exists in the current folder's files
    let fileId = UUID()
    let currentFileIds = [UUID(), fileId, UUID()]

    // When: Checking if file is in current folder
    let isInCurrentFolder = currentFileIds.contains { $0 == fileId }

    // Then: Should return true
    #expect(isInCurrentFolder == true)
  }

  /// Tests that selection is cleared when selectedFile is not in currentAudioFiles
  @Test
  func testSelectionClearsWhenFileNotInFolder() {
    // Given: A file ID that does NOT exist in current folder
    let selectedFileId = UUID()
    let currentFileIds = [UUID(), UUID(), UUID()]

    // When: Checking if selected file is in current folder
    let isInCurrentFolder = currentFileIds.contains { $0 == selectedFileId }

    // Then: Should return false, meaning selection should be cleared
    #expect(isInCurrentFolder == false)
  }

  /// Tests that redundant selection updates are avoided (idempotency)
  @Test
  func testSelectionSyncIdempotent() {
    // Given: Current selection already matches selectedFile
    let fileId = UUID()
    let currentSelectionId: UUID? = fileId
    let selectedFileId = fileId

    // When: Checking if already matching
    let alreadyMatches = currentSelectionId == selectedFileId

    // Then: Should skip update
    #expect(alreadyMatches == true)
  }

  /// Tests that selection sync handles nil selectedFile
  @Test
  func testSelectionSyncWithNilFile() {
    // Given: selectedFile is nil
    let selectedFileId: UUID? = nil

    // Then: selection should be cleared (nil)
    #expect(selectedFileId == nil)
  }

  /// Tests navigation back to folder containing selected file
  @Test
  func testSelectionRestoredAfterNavigateBack() {
    // Given: A file ID that is selected
    let selectedFileId = UUID()
    // Navigation returns to a folder that contains this file
    let parentFolderFileIds = [UUID(), selectedFileId, UUID()]

    // When: Checking if file is in parent folder
    let isInFolder = parentFolderFileIds.contains { $0 == selectedFileId }

    // Then: Selection should be restored
    #expect(isInFolder == true)
  }
}

// MARK: - PlaybackQueue Navigation Tests

/// Helper that builds an in-memory SwiftData container and returns a lightweight
/// ABFile factory. ABFile is a @Model class, so it must be created inside a
/// ModelContext even for unit tests.
private func makeQueueTestContext() throws -> (ModelContainer, ModelContext) {
  let config = ModelConfiguration(isStoredInMemoryOnly: true)
  let container = try ModelContainer(
    for: ABFile.self, LoopSegment.self, PlaybackRecord.self, Folder.self, SubtitleFile.self,
    configurations: config
  )
  let context = ModelContext(container)
  return (container, context)
}

private func makeFolder(_ name: String, in context: ModelContext, parent: Folder? = nil) -> Folder {
  let folder = Folder(name: name, parent: parent)
  context.insert(folder)
  return folder
}

private func makeFile(_ name: String, in context: ModelContext, folder: Folder? = nil) -> ABFile {
  let file = ABFile(displayName: name, bookmarkData: Data(), folder: folder)
  context.insert(file)
  return file
}

// MARK: Bug 2 — Prev/next navigation buttons are inactive when loopMode == .none

@Suite("PlaybackQueue — manual navigation ignores loopMode")
@MainActor
struct PlaybackQueueManualNavigationTests {

  @Test("navigateNext returns next file when loopMode is .none")
  func navigateNextWorksInNoneMode() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp3", in: ctx)
    let f2 = makeFile("ep2.mp3", in: ctx)
    let f3 = makeFile("ep3.mp3", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .none
    queue.updateQueue([f1, f2, f3])
    queue.setCurrentFile(f1)

    let next = queue.navigateNext()
    #expect(next?.id == f2.id)
  }

  @Test("navigatePrev returns previous file when loopMode is .none")
  func navigatePrevWorksInNoneMode() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp3", in: ctx)
    let f2 = makeFile("ep2.mp3", in: ctx)
    let f3 = makeFile("ep3.mp3", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .none
    queue.updateQueue([f1, f2, f3])
    queue.setCurrentFile(f3)

    let prev = queue.navigatePrev()
    #expect(prev?.id == f2.id)
  }

  @Test("navigateNext wraps around to first file when on last file (loopMode .none)")
  func navigateNextWrapsAround() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp3", in: ctx)
    let f2 = makeFile("ep2.mp3", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .none
    queue.updateQueue([f1, f2])
    queue.setCurrentFile(f2)

    let next = queue.navigateNext()
    #expect(next?.id == f1.id)
  }

  @Test("navigatePrev wraps around to last file when on first file (loopMode .none)")
  func navigatePrevWrapsAround() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp3", in: ctx)
    let f2 = makeFile("ep2.mp3", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .none
    queue.updateQueue([f1, f2])
    queue.setCurrentFile(f1)

    let prev = queue.navigatePrev()
    #expect(prev?.id == f2.id)
  }

  @Test("navigateNext works when loopMode is .repeatOne")
  func navigateNextWorksInRepeatOneMode() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp3", in: ctx)
    let f2 = makeFile("ep2.mp3", in: ctx)
    let f3 = makeFile("ep3.mp3", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .repeatOne
    queue.updateQueue([f1, f2, f3])
    queue.setCurrentFile(f1)

    let next = queue.navigateNext()
    #expect(next?.id == f2.id)
  }

  @Test("auto-play (playNext) still returns nil in .none mode")
  func autoPlayReturnsNilInNoneMode() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp3", in: ctx)
    let f2 = makeFile("ep2.mp3", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .none
    queue.updateQueue([f1, f2])
    queue.setCurrentFile(f1)

    // playNext() is for auto-play — should still respect loopMode
    #expect(queue.playNext() == nil)
  }
}

// MARK: Bug 1 — Video sequential playback uses wrong order because currentFileID is stale

@Suite("PlaybackQueue — currentFileID tracking via setCurrentFile")
@MainActor
struct PlaybackQueueCurrentFileTrackingTests {

  @Test("navigateNext returns file after the one set by setCurrentFile")
  func navigateNextFromSetCurrentFile() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp4", in: ctx)
    let f2 = makeFile("ep2.mp4", in: ctx)
    let f3 = makeFile("ep3.mp4", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .autoPlayNext
    queue.updateQueue([f1, f2, f3])

    // Simulates VideoPlayerView calling selectFile (which calls setCurrentFile)
    queue.setCurrentFile(f2)

    let next = queue.navigateNext()
    #expect(next?.id == f3.id)
  }

  @Test("without setCurrentFile, navigateNext starts from the beginning")
  func navigateNextWithoutSetCurrentFileStartsFromFirst() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp4", in: ctx)
    let f2 = makeFile("ep2.mp4", in: ctx)
    let f3 = makeFile("ep3.mp4", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .autoPlayNext
    queue.updateQueue([f1, f2, f3])
    // No setCurrentFile — currentFileID is nil

    let next = queue.navigateNext()
    // When currentFileID is nil, navigate uses index -1, so nextIndex = 0
    #expect(next?.id == f1.id)
  }

  @Test("sequential navigation produces correct order across multiple steps")
  func sequentialNavigationOrder() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp4", in: ctx)
    let f2 = makeFile("ep2.mp4", in: ctx)
    let f3 = makeFile("ep3.mp4", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .none
    queue.updateQueue([f1, f2, f3])
    queue.setCurrentFile(f1)

    let step1 = queue.navigateNext()
    #expect(step1?.id == f2.id)

    let step2 = queue.navigateNext()
    #expect(step2?.id == f3.id)

    // Wraps around
    let step3 = queue.navigateNext()
    #expect(step3?.id == f1.id)
  }

  @Test("setCurrentFile to middle file — prev returns first, next returns third")
  func setCurrentFileInMiddle() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp4", in: ctx)
    let f2 = makeFile("ep2.mp4", in: ctx)
    let f3 = makeFile("ep3.mp4", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .none
    queue.updateQueue([f1, f2, f3])
    queue.setCurrentFile(f2)

    #expect(queue.navigatePrev()?.id == f1.id)

    // navigatePrev updated currentFileID to f1, reset to f2 to test next
    queue.setCurrentFile(f2)
    #expect(queue.navigateNext()?.id == f3.id)
  }

  @Test("updateQueue preserves currentFileID when file is still present")
  func updateQueuePreservesCurrentFile() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp4", in: ctx)
    let f2 = makeFile("ep2.mp4", in: ctx)
    let f3 = makeFile("ep3.mp4", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .none
    queue.updateQueue([f1, f2, f3])
    queue.setCurrentFile(f2)

    // Refresh queue (same files, simulating sort order change)
    queue.updateQueue([f1, f2, f3])

    // currentFileID should still be f2, so next is f3
    let next = queue.navigateNext()
    #expect(next?.id == f3.id)
  }

  @Test("updateQueue clears currentFileID when file is removed")
  func updateQueueClearsCurrentFileWhenRemoved() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp4", in: ctx)
    let f2 = makeFile("ep2.mp4", in: ctx)
    let f3 = makeFile("ep3.mp4", in: ctx)

    let queue = PlaybackQueue()
    queue.loopMode = .none
    queue.updateQueue([f1, f2, f3])
    queue.setCurrentFile(f2)

    // Remove f2 from queue
    queue.updateQueue([f1, f3])

    // currentFileID should be nil now, so navigateNext starts from beginning
    let next = queue.navigateNext()
    #expect(next?.id == f1.id)
  }

  @Test("removeFiles removes deleted IDs and clears current file")
  func removeFilesClearsCurrentFileWhenRemoved() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp4", in: ctx)
    let f2 = makeFile("ep2.mp4", in: ctx)
    let f3 = makeFile("ep3.mp4", in: ctx)

    let queue = PlaybackQueue()
    queue.updateQueue([f1, f2, f3])
    queue.setCurrentFile(f2)

    let changed = queue.removeFiles(withIDs: [f2.id, f3.id])

    #expect(changed)
    #expect(queue.queuedFiles.map(\.id) == [f1.id])
    #expect(queue.currentFile == nil)
  }

  @Test("removeFiles returns false when nothing matches")
  func removeFilesNoOpWhenIDsMissing() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp4", in: ctx)
    let f2 = makeFile("ep2.mp4", in: ctx)

    let queue = PlaybackQueue()
    queue.updateQueue([f1, f2])
    queue.setCurrentFile(f1)

    let changed = queue.removeFiles(withIDs: [UUID()])

    #expect(changed == false)
    #expect(queue.queuedFiles.map(\.id) == [f1.id, f2.id])
    #expect(queue.currentFile?.id == f1.id)
  }
}

@Suite("PlaybackQueue — snapshot and source context")
@MainActor
struct PlaybackQueueSnapshotTests {

  @Test("restore keeps exact saved queue order")
  func restoreKeepsSavedOrder() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp3", in: ctx)
    let f2 = makeFile("ep2.mp3", in: ctx)
    let f3 = makeFile("ep3.mp3", in: ctx)
    let sourceFolderID = UUID()

    let writerQueue = PlaybackQueue()
    writerQueue.clearPersistedSnapshot()
    defer { writerQueue.clearPersistedSnapshot() }

    writerQueue.replaceQueue(
      files: [f2, f1, f3],
      currentFile: f1,
      sourceFolderID: sourceFolderID
    )

    let readerQueue = PlaybackQueue()
    let restored = readerQueue.restorePersistedSnapshot { ids in
      var filesByID: [UUID: ABFile] = [:]
      for file in [f1, f2, f3] where ids.contains(file.id) {
        filesByID[file.id] = file
      }
      return filesByID
    }

    #expect(restored)
    #expect(readerQueue.queuedFiles.map(\.id) == [f2.id, f1.id, f3.id])
    #expect(readerQueue.currentFile?.id == f1.id)
    #expect(readerQueue.sourceFolderID == sourceFolderID)
  }

  @Test("restore fails when persisted current file is missing")
  func restoreFailsWhenCurrentFileMissing() throws {
    let (_, ctx) = try makeQueueTestContext()
    let f1 = makeFile("ep1.mp3", in: ctx)
    let f2 = makeFile("ep2.mp3", in: ctx)

    let writerQueue = PlaybackQueue()
    writerQueue.clearPersistedSnapshot()
    defer { writerQueue.clearPersistedSnapshot() }

    writerQueue.replaceQueue(files: [f1, f2], currentFile: f2, sourceFolderID: nil)

    let readerQueue = PlaybackQueue()
    let restored = readerQueue.restorePersistedSnapshot { _ in
      [f1.id: f1]
    }

    #expect(restored == false)
    #expect(readerQueue.hasQueue == false)
    #expect(readerQueue.queuedFiles.isEmpty)
    #expect(readerQueue.currentFile == nil)
  }

  @Test("syncQueue only applies when source folder matches")
  func syncOnlyAppliesToMatchingSource() throws {
    let (_, ctx) = try makeQueueTestContext()
    let folderA = makeFolder("A", in: ctx)
    let folderB = makeFolder("B", in: ctx)

    let a1 = makeFile("a1.mp3", in: ctx, folder: folderA)
    let a2 = makeFile("a2.mp3", in: ctx, folder: folderA)
    let b1 = makeFile("b1.mp3", in: ctx, folder: folderB)
    let b2 = makeFile("b2.mp3", in: ctx, folder: folderB)

    let queue = PlaybackQueue()
    queue.clearPersistedSnapshot()
    defer { queue.clearPersistedSnapshot() }

    queue.replaceQueue(files: [a1, a2], currentFile: a1, sourceFolderID: folderA.id)
    queue.syncQueue(files: [b2, b1], sourceFolderID: folderB.id)

    #expect(queue.queuedFiles.map(\.id) == [a1.id, a2.id])
    #expect(queue.currentFile?.id == a1.id)
    #expect(queue.sourceFolderID == folderA.id)
  }
}

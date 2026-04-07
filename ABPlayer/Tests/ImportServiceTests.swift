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
private func makeTempSourceFile(named name: String) throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
  try Data("audio".utf8).write(to: url)
  return url
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
}

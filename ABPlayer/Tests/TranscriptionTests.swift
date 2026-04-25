import Foundation
import Testing

@testable import ABPlayerDev

// NOTE: TranscriptionCacheTests removed - hash function replaced by audioFileId

// MARK: - Subtitle Cue Encoding Tests

struct SubtitleCueEncodingTests {

  @Test
  func testCueEncodingDecoding() {
    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 2.5, text: "Hello"),
      SubtitleCue(startTime: 2.5, endTime: 5.0, text: "World"),
    ]

    let data = try! JSONEncoder().encode(cues)
    let decoded = try! JSONDecoder().decode([SubtitleCue].self, from: data)

    #expect(decoded.count == 2)
    #expect(decoded[0].text == "Hello")
    #expect(decoded[0].startTime == 0.0)
    #expect(decoded[0].endTime == 2.5)
    #expect(decoded[1].text == "World")
    #expect(decoded[1].startTime == 2.5)
  }

  @Test
  func testCueWithSpecialCharacters() {
    let cue = SubtitleCue(
      startTime: 0.0,
      endTime: 1.0,
      text: "Hello \"World\" with 'quotes' and\nnewlines"
    )

    let data = try! JSONEncoder().encode([cue])
    let decoded = try! JSONDecoder().decode([SubtitleCue].self, from: data)

    #expect(decoded[0].text == "Hello \"World\" with 'quotes' and\nnewlines")
  }

  @Test
  func testEmptyCuesArray() {
    let cues: [SubtitleCue] = []

    let data = try! JSONEncoder().encode(cues)
    let decoded = try! JSONDecoder().decode([SubtitleCue].self, from: data)

    #expect(decoded.isEmpty)
  }
}

// MARK: - Subtitle Sentence Navigation Tests

struct SubtitleCueSentenceNavigationTests {

  @Test
  func latestStartedCueReturnsPreviousCueWhenTimeBetweenCues() {
    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 1.0, text: "First"),
      SubtitleCue(startTime: 2.0, endTime: 3.0, text: "Second"),
      SubtitleCue(startTime: 4.0, endTime: 5.0, text: "Third"),
    ]

    let cue = cues.latestStartedCue(at: 1.5)
    #expect(cue == cues[0])
  }

  @Test
  func latestStartedCueReturnsNilBeforeFirstCue() {
    let cues = [
      SubtitleCue(startTime: 1.0, endTime: 2.0, text: "First"),
      SubtitleCue(startTime: 3.0, endTime: 4.0, text: "Second"),
    ]

    let cue = cues.latestStartedCue(at: 0.5)
    #expect(cue == nil)
  }

  @Test
  func latestStartedCueReturnsLaterCueWhenStartTimesMatch() {
    let cues = [
      SubtitleCue(startTime: 1.0, endTime: 2.0, text: "First"),
      SubtitleCue(startTime: 1.0, endTime: 2.5, text: "Second"),
    ]

    let cue = cues.latestStartedCue(at: 1.5)
    #expect(cue == cues[1])
  }

  @Test
  func previousSentenceStartReturnsCurrentSentenceStartWhenTimeBetweenCues() {
    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 1.0, text: "First"),
      SubtitleCue(startTime: 2.0, endTime: 3.0, text: "Second"),
      SubtitleCue(startTime: 4.0, endTime: 5.0, text: "Third"),
    ]

    let target = cues.previousSentenceStart(at: 1.5)
    #expect(target == 0.0)
  }

  @Test
  func previousSentenceStartReturnsPreviousSentenceWhenInsideSentence() {
    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 1.0, text: "First"),
      SubtitleCue(startTime: 2.0, endTime: 3.0, text: "Second"),
      SubtitleCue(startTime: 4.0, endTime: 5.0, text: "Third"),
    ]

    let target = cues.previousSentenceStart(at: 2.5)
    #expect(target == 0.0)
  }

  @Test
  func nextSentenceStartReturnsNextSentenceWhenInsideSentence() {
    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 1.0, text: "First"),
      SubtitleCue(startTime: 2.0, endTime: 3.0, text: "Second"),
      SubtitleCue(startTime: 4.0, endTime: 5.0, text: "Third"),
    ]

    let target = cues.nextSentenceStart(at: 2.5)
    #expect(target == 4.0)
  }

  @Test
  func nextSentenceStartReturnsCurrentSentenceWhenTimeBetweenCues() {
    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 1.0, text: "First"),
      SubtitleCue(startTime: 2.0, endTime: 3.0, text: "Second"),
      SubtitleCue(startTime: 4.0, endTime: 5.0, text: "Third"),
    ]

    let target = cues.nextSentenceStart(at: 1.5)
    #expect(target == 2.0)
  }

  @Test
  func sentenceStartMethodsHandleEmptyCues() {
    let cues: [SubtitleCue] = []

    #expect(cues.previousSentenceStart(at: 1.0) == nil)
    #expect(cues.nextSentenceStart(at: 1.0) == nil)
  }
}

// MARK: - Transcription State Tests

struct TranscriptionStateTests {

  @Test
  func testIdleStateEquality() {
    #expect(TranscriptionState.idle == TranscriptionState.idle)
  }

  @Test
  func testLoadingStateEquality() {
    #expect(
      TranscriptionState.loading(modelName: "tiny")
        == TranscriptionState.loading(modelName: "tiny"))
  }

  @Test
  func testTranscribingStateEqualityWithSameProgress() {
    #expect(
      TranscriptionState.transcribing(progress: 0.5, fileName: "test.mp3")
        == TranscriptionState.transcribing(progress: 0.5, fileName: "test.mp3"))
  }

  @Test
  func testTranscribingStateInequalityWithDifferentProgress() {
    #expect(
      TranscriptionState.transcribing(progress: 0.5, fileName: "test.mp3")
        != TranscriptionState.transcribing(progress: 0.6, fileName: "test.mp3"))
  }

  @Test
  func testCompletedStateEquality() {
    #expect(TranscriptionState.completed == TranscriptionState.completed)
  }

  @Test
  func testFailedStateEqualityWithSameMessage() {
    #expect(
      TranscriptionState.failed("Error")
        == TranscriptionState.failed("Error"))
  }

  @Test
  func testFailedStateInequalityWithDifferentMessage() {
    #expect(
      TranscriptionState.failed("Error 1")
        != TranscriptionState.failed("Error 2"))
  }

  @Test
  func testDifferentStatesAreNotEqual() {
    #expect(TranscriptionState.idle != TranscriptionState.loading(modelName: "tiny"))
    #expect(TranscriptionState.loading(modelName: "tiny") != TranscriptionState.completed)
    #expect(
      TranscriptionState.transcribing(progress: 0.5, fileName: "test.mp3")
        != TranscriptionState.completed)
  }
}

@MainActor
struct TranscriptionQueueManagedLibraryTests {

  @Test
  func enqueueStoresRelativePathAndIgnoresBookmarkData() {
    let transcriptionManager = TranscriptionManager()
    let settings = TranscriptionSettings()
    let librarySettings = LibrarySettings()
    let subtitleLoader = SubtitleLoader(librarySettings: librarySettings)
    let queueManager = TranscriptionQueueManager(
      transcriptionManager: transcriptionManager,
      settings: settings,
      subtitleLoader: subtitleLoader,
      librarySettings: librarySettings
    )

    let audioFile = ABFile(
      displayName: "chapter.mp3",
      bookmarkData: Data([0xAA, 0xBB]),
      relativePath: "book/chapter.mp3"
    )

    queueManager.enqueue(audioFile: audioFile)

    let task = queueManager.tasks.first
    #expect(task != nil)
    #expect(task?.audioRelativePath == "book/chapter.mp3")
    #expect(task?.bookmarkData.isEmpty == true)
  }

  @Test
  func processQueueUsesRelativePathWhenBookmarkIsEmpty() async throws {
    let transcriptionManager = TranscriptionManager()
    let settings = TranscriptionSettings()

    let libraryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("TranscriptionQueueManagedLibraryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: libraryRoot) }

    let librarySettings = LibrarySettings()
    librarySettings.libraryPath = libraryRoot.path
    let subtitleLoader = SubtitleLoader(librarySettings: librarySettings)
    let queueManager = TranscriptionQueueManager(
      transcriptionManager: transcriptionManager,
      settings: settings,
      subtitleLoader: subtitleLoader,
      librarySettings: librarySettings
    )

    let relativePath = "book/chapter.mp3"
    let audioURL = libraryRoot.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("audio".utf8).write(to: audioURL)

    let srtURL = audioURL.deletingPathExtension().appendingPathExtension("srt")
    let srt = [
      "1",
      "00:00:00,000 --> 00:00:01,000",
      "Line",
      "",
    ].joined(separator: "\n")
    try srt.write(to: srtURL, atomically: true, encoding: .utf8)

    let audioFile = ABFile(
      displayName: "chapter.mp3",
      bookmarkData: Data([0xAA, 0xBB]),
      relativePath: relativePath
    )

    queueManager.enqueue(audioFile: audioFile)

    let didComplete = await waitUntil {
      queueManager.tasks.first?.status == .completed
    }

    #expect(didComplete)
    #expect(queueManager.tasks.first?.bookmarkData.isEmpty == true)
    #expect(!subtitleLoader.cachedSubtitles(for: audioFile.id).isEmpty)
  }
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

// MARK: - Transcription Settings Tests

@MainActor
struct TranscriptionSettingsTests {

  private let modelDirectoryKey = "transcription_model_directory"
  private let modelDirectoryBookmarkKey = "transcription_model_directory_bookmark"

  private func clearModelDirectoryDefaults() {
    UserDefaults.standard.removeObject(forKey: modelDirectoryKey)
    UserDefaults.standard.removeObject(forKey: modelDirectoryBookmarkKey)
  }

  @Test
  func testAvailableModelsNotEmpty() {
    #expect(!TranscriptionSettings.availableModels.isEmpty)
  }

  @Test
  func testDefaultModelInAvailableModels() {
    let defaultModel = "distil-large-v3"
    let modelIds = TranscriptionSettings.availableModels.map { $0.id }

    #expect(modelIds.contains(defaultModel))
  }

  @Test
  func testAvailableLanguagesIncludesAutoDetect() {
    let languageIds = TranscriptionSettings.availableLanguages.map { $0.id }

    #expect(languageIds.contains("auto"))
  }

  @Test
  func testAvailableLanguagesIncludesEnglish() {
    let languageIds = TranscriptionSettings.availableLanguages.map { $0.id }

    #expect(languageIds.contains("en"))
  }

  @Test
  func testIsModelDownloadedAsyncReturnsFalseForNonexistentDirectory() async {
    let settings = TranscriptionSettings()
    settings.modelDirectory = "/nonexistent/path/that/does/not/exist"

    let isDownloaded = await settings.isModelDownloadedAsync(modelName: "tiny")

    #expect(!isDownloaded, "Should return false for non-existent directory")
  }

  @Test
  func testListDownloadedModelsReturnsEmptyForNonexistentDirectory() async {
    let settings = TranscriptionSettings()
    settings.modelDirectory = "/nonexistent/path/that/does/not/exist"

    let models = await settings.listDownloadedModelsAsync()

    #expect(models.isEmpty, "Should return empty array for non-existent directory")
  }

  @Test
  func testListDownloadedModelsReturnsEmptyForEmptyDirectory() async throws {
    let settings = TranscriptionSettings()
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    settings.modelDirectory = tempDir.path
    let models = await settings.listDownloadedModelsAsync()

    #expect(models.isEmpty, "Should return empty array for empty directory")
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
  func testListDownloadedModelsDetectsModelDirectory() async throws {
    let settings = TranscriptionSettings()
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let modelDir =
      tempDir
      .appendingPathComponent("models")
      .appendingPathComponent("argmaxinc")
      .appendingPathComponent("whisperkit-coreml")
      .appendingPathComponent("openai_whisper-tiny")

    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    try "{}".write(
      to: modelDir.appendingPathComponent("config.json"),
      atomically: true,
      encoding: .utf8
    )

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    settings.modelDirectory = tempDir.path
    let models = await settings.listDownloadedModelsAsync()

    #expect(models.count == 1, "Should detect one model directory")
    #expect(models.first?.name == "openai_whisper-tiny", "Model name should match directory name")
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
  func testIsModelDownloadedAsyncDetectsValidModelDirectory() async throws {
    let settings = TranscriptionSettings()
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let modelDir =
      tempDir
      .appendingPathComponent("models")
      .appendingPathComponent("argmaxinc")
      .appendingPathComponent("whisperkit-coreml")
      .appendingPathComponent("openai_whisper-tiny")

    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: modelDir.appendingPathComponent("AudioEncoder.mlmodelc"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: modelDir.appendingPathComponent("TextDecoder.mlmodelc"),
      withIntermediateDirectories: true
    )
    try "{}".write(
      to: modelDir.appendingPathComponent("config.json"),
      atomically: true,
      encoding: .utf8
    )

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    settings.modelDirectory = tempDir.path
    let isDownloaded = await settings.isModelDownloadedAsync(modelName: "tiny")

    #expect(isDownloaded, "Should detect model directory with required indicator files")
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
  func testIsModelDownloadedAsyncDoesNotConfuseLargeV3WithDistilLargeV3() async throws {
    let settings = TranscriptionSettings()
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let distilDir =
      tempDir
      .appendingPathComponent("models")
      .appendingPathComponent("argmaxinc")
      .appendingPathComponent("whisperkit-coreml")
      .appendingPathComponent("distil-whisper_distil-large-v3")

    try FileManager.default.createDirectory(at: distilDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: distilDir.appendingPathComponent("AudioEncoder.mlmodelc"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: distilDir.appendingPathComponent("TextDecoder.mlmodelc"),
      withIntermediateDirectories: true
    )
    try "{}".write(
      to: distilDir.appendingPathComponent("config.json"),
      atomically: true,
      encoding: .utf8
    )

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    settings.modelDirectory = tempDir.path

    let largeV3Downloaded = await settings.isModelDownloadedAsync(modelName: "large-v3")
    let distilDownloaded = await settings.isModelDownloadedAsync(modelName: "distil-large-v3")

    #expect(!largeV3Downloaded, "Should not treat distil-large-v3 as large-v3")
    #expect(distilDownloaded, "Should still detect distil-large-v3 correctly")
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
  func testIsModelDownloadedAsyncReturnsFalseForIncompleteModelDirectory() async throws {
    let settings = TranscriptionSettings()
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let modelDir =
      tempDir
      .appendingPathComponent("models")
      .appendingPathComponent("argmaxinc")
      .appendingPathComponent("whisperkit-coreml")
      .appendingPathComponent("openai_whisper-tiny")

    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    try "{}".write(
      to: modelDir.appendingPathComponent("config.json"),
      atomically: true,
      encoding: .utf8
    )

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    settings.modelDirectory = tempDir.path
    let isDownloaded = await settings.isModelDownloadedAsync(modelName: "tiny")

    #expect(!isDownloaded, "Should require all model indicator files")
  }

  @Test
  func testPerformLegacyMigrationReturnsFalseWhenMoveFails() throws {
    let modelDirectoryKey = UserDefaultsKey.transcriptionModelDirectory
    let previousModelDirectory = UserDefaults.standard.string(forKey: modelDirectoryKey)
    UserDefaults.standard.removeObject(forKey: modelDirectoryKey)
    defer {
      if let previousModelDirectory {
        UserDefaults.standard.set(previousModelDirectory, forKey: modelDirectoryKey)
      } else {
        UserDefaults.standard.removeObject(forKey: modelDirectoryKey)
      }
    }

    let settings = TranscriptionSettings(performInitialMigration: false)

    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("TranscriptionLegacyMigrationFailure-\(UUID().uuidString)", isDirectory: true)
    let legacyDirectory = tempRoot.appendingPathComponent("legacy", isDirectory: true)
    let newDirectory = tempRoot.appendingPathComponent("new", isDirectory: false)

    defer { try? FileManager.default.removeItem(at: tempRoot) }

    try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
    let legacySubdirectory = legacyDirectory.appendingPathComponent("openai_whisper-tiny", isDirectory: true)
    try FileManager.default.createDirectory(at: legacySubdirectory, withIntermediateDirectories: true)

    try Data("blocking".utf8).write(to: newDirectory)

    let migrated = settings.performLegacyDefaultModelDirectoryMigration(
      from: legacyDirectory,
      to: newDirectory
    )

    #expect(
      migrated == false,
      "Migration helper should return false when destination path blocks model move"
    )
  }

  @Test
  func testFormatSizeReturnsReadableString() {
    let mbSize: Int64 = 100 * 1024 * 1024
    let mbFormatted = TranscriptionSettings.formatSize(mbSize)
    #expect(mbFormatted.contains("MB") || mbFormatted.contains("100"))

    let gbSize: Int64 = 2 * 1024 * 1024 * 1024
    let gbFormatted = TranscriptionSettings.formatSize(gbSize)
    #expect(gbFormatted.contains("GB") || gbFormatted.contains("2"))
  }

  @Test
  func testSetModelDirectoryPersistsBookmarkData() throws {
    clearModelDirectoryDefaults()
    defer { clearModelDirectoryDefaults() }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let settings = TranscriptionSettings(performInitialMigration: false)

    settings.modelDirectory = ""
    settings.modelDirectoryBookmarkData = nil

    try settings.setModelDirectory(directory)

    #expect(settings.modelDirectory == directory.path)
    #expect((settings.modelDirectoryBookmarkData?.isEmpty == false))
  }

  @Test
  func testBestEffortMigrationSkipsMissingSourceDirectory() throws {
    let settings = TranscriptionSettings(performInitialMigration: false)

    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("TranscriptionBestEffortMissing-\(UUID().uuidString)", isDirectory: true)
    let missingDirectory = tempRoot.appendingPathComponent("missing", isDirectory: true)
    let destinationDirectory = tempRoot.appendingPathComponent("destination", isDirectory: true)

    defer { try? FileManager.default.removeItem(at: tempRoot) }

    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let result = settings.migrateModelsBestEffort(
      from: missingDirectory,
      oldDirectoryBookmarkData: nil,
      to: destinationDirectory
    )

    if case .skippedSourceMissing = result {
      #expect(true)
    } else {
      Issue.record("Expected skippedSourceMissing for missing source directory")
    }
  }

  @Test
  func testBestEffortMigrationMovesDirectoriesWhenSourceAccessible() throws {
    let settings = TranscriptionSettings(performInitialMigration: false)

    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("TranscriptionBestEffortSuccess-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = tempRoot.appendingPathComponent("source", isDirectory: true)
    let destinationDirectory = tempRoot.appendingPathComponent("destination", isDirectory: true)
    let sourceModelDirectory = sourceDirectory.appendingPathComponent("openai_whisper-tiny", isDirectory: true)

    defer { try? FileManager.default.removeItem(at: tempRoot) }

    try FileManager.default.createDirectory(at: sourceModelDirectory, withIntermediateDirectories: true)

    let result = settings.migrateModelsBestEffort(
      from: sourceDirectory,
      oldDirectoryBookmarkData: nil,
      to: destinationDirectory
    )

    if case .migrated = result {
      #expect(FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent("openai_whisper-tiny").path))
      #expect(!FileManager.default.fileExists(atPath: sourceModelDirectory.path))
    } else {
      Issue.record("Expected migrated when source directory is accessible")
    }
  }

  @Test
  func testBestEffortMigrationReturnsFailureWhenDestinationIsBlocked() throws {
    let settings = TranscriptionSettings(performInitialMigration: false)

    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("TranscriptionBestEffortFailure-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = tempRoot.appendingPathComponent("source", isDirectory: true)
    let destinationPath = tempRoot.appendingPathComponent("destination", isDirectory: false)
    let sourceModelDirectory = sourceDirectory.appendingPathComponent("openai_whisper-tiny", isDirectory: true)

    defer { try? FileManager.default.removeItem(at: tempRoot) }

    try FileManager.default.createDirectory(at: sourceModelDirectory, withIntermediateDirectories: true)
    try Data("blocking".utf8).write(to: destinationPath)

    let result = settings.migrateModelsBestEffort(
      from: sourceDirectory,
      oldDirectoryBookmarkData: nil,
      to: destinationPath
    )

    if case .failed = result {
      #expect(true)
    } else {
      Issue.record("Expected failure when destination path blocks migration")
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
  func testBestEffortMigrationSkipsInaccessibleSourceDirectory() throws {
    let settings = TranscriptionSettings(performInitialMigration: false)

    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("TranscriptionBestEffortNoPermission-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = tempRoot.appendingPathComponent("source", isDirectory: true)
    let destinationDirectory = tempRoot.appendingPathComponent("destination", isDirectory: true)
    let sourceModelDirectory = sourceDirectory.appendingPathComponent("openai_whisper-tiny", isDirectory: true)

    try FileManager.default.createDirectory(at: sourceModelDirectory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sourceDirectory.path)

    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sourceDirectory.path)
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let result = settings.migrateModelsBestEffort(
      from: sourceDirectory,
      oldDirectoryBookmarkData: nil,
      to: destinationDirectory
    )

    if case .skippedSourceInaccessible = result {
      #expect(true)
    } else {
      Issue.record("Expected skippedSourceInaccessible when source directory permission is denied")
    }
  }
}

// MARK: - Transcription Manager Tests

@MainActor
struct TranscriptionManagerTests {
  @Test
  func testResetSetsStateToIdle() {
    let manager = TranscriptionManager()

    // Set state to something other than idle
    manager.state = .failed("Test Error")
    #expect(manager.state != .idle)

    // Reset and verify
    manager.reset()
    #expect(manager.state == .idle)
  }

}

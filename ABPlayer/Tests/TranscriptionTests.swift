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

// MARK: - Transcription Settings Tests

@MainActor
struct TranscriptionSettingsTests {

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

  @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
  func testDefaultModelDirectoryIsInUserHome() {
    let defaultDir = TranscriptionSettings.defaultModelDirectory

    #expect(
      defaultDir.path.contains(".abplayer"),
      "Default directory should be in ~/.abplayer"
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

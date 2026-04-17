import AVFoundation
import Foundation
import SwiftData
import Testing

@testable import ABPlayerDev

// MARK: - A-B Loop Logic Tests

struct ABLoopTests {

  // MARK: - Loop Check Tests

  @Test
  func testLoopCheckTriggersWhenTimeExceedsPointB() {
    // Given: pointB = 20.0, currentTime = 20.0
    let pointB = 20.0
    let currentTime = 20.0

    // When: checking if loop should trigger
    let shouldLoop = currentTime >= pointB

    // Then: should trigger loop back to A
    #expect(shouldLoop == true)
  }

  @Test
  func testLoopCheckDoesNotTriggerBeforePointB() {
    // Given: pointB = 20.0, currentTime = 15.0
    let pointB = 20.0
    let currentTime = 15.0

    // When: checking if loop should trigger
    let shouldLoop = currentTime >= pointB

    // Then: should NOT trigger loop
    #expect(shouldLoop == false)
  }

  @Test
  func testLoopCheckWithZeroPointA() {
    // Given: pointB = 5.0, currentTime = 5.5
    let pointB = 5.0
    let currentTime = 5.5

    // When: checking if loop should trigger
    let shouldLoop = currentTime >= pointB

    // Then: should trigger loop
    #expect(shouldLoop == true)
  }

  // MARK: - Point A/B Validation Tests

  @Test
  func testPointBMustBeAfterPointA() {
    // Given: pointA = 15.0, pointB = 10.0 (invalid: B before A)
    let pointA = 15.0
    let pointB = 10.0

    // When: validating A-B range
    let isValidRange = pointB > pointA

    // Then: should be invalid
    #expect(isValidRange == false)
  }

  @Test
  func testValidPointABRange() {
    // Given: pointA = 10.0, pointB = 20.0 (valid)
    let pointA = 10.0
    let pointB = 20.0

    // When: validating A-B range
    let isValidRange = pointB > pointA

    // Then: should be valid
    #expect(isValidRange == true)
  }

  @Test
  func testPointAEqualToPointBIsInvalid() {
    // Given: pointA = pointB = 10.0 (invalid: same point)
    let pointA = 10.0
    let pointB = 10.0

    // When: validating A-B range
    let isValidRange = pointB > pointA

    // Then: should be invalid
    #expect(isValidRange == false)
  }

  // MARK: - Seek Clamping Tests

  @Test
  func testSeekClampToZero() {
    // Given: target time is negative
    let targetTime = -5.0
    let duration = 100.0

    // When: clamping the seek value
    let clampedTime = min(max(targetTime, 0), duration)

    // Then: should clamp to 0
    #expect(clampedTime == 0)
  }

  @Test
  func testSeekClampToDuration() {
    // Given: target time exceeds duration
    let targetTime = 150.0
    let duration = 100.0

    // When: clamping the seek value
    let clampedTime = min(max(targetTime, 0), duration)

    // Then: should clamp to duration
    #expect(clampedTime == 100.0)
  }

  @Test
  func testSeekWithinBounds() {
    // Given: target time is within bounds
    let targetTime = 50.0
    let duration = 100.0

    // When: clamping the seek value
    let clampedTime = min(max(targetTime, 0), duration)

    // Then: should remain unchanged
    #expect(clampedTime == 50.0)
  }

  // MARK: - Segment Duplicate Detection Tests

  @Test
  func testDetectDuplicateSegment() {
    // Given: existing segment with startTime=10, endTime=20
    let existingSegments = [(startTime: 10.0, endTime: 20.0)]
    let newStartTime = 10.0
    let newEndTime = 20.0

    // When: checking for duplicate
    let isDuplicate = existingSegments.contains {
      $0.startTime == newStartTime && $0.endTime == newEndTime
    }

    // Then: should detect as duplicate
    #expect(isDuplicate == true)
  }

  @Test
  func testNonDuplicateSegment() {
    // Given: existing segment with startTime=10, endTime=20
    let existingSegments = [(startTime: 10.0, endTime: 20.0)]
    let newStartTime = 15.0
    let newEndTime = 25.0

    // When: checking for duplicate
    let isDuplicate = existingSegments.contains {
      $0.startTime == newStartTime && $0.endTime == newEndTime
    }

    // Then: should NOT be duplicate
    #expect(isDuplicate == false)
  }
}
@MainActor
struct PlaybackQueueLogicTests {
  @Test
  func testRepeatAllWrapsToStart() {
    let queue = PlaybackQueue()
    queue.loopMode = .repeatAll

    let fileA = ABFile(displayName: "A.mp3", bookmarkData: Data("A".utf8))
    let fileB = ABFile(displayName: "B.mp3", bookmarkData: Data("B".utf8))
    let fileC = ABFile(displayName: "C.mp3", bookmarkData: Data("C".utf8))

    queue.updateQueue([fileA, fileB, fileC])
    queue.setCurrentFile(fileC)

    let nextFile = queue.playNext()

    #expect(nextFile?.id == fileA.id)
  }

  @Test
  func testAutoPlayNextStopsAtEnd() {
    let queue = PlaybackQueue()
    queue.loopMode = .autoPlayNext

    let fileA = ABFile(displayName: "A.mp3", bookmarkData: Data("A".utf8))
    let fileB = ABFile(displayName: "B.mp3", bookmarkData: Data("B".utf8))

    queue.updateQueue([fileA, fileB])
    queue.setCurrentFile(fileB)

    let nextFile = queue.playNext()

    #expect(nextFile == fileA)
  }

  @Test
  func testShuffleSkipsCurrentWhenPossible() {
    let queue = PlaybackQueue()
    queue.loopMode = .shuffle

    let fileA = ABFile(displayName: "A.mp3", bookmarkData: Data("A".utf8))
    let fileB = ABFile(displayName: "B.mp3", bookmarkData: Data("B".utf8))

    queue.updateQueue([fileA, fileB])
    queue.setCurrentFile(fileA)

    let nextFile = queue.playNext()

    #expect(nextFile?.id != fileA.id)
  }

  @Test
  func testPlayPrevRepeatAllWrapsToEnd() {
    let queue = PlaybackQueue()
    queue.loopMode = .repeatAll

    let fileA = ABFile(displayName: "A.mp3", bookmarkData: Data("A".utf8))
    let fileB = ABFile(displayName: "B.mp3", bookmarkData: Data("B".utf8))

    queue.updateQueue([fileA, fileB])
    queue.setCurrentFile(fileA)

    let previousFile = queue.playPrev()

    #expect(previousFile?.id == fileB.id)
  }

  @Test
  func testQueueClearsCurrentWhenMissing() {
    let queue = PlaybackQueue()
    queue.loopMode = .repeatAll

    let fileA = ABFile(displayName: "A.mp3", bookmarkData: Data("A".utf8))
    let fileB = ABFile(displayName: "B.mp3", bookmarkData: Data("B".utf8))
    let fileC = ABFile(displayName: "C.mp3", bookmarkData: Data("C".utf8))

    queue.updateQueue([fileA, fileB, fileC])
    queue.setCurrentFile(fileB)

    queue.updateQueue([fileA, fileC])
    let nextFile = queue.playNext()

    #expect(nextFile?.id == fileA.id)
  }
}

// MARK: - SessionTracker Logic Tests

struct SessionTrackerLogicTests {

  private func makeSessionContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: ListeningSession.self, configurations: config)
  }

  @MainActor
  private func makeTracker(
    warmupThreshold: Double = 5,
    idleTimeout: TimeInterval = 5
  ) throws -> (SessionTracker, ModelContext) {
    let container = try makeSessionContainer()
    let tracker = SessionTracker(
      modelContainer: container,
      warmupThreshold: warmupThreshold,
      idleTimeout: idleTimeout
    )
    return (tracker, ModelContext(container))
  }

  @Test
  @MainActor
  func testWarmupLessThanThresholdDoesNotStartSession() async throws {
    let (tracker, context) = try makeTracker(warmupThreshold: 5, idleTimeout: 0.05)

    tracker.handlePlaybackStateChanged(isPlaying: true)
    tracker.recordPlaybackTick(4.9)
    tracker.handlePlaybackStateChanged(isPlaying: false)
    try? await Task.sleep(nanoseconds: 70_000_000)
    await tracker.waitForRecorderTasksForTesting()

    let sessions = (try? context.fetch(FetchDescriptor<ListeningSession>())) ?? []
    #expect(sessions.isEmpty)
    #expect(tracker.displaySeconds == 0)
  }

  @Test
  @MainActor
  func testWarmupThresholdCountsInitialFiveSecondsInSchemeB() async throws {
    let (tracker, context) = try makeTracker(warmupThreshold: 5, idleTimeout: 0.05)

    tracker.handlePlaybackStateChanged(isPlaying: true)
    tracker.recordPlaybackTick(5.1)
    tracker.handlePlaybackStateChanged(isPlaying: false)
    tracker.endSession()
    await tracker.waitForRecorderTasksForTesting()

    let sessions = (try? context.fetch(FetchDescriptor<ListeningSession>())) ?? []
    #expect(sessions.count == 1)
    #expect(abs((sessions.first?.duration ?? 0) - 5.1) < 0.001)
    #expect(tracker.displaySeconds == 0)
  }

  @Test
  @MainActor
  func testIdleUnderTimeoutKeepsSameSession() async throws {
    let (tracker, context) = try makeTracker(warmupThreshold: 5, idleTimeout: 0.15)

    tracker.handlePlaybackStateChanged(isPlaying: true)
    tracker.recordPlaybackTick(5.0)
    tracker.recordPlaybackTick(2.0)
    tracker.handlePlaybackStateChanged(isPlaying: false)
    try? await Task.sleep(nanoseconds: 80_000_000)
    tracker.handlePlaybackStateChanged(isPlaying: true)
    tracker.recordPlaybackTick(1.0)
    tracker.endSession()
    await tracker.waitForRecorderTasksForTesting()

    let sessions = (try? context.fetch(FetchDescriptor<ListeningSession>())) ?? []
    #expect(sessions.count == 1)
    #expect(abs((sessions.first?.duration ?? 0) - 8.0) < 0.001)
  }

  @Test
  @MainActor
  func testIdleTimeoutEndsSessionAndResetsCounter() async throws {
    let (tracker, context) = try makeTracker(warmupThreshold: 5, idleTimeout: 0.05)

    tracker.handlePlaybackStateChanged(isPlaying: true)
    tracker.recordPlaybackTick(5.0)
    tracker.recordPlaybackTick(1.0)
    tracker.handlePlaybackStateChanged(isPlaying: false)
    try? await Task.sleep(nanoseconds: 80_000_000)
    await tracker.waitForRecorderTasksForTesting()

    let sessions = (try? context.fetch(FetchDescriptor<ListeningSession>())) ?? []
    #expect(sessions.count == 1)
    #expect(abs((sessions.first?.duration ?? 0) - 6.0) < 0.001)
    #expect(tracker.displaySeconds == 0)
  }

  @Test
  @MainActor
  func testEndSessionAndWaitFlushesEndedSession() async throws {
    let (tracker, context) = try makeTracker(warmupThreshold: 5, idleTimeout: 0.2)

    tracker.handlePlaybackStateChanged(isPlaying: true)
    tracker.recordPlaybackTick(5.0)
    await tracker.endSessionAndWaitForTesting()

    let sessions = (try? context.fetch(FetchDescriptor<ListeningSession>())) ?? []
    #expect(sessions.count == 1)
    #expect(abs((sessions.first?.duration ?? 0) - 5.0) < 0.001)
    #expect(sessions.first?.endedAt != nil)
  }

  @Test
  @MainActor
  func testOrphanCleanupRepairsAndMergesNearbyOrphans() async throws {
    let (tracker, context) = try makeTracker(warmupThreshold: 5, idleTimeout: 0.2)
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    let orphanA = ListeningSession(
      startedAt: base,
      endedAt: nil,
      duration: 120
    )
    let orphanB = ListeningSession(
      startedAt: base.addingTimeInterval(170),
      endedAt: nil,
      duration: 90
    )
    let orphanC = ListeningSession(
      startedAt: base.addingTimeInterval(400),
      endedAt: nil,
      duration: 30
    )

    context.insert(orphanA)
    context.insert(orphanB)
    context.insert(orphanC)
    try context.save()

    await tracker.repairOrphanSessionsNow()

    let sessions = (try? context.fetch(
      FetchDescriptor<ListeningSession>(
        sortBy: [SortDescriptor(\ListeningSession.startedAt, order: .forward)]
      )
    )) ?? []

    #expect(sessions.count == 2)

    let first = sessions[0]
    let second = sessions[1]

    #expect(first.startedAt == base)
    #expect(abs(first.duration - 210) < 0.001)
    #expect(first.endedAt == base.addingTimeInterval(260))

    #expect(second.startedAt == base.addingTimeInterval(400))
    #expect(abs(second.duration - 30) < 0.001)
    #expect(second.endedAt == base.addingTimeInterval(430))
  }

  @Test
  @MainActor
  func testOrphanCleanupDeletesInvalidZeroDurationOrphan() async throws {
    let (tracker, context) = try makeTracker(warmupThreshold: 5, idleTimeout: 0.2)
    let base = Date(timeIntervalSince1970: 1_700_100_000)

    let invalidOrphan = ListeningSession(
      startedAt: base,
      endedAt: nil,
      duration: 0
    )
    let validOrphan = ListeningSession(
      startedAt: base.addingTimeInterval(120),
      endedAt: nil,
      duration: 30
    )

    context.insert(invalidOrphan)
    context.insert(validOrphan)
    try context.save()

    await tracker.repairOrphanSessionsNow()

    let sessions = (try? context.fetch(
      FetchDescriptor<ListeningSession>(
        sortBy: [SortDescriptor(\ListeningSession.startedAt, order: .forward)]
      )
    )) ?? []

    #expect(sessions.count == 1)
    #expect(sessions.first?.startedAt == base.addingTimeInterval(120))
    #expect(sessions.first?.endedAt == base.addingTimeInterval(150))
  }

  @Test
  func testListeningTimeAccumulation() {
    // Given: initial duration and delta
    var totalDuration = 0.0
    let deltas = [0.03, 0.03, 0.03, 0.03]  // 4 ticks

    // When: accumulating listening time
    for delta in deltas {
      totalDuration += delta
    }

    // Then: total should be sum of deltas
    #expect(abs(totalDuration - 0.12) < 0.001)
  }

  @Test
  func testNegativeDeltaIgnored() {
    // Given: negative delta
    let delta = -0.5
    var totalDuration = 10.0

    // When: attempting to add negative time
    if delta > 0 {
      totalDuration += delta
    }

    // Then: duration should be unchanged
    #expect(totalDuration == 10.0)
  }

  @Test
  func testZeroDeltaIgnored() {
    // Given: zero delta
    let delta = 0.0
    var totalDuration = 10.0

    // When: attempting to add zero time
    if delta > 0 {
      totalDuration += delta
    }

    // Then: duration should be unchanged
    #expect(totalDuration == 10.0)
  }

  @Test
  func testSaveIntervalThreshold() {
    // Given: save interval of 5 seconds
    let lastSavedSeconds = 0.0
    var currentSeconds = 4.9

    // When: checking if save should trigger
    var shouldSave = currentSeconds - lastSavedSeconds >= 5

    // Then: should NOT save yet
    #expect(shouldSave == false)

    // When: exceeding threshold
    currentSeconds = 5.0
    shouldSave = currentSeconds - lastSavedSeconds >= 5

    // Then: should save
    #expect(shouldSave == true)
  }
}

// MARK: - Subtitle Parser Tests

struct SubtitleParserTests {

  @Test
  func testTimestampParsingHHMMSS() {
    // Given: timestamp components
    let hours = 1.0
    let minutes = 30.0
    let seconds = 45.5

    // When: converting to seconds
    let totalSeconds = hours * 3600 + minutes * 60 + seconds

    // Then: should be 5445.5 seconds
    #expect(totalSeconds == 5445.5)
  }

  @Test
  func testTimestampParsingMMSS() {
    // Given: timestamp without hours
    let hours = 0.0
    let minutes = 5.0
    let seconds = 30.0

    // When: converting to seconds
    let totalSeconds = hours * 3600 + minutes * 60 + seconds

    // Then: should be 330 seconds
    #expect(totalSeconds == 330.0)
  }

  @Test
  func testSubtitleFormatDetectionSRT() {
    let filename = "movie.srt"
    let ext = filename.split(separator: ".").last ?? ""

    #expect(ext == "srt")
  }

  @Test
  func testSubtitleFormatDetectionVTT() {
    let filename = "podcast.vtt"
    let ext = filename.split(separator: ".").last ?? ""

    #expect(ext == "vtt")
  }

  @Test
  func testCueTimeRangeValidation() {
    // Given: a cue with valid time range
    let startTime = 10.5
    let endTime = 15.3

    // When: validating range
    let isValid = endTime > startTime && startTime >= 0

    // Then: should be valid
    #expect(isValid == true)
  }

  @Test
  func testCueWithInvalidTimeRange() {
    // Given: a cue with invalid time range (end before start)
    let startTime = 20.0
    let endTime = 15.0

    // When: validating range
    let isValid = endTime > startTime && startTime >= 0

    // Then: should be invalid
    #expect(isValid == false)
  }
}

// MARK: - Folder Import Logic Tests

struct FolderImportLogicTests {

  @Test
  func testABFileExtensionMatching() {
    let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac"]

    #expect(audioExtensions.contains("mp3"))
    #expect(audioExtensions.contains("m4a"))
    #expect(audioExtensions.contains("wav"))
    #expect(audioExtensions.contains("aac"))
    #expect(!audioExtensions.contains("txt"))
    #expect(!audioExtensions.contains("pdf"))
  }

  @Test
  func testSubtitleFileExtensionMatching() {
    let subtitleExtensions: Set<String> = ["srt", "vtt"]

    #expect(subtitleExtensions.contains("srt"))
    #expect(subtitleExtensions.contains("vtt"))
    #expect(!subtitleExtensions.contains("mp3"))
  }

  @Test
  func testBaseNameMatchingForPairing() {
    // Given: audio file and corresponding subtitle
    let audioBaseName = "lecture_001"
    let subtitleBaseName = "lecture_001"

    // When: comparing base names (case-insensitive)
    let isMatch = audioBaseName.lowercased() == subtitleBaseName.lowercased()

    // Then: should match
    #expect(isMatch == true)
  }

  @Test
  func testBaseNameMatchingCaseInsensitive() {
    // Given: mixed case file names
    let audioBaseName = "LECTURE_001"
    let subtitleBaseName = "lecture_001"

    // When: comparing base names (case-insensitive)
    let isMatch = audioBaseName.lowercased() == subtitleBaseName.lowercased()

    // Then: should match
    #expect(isMatch == true)
  }

  @Test
  func testBaseNameNoMatchDifferentNames() {
    // Given: different base names
    let audioBaseName = "lecture_001"
    let subtitleBaseName = "lecture_002"

    // When: comparing base names
    let isMatch = audioBaseName.lowercased() == subtitleBaseName.lowercased()

    // Then: should NOT match
    #expect(isMatch == false)
  }
}

// MARK: - Time Formatting Tests

struct TimeFormattingTests {

  @Test
  func testTimeStringFormattingMinutesSeconds() {
    // Given: total seconds
    let totalSeconds = 125  // 2:05

    // When: formatting
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    let formatted = String(format: "%d:%02d", minutes, seconds)

    // Then: should format correctly
    #expect(formatted == "2:05")
  }

  @Test
  func testTimeStringFormattingZero() {
    let totalSeconds = 0

    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    let formatted = String(format: "%d:%02d", minutes, seconds)

    #expect(formatted == "0:00")
  }

  @Test
  func testTimeStringFormattingLongDuration() {
    // Given: 1 hour 30 minutes 45 seconds = 5445 seconds
    let totalSeconds = 5445

    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    let formatted = String(format: "%d:%02d", minutes, seconds)

    // Note: Format shows minutes:seconds (90:45 for long durations)
    #expect(formatted == "90:45")
  }

  @Test
  func testRoundingSecondsFromDouble() {
    // Given: double time value
    let timeValue = 125.7

    // When: rounding to integer seconds
    let totalSeconds = Int(timeValue.rounded())

    // Then: should round correctly
    #expect(totalSeconds == 126)
  }
}

// MARK: - Scroll Pause Logic Tests

struct ScrollPauseLogicTests {

  @Test
  func testManualScrollSetsUserScrolling() {
    var isUserScrolling = false

    // When: user scrolls manually
    isUserScrolling = true

    #expect(isUserScrolling == true)
  }

  @Test
  func testFollowPlaybackButtonResumesAutoScroll() {
    // Given: user is scrolling
    var isUserScrolling = true

    // When: user taps "follow playback" button
    isUserScrolling = false

    #expect(isUserScrolling == false)
  }

  @Test
  func testCuesChangeResetsScrollState() {
    // Given: user is scrolling
    var isUserScrolling = true
    var currentCueID: UUID? = UUID()

    // When: cues change (simulating .onChange(of: cues))
    isUserScrolling = false
    currentCueID = nil

    // Then: all states should be reset
    #expect(isUserScrolling == false)
    #expect(currentCueID == nil)
  }
}

// MARK: - Vocabulary Logic Tests

struct VocabularyLogicTests {

  @Test
  func testDifficultyLevelCalculation() {
    // Given: forgot count is higher than remembered count
    let forgotCount = 5
    let rememberedCount = 2

    // When: calculating difficulty level
    let difficultyLevel = max(0, forgotCount - rememberedCount)

    // Then: should be the difference
    #expect(difficultyLevel == 3)
  }

  @Test
  func testDifficultyLevelNonNegative() {
    // Given: remembered count is higher than forgot count
    let forgotCount = 2
    let rememberedCount = 5

    // When: calculating difficulty level
    let difficultyLevel = max(0, forgotCount - rememberedCount)

    // Then: should be clamped to 0
    #expect(difficultyLevel == 0)
  }

  @Test
  func testDifficultyLevelEqualCounts() {
    // Given: equal counts
    let forgotCount = 3
    let rememberedCount = 3

    // When: calculating difficulty level
    let difficultyLevel = max(0, forgotCount - rememberedCount)

    // Then: should be 0
    #expect(difficultyLevel == 0)
  }

  @Test
  func testDifficultyColorLevel1IsGreen() {
    let color = colorForDifficulty(level: 1)

    // Then: should be green
    #expect(color == "green")
  }

  @Test
  func testDifficultyColorLevel2IsYellow() {
    let color = colorForDifficulty(level: 2)

    // Then: should be yellow
    #expect(color == "yellow")
  }

  @Test
  func testDifficultyColorLevel3OrMoreIsRed() {
    for level in [3, 4, 5, 10] {
      let color = colorForDifficulty(level: level)

      // Then: should be red
      #expect(color == "red")
    }
  }

  @Test
  func testNewVocabularyStartsWithForgotCount1() {
    // Given: a new vocabulary entry after clicking "Don't know + 1"
    let initialForgotCount = 1
    let initialRememberedCount = 0

    // When: calculating difficulty level
    let difficultyLevel = max(0, initialForgotCount - initialRememberedCount)

    // Then: should be 1 (green)
    #expect(difficultyLevel == 1)
  }

  @Test
  func testWordNormalization() {
    // Given: word with punctuation and mixed case
    let word = "Hello,"
    let normalized = word.lowercased().trimmingCharacters(
      in: CharacterSet.punctuationCharacters)

    // Then: should be lowercase without punctuation
    #expect(normalized == "hello")
  }

  private func colorForDifficulty(level: Int) -> String {
    switch level {
    case 1: "green"
    case 2: "yellow"
    default: "red"
    }
  }
}

struct SortingUtilityTests {

  @Test
  func testExtractLeadingNumberUsesFirstNumericSegment() {
    #expect(SortingUtility.extractLeadingNumber("englishpod_B0024pb") == 24)
    #expect(SortingUtility.extractLeadingNumber("abc_B0024_987XXpb") == 24)
    #expect(SortingUtility.extractLeadingNumber("no_digits") == Int.max)
  }

  @Test
  func testSortAudioFilesByNumberAscUsesFirstNumericSegment() {
    let fileA = ABFile(displayName: "englishpod_B0100pb", bookmarkData: Data("A".utf8))
    let fileB = ABFile(displayName: "abc_B0024_987XXpb", bookmarkData: Data("B".utf8))
    let fileC = ABFile(displayName: "lesson_B0007_part2", bookmarkData: Data("C".utf8))

    let sorted = SortingUtility.sortAudioFiles([fileA, fileB, fileC], by: .numberAsc)

    #expect(sorted.map(\ABFile.displayName) == [
      "lesson_B0007_part2",
      "abc_B0024_987XXpb",
      "englishpod_B0100pb",
    ])
  }
}

// MARK: - Mocks

private func makeBookmarkedAudioFile(displayName: String) -> (ABFile, URL) {
  let fileName = "\(UUID().uuidString)-\(displayName)"
  let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
  do {
    try Data("test".utf8).write(to: fileURL)
    let bookmarkData = try fileURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    let file = ABFile(displayName: displayName, bookmarkData: bookmarkData, relativePath: fileName)
    return (file, fileURL)
  } catch {
    assertionFailure("Failed to create bookmark for \(displayName): \(error)")
    let file = ABFile(displayName: displayName, bookmarkData: Data(), relativePath: fileName)
    return (file, fileURL)
  }
}

@MainActor
private func makePlayerManager(engine: any PlayerEngineProtocol) -> PlayerManager {
  let settings = LibrarySettings()
  settings.libraryPath = FileManager.default.temporaryDirectory.path
  return PlayerManager(librarySettings: settings, engine: engine)
}

actor MockAudioPlayerEngine: PlayerEngineProtocol {
  var currentPlayer: AVPlayer? = AVPlayer()

  // Call tracking
  var loadCallCount = 0
  var lastLoadedFileURL: URL?
  var playCallCount = 0
  var pauseCallCount = 0
  var seekCallCount = 0
  var lastSeekTime: Double?

  // Simulation control
  var loadDelay: UInt64 = 0  // nanoseconds
  var shouldPlayFail = false

  func load(
    fileURL: URL,
    resumeTime: Double,
    onDurationLoaded: @MainActor @Sendable @escaping (Double) -> Void,
    onTimeUpdate: @MainActor @Sendable @escaping (Double) -> Void,
    onLoopCheck: @MainActor @Sendable @escaping (Double) -> Void,
    onPlaybackStateChange: @MainActor @Sendable @escaping (Bool) -> Void,
    onPlayerReady: @MainActor @Sendable @escaping (AVPlayer) -> Void
  ) async throws -> AVPlayerItem? {
    loadCallCount += 1
    lastLoadedFileURL = fileURL

    if loadDelay > 0 {
      try? await Task.sleep(nanoseconds: loadDelay)
    }

    await onDurationLoaded(100.0)  // Dummy duration
    await onPlayerReady(currentPlayer!)

    // Simulate player ready state
    return AVPlayerItem(url: URL(string: "https://example.com/dummy.mp3")!)
  }

  func play() -> Bool {
    playCallCount += 1
    return !shouldPlayFail
  }

  func pause() {
    pauseCallCount += 1
  }

  func syncPauseState() {}
  func syncPlayState() {}
  func seek(to time: Double) {
    seekCallCount += 1
    lastSeekTime = time
  }
  func setVolume(_ volume: Float) async {}
  func teardown() {}
}

// MARK: - Integration Tests with Mock Engine

@MainActor
struct PlayerManagerIntegrationTests {

  @Test
  func testVideoPlaybackEnablesSleepPreventionWhenSettingEnabled() async {
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)
    let settings = PlayerSettings()
    settings.preventSleep = true
    manager.playerSettings = settings

    let (videoFile, videoURL) = makeBookmarkedAudioFile(displayName: "video.mp4")
    defer { try? FileManager.default.removeItem(at: videoURL) }

    await manager.load(audioFile: videoFile)
    await manager.play()

    #expect(manager.isSleepPreventionActiveForTest == true)
  }

  @Test
  func testAudioPlaybackDoesNotEnableSleepPrevention() async {
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)
    let settings = PlayerSettings()
    settings.preventSleep = true
    manager.playerSettings = settings

    let (audioFile, audioURL) = makeBookmarkedAudioFile(displayName: "audio.mp3")
    defer { try? FileManager.default.removeItem(at: audioURL) }

    await manager.load(audioFile: audioFile)
    await manager.play()

    #expect(manager.isSleepPreventionActiveForTest == false)
  }

  @Test
  func testPauseReleasesSleepPreventionForVideoPlayback() async {
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)
    let settings = PlayerSettings()
    settings.preventSleep = true
    manager.playerSettings = settings

    let (videoFile, videoURL) = makeBookmarkedAudioFile(displayName: "video.mp4")
    defer { try? FileManager.default.removeItem(at: videoURL) }

    await manager.load(audioFile: videoFile)
    await manager.play()
    #expect(manager.isSleepPreventionActiveForTest == true)

    await manager.pause()

    #expect(manager.isSleepPreventionActiveForTest == false)
  }

  @Test
  func testLoadResetsSleepPreventionImmediately() async {
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)
    let settings = PlayerSettings()
    settings.preventSleep = true
    manager.playerSettings = settings

    let (videoFile, videoURL) = makeBookmarkedAudioFile(displayName: "video.mp4")
    defer { try? FileManager.default.removeItem(at: videoURL) }
    let (audioFile, audioURL) = makeBookmarkedAudioFile(displayName: "audio.mp3")
    defer { try? FileManager.default.removeItem(at: audioURL) }

    await manager.load(audioFile: videoFile)
    await manager.play()
    #expect(manager.isSleepPreventionActiveForTest == true)

    await manager.load(audioFile: audioFile)

    #expect(manager.isPlaying == false)
    #expect(manager.isSleepPreventionActiveForTest == false)
  }

  @Test
  func testSwitchingFileResetsPlayingState() async {
    // Given
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)

    // Setup dummy file A
    let (fileA, fileAURL) = makeBookmarkedAudioFile(displayName: "A.mp3")
    defer { try? FileManager.default.removeItem(at: fileAURL) }

    // Begin playing file A (manually set state since logic handles UI update immediately)
    // We simulate "play" has happened
    await manager.load(audioFile: fileA)
    manager.isPlaying = true

    // Verify playing state
    #expect(manager.isPlaying == true)

    // When: Loading file B
    let (fileB, fileBURL) = makeBookmarkedAudioFile(displayName: "B.mp3")
    defer { try? FileManager.default.removeItem(at: fileBURL) }
    await manager.load(audioFile: fileB)

    // Then: Manager should have stopped playing immediately upon load starts
    // Manager.load sets isPlaying = false at the beginning
    #expect(manager.isPlaying == false)
    #expect(manager.currentFile?.displayName == "B")
  }

  @Test
  func testCurrentFileUpdatesCorrectly() async {
    // Given
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)

    let (fileA, fileAURL) = makeBookmarkedAudioFile(displayName: "A.mp3")
    defer { try? FileManager.default.removeItem(at: fileAURL) }
    let (fileB, fileBURL) = makeBookmarkedAudioFile(displayName: "B.mp3")
    defer { try? FileManager.default.removeItem(at: fileBURL) }

    // When: Switch A -> B
    await manager.load(audioFile: fileA)
    #expect(manager.currentFile?.displayName == "A")

    await manager.load(audioFile: fileB)

    // Then
    #expect(manager.currentFile?.displayName == "B")

    // Verify Engine was called twice
    let callCount = await mockEngine.loadCallCount
    #expect(callCount == 2)
  }

  @Test
  func testLoadCallsAreSerialized() async {
    // Given: Slow engine
    let mockEngine = MockAudioPlayerEngine()
    // 100ms delay
    await mockEngine.setDelay(100_000_000)

    let manager = makePlayerManager(engine: mockEngine)
    let (fileA, fileAURL) = makeBookmarkedAudioFile(displayName: "A.mp3")
    defer { try? FileManager.default.removeItem(at: fileAURL) }
    let (fileB, fileBURL) = makeBookmarkedAudioFile(displayName: "B.mp3")
    defer { try? FileManager.default.removeItem(at: fileBURL) }

    // When: Call load A then load B immediately
    // We use Task to launch them potentially concurrently, but Manager is MainActor protected.
    // However, the awaiting of engine inside Manager.load is suspension point.

    await manager.load(audioFile: fileA)
    await manager.load(audioFile: fileB)

    // Since we await'ed them sequentially, they ran sequentially.
    // The critical part is that state is correct at the end.

    #expect(manager.currentFile?.displayName == "B")

    let lastFileURL = await mockEngine.lastLoadedFileURL
    #expect(lastFileURL?.lastPathComponent == fileB.relativePath)
  }

  @Test
  func testTogglePlayPauseWhilePlayingCallsPauseReference() async {
    // Given: Playing
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)
    manager.isPlaying = true

    // When: Toggle
    await manager.togglePlayPause()

    // Then: State updates immediately
    #expect(manager.isPlaying == false)

    // Verify sync pause was NOT called immediately on main actor?
    // Wait, manager calls _player?.pause() synchronously (if valid).
    // And calls await _engine.syncPauseState() in background.
    // We can't easily test the background task timing here without expectations,
    // but we can check the state is false.
  }

  @Test
  func testPlayWithoutCurrentFileDoesNotStartPlayback() async {
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)

    await manager.play()

    #expect(manager.isPlaying == false)
    let playCount = await mockEngine.playCallCount
    #expect(playCount == 0)
  }

  @Test
  func testTogglePlayPauseWithoutCurrentFileDoesNothing() async {
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)

    await manager.togglePlayPause()

    #expect(manager.isPlaying == false)
    let playCount = await mockEngine.playCallCount
    #expect(playCount == 0)
  }

  @Test
  func testRapidFileSwitchingCancelsOldLoad() async {
    // Given
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)
    // Set a delay to simulate async loading
    await mockEngine.setDelay(50_000_000)  // 50ms

    let (fileA, fileAURL) = makeBookmarkedAudioFile(displayName: "A.mp3")
    defer { try? FileManager.default.removeItem(at: fileAURL) }
    let (fileB, fileBURL) = makeBookmarkedAudioFile(displayName: "B.mp3")
    defer { try? FileManager.default.removeItem(at: fileBURL) }

    // When: Start loading A, then immediately load B
    // We launch them in parallel tasks but they will hit the actor sequentially or concurrently depending on scheduling,
    // but the Manager's State (loadingFileID) is MainActor protected and will be updated immediately.

    // Task 1: Load A
    Task {
      await manager.load(audioFile: fileA)
    }

    // Small yield to ensure Task 1 starts but hits the delay
    try? await Task.sleep(nanoseconds: 10_000_000)

    // Task 2: Load B
    await manager.load(audioFile: fileB)

    // Then: Manager should reflect file B
    #expect(manager.currentFile?.displayName == "B")

    // Wait for everything to settle
    try? await Task.sleep(nanoseconds: 100_000_000)

    // Verify that even after A 'finishes' (in background), the manager state is still B
    #expect(manager.currentFile?.displayName == "B")
    #expect(manager.duration != 0)  // Should have loaded duration for B
  }

  @Test
  func testLoadDoesNotDependOnBookmarkData() async throws {
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)

    let librarySettings = manager.librarySettings
    let relativePath = "library-only.mp3"
    let mediaURL = librarySettings.libraryDirectoryURL.appendingPathComponent(relativePath)
    try Data("audio".utf8).write(to: mediaURL)
    defer { try? FileManager.default.removeItem(at: mediaURL) }

    let file = ABFile(
      displayName: "library-only.mp3",
      bookmarkData: Data(),
      relativePath: relativePath
    )

    await manager.load(audioFile: file)

    let loadedURL = await mockEngine.lastLoadedFileURL
    #expect(loadedURL?.lastPathComponent == "library-only.mp3")
  }

  @Test
  func testSeekToPreviousSubtitleSentenceSeeksToPreviousCueStart() async {
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)
    manager.currentTime = 2.3

    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 1.0, text: "First"),
      SubtitleCue(startTime: 2.0, endTime: 3.0, text: "Second"),
      SubtitleCue(startTime: 4.0, endTime: 5.0, text: "Third"),
    ]

    await manager.seekToPreviousSubtitleSentence(in: cues)

    let seekCallCount = await mockEngine.seekCallCount
    let lastSeekTime = await mockEngine.lastSeekTime
    #expect(seekCallCount == 1)
    #expect(lastSeekTime == 0.001)
  }

  @Test
  func testSeekToNextSubtitleSentenceSeeksToNextCueStart() async {
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)
    manager.currentTime = 2.3

    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 1.0, text: "First"),
      SubtitleCue(startTime: 2.0, endTime: 3.0, text: "Second"),
      SubtitleCue(startTime: 4.0, endTime: 5.0, text: "Third"),
    ]

    await manager.seekToNextSubtitleSentence(in: cues)

    let seekCallCount = await mockEngine.seekCallCount
    let lastSeekTime = await mockEngine.lastSeekTime
    #expect(seekCallCount == 1)
    #expect(lastSeekTime == 4.001)
  }

  @Test
  func testSeekToNextSubtitleSentenceWithEmptyCuesDoesNothing() async {
    let mockEngine = MockAudioPlayerEngine()
    let manager = makePlayerManager(engine: mockEngine)
    manager.currentTime = 2.3

    await manager.seekToNextSubtitleSentence(in: [])

    let seekCallCount = await mockEngine.seekCallCount
    #expect(seekCallCount == 0)
  }
}

extension MockAudioPlayerEngine {
  func setDelay(_ delay: UInt64) {
    self.loadDelay = delay
  }
}

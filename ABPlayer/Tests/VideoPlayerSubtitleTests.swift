import Foundation
import Testing

@testable import ABPlayerDev

@MainActor
struct VideoPlayerSubtitleStateTests {
  @Test
  func subtitleToggleDoesNothingWhenNoCues() {
    let viewModel = VideoPlayerViewModel()

    #expect(viewModel.hasAvailableSubtitles == false)
    viewModel.toggleSubtitle()
    #expect(viewModel.isSubtitleEnabled == false)
    #expect(viewModel.currentSubtitleText == nil)
  }

  @Test
  func subtitleShowsCurrentCueWhenEnabled() {
    let viewModel = VideoPlayerViewModel()
    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 2.0, text: "Hello"),
      SubtitleCue(startTime: 2.0, endTime: 4.0, text: "World"),
    ]

    viewModel.updateSubtitleCues(cues)
    viewModel.toggleSubtitle()
    viewModel.updateCurrentSubtitle(at: 2.5)

    #expect(viewModel.isSubtitleEnabled)
    #expect(viewModel.currentSubtitleText == "World")
  }

  @Test
  func subtitleOverlayIsNilBetweenCues() {
    let viewModel = VideoPlayerViewModel()
    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 1.0, text: "Hello"),
      SubtitleCue(startTime: 2.0, endTime: 3.0, text: "World"),
    ]

    viewModel.updateSubtitleCues(cues)
    viewModel.toggleSubtitle()
    viewModel.updateCurrentSubtitle(at: 1.5)

    #expect(viewModel.currentSubtitleText == nil)
  }

  @Test
  func subtitleEnabledPreservedAcrossReload() {
    let viewModel = VideoPlayerViewModel()
    let cues = [SubtitleCue(startTime: 0.0, endTime: 2.0, text: "First")]

    viewModel.updateSubtitleCues(cues)
    viewModel.toggleSubtitle()
    #expect(viewModel.isSubtitleEnabled)

    viewModel.beginSubtitleReload()
    // isSubtitleEnabled stays true so it auto-restores when cues arrive
    #expect(viewModel.isSubtitleEnabled)

    viewModel.updateSubtitleCues(cues)
    #expect(viewModel.isSubtitleEnabled)
  }

  @Test
  func subtitleTextUpdatesWhenCuesChange() {
    let viewModel = VideoPlayerViewModel()
    let cueID = UUID()

    viewModel.updateSubtitleCues([
      SubtitleCue(id: cueID, startTime: 0.0, endTime: 2.0, text: "Original"),
    ])
    viewModel.toggleSubtitle()
    viewModel.updateCurrentSubtitle(at: 0.5)
    #expect(viewModel.currentSubtitleText == "Original")

    viewModel.updateSubtitleCues([
      SubtitleCue(id: cueID, startTime: 0.0, endTime: 2.0, text: "Updated"),
    ])

    #expect(viewModel.currentSubtitleText == "Updated")
  }
}

@MainActor
struct SubtitleLoaderSyncTests {
  @Test
  func updateSubtitleRefreshesCacheAndRevision() async throws {
    let (audioFile, audioURL, librarySettings, libraryRoot) = try makeManagedLibraryAudioFile(
      displayName: "subtitle-sync.mp3"
    )
    let subtitleLoader = SubtitleLoader(librarySettings: librarySettings)
    let srtURL = audioURL.deletingPathExtension().appendingPathExtension("srt")

    defer {
      try? FileManager.default.removeItem(at: libraryRoot)
    }

    let originalSRT = [
      "1",
      "00:00:00,000 --> 00:00:02,000",
      "Original",
      "",
      "2",
      "00:00:02,000 --> 00:00:04,000",
      "Line 2",
      "",
    ].joined(separator: "\n")
    try originalSRT.write(to: srtURL, atomically: true, encoding: .utf8)

    let loaded = await subtitleLoader.loadSubtitles(for: audioFile)
    #expect(loaded.count == 2)
    #expect(loaded[0].text == "Original")

    let oldRevision = subtitleLoader.revisionMap[audioFile.id, default: 0]

    let updated = await subtitleLoader.updateSubtitle(
      for: audioFile,
      cueID: loaded[0].id,
      subtitle: "Updated"
    )

    #expect(updated?.count == 2)
    #expect(updated?[0].text == "Updated")
    #expect(subtitleLoader.cachedSubtitles(for: audioFile.id).first?.text == "Updated")
    #expect(subtitleLoader.revisionMap[audioFile.id, default: 0] == oldRevision + 1)

    let reloaded = await subtitleLoader.loadSubtitles(for: audioFile)
    #expect(reloaded.first?.text == "Updated")
  }
}

@MainActor
private func makeManagedLibraryAudioFile(displayName: String) throws -> (ABFile, URL, LibrarySettings, URL)
{
  let libraryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("SubtitleLoaderSyncTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

  let relativePath = "\(UUID().uuidString)-\(displayName)"
  let fileURL = libraryRoot.appendingPathComponent(relativePath)

  try Data("audio".utf8).write(to: fileURL)

  let librarySettings = LibrarySettings()
  librarySettings.libraryPath = libraryRoot.path

  let audioFile = ABFile(
    displayName: displayName,
    bookmarkData: Data(),
    relativePath: relativePath
  )

  return (audioFile, fileURL, librarySettings, libraryRoot)
}

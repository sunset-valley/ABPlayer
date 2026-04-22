import SwiftData
import SwiftUI

@MainActor
struct VideoTapPlaybackDemoView: View {
  @State private var librarySettings: LibrarySettings
  @State private var subtitleLoader: SubtitleLoader
  @State private var playerManager: PlayerManager
  @State private var sessionTracker: SessionTracker
  @State private var audioFile: ABFile?
  @State private var didSetup = false
  @State private var hasSetupError = false
  @State private var interactionMonitor = VideoTapInteractionMonitor()

  init() {
    let dependencies = Self.makeDependencies()

    _librarySettings = State(initialValue: dependencies.librarySettings)
    _subtitleLoader = State(initialValue: dependencies.subtitleLoader)
    let manager = PlayerManager(librarySettings: dependencies.librarySettings, engine: MockPlayerEngine())
    manager.sessionTracker = dependencies.sessionTracker

    _playerManager = State(initialValue: manager)
    _sessionTracker = State(initialValue: dependencies.sessionTracker)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Video Tap Playback Demo")
        .font(.title2)
        .accessibilityIdentifier("video-tap-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-video-tap-playback")
        .font(.caption)
        .foregroundStyle(.secondary)

      statusPanel

      if hasSetupError {
        Text("Failed to prepare demo media")
          .foregroundStyle(.red)
      }

      if let audioFile {
        VideoPlayerView(audioFile: audioFile, interactionMonitor: interactionMonitor)
          .environment(playerManager)
          .environment(sessionTracker)
          .environment(subtitleLoader)
      } else {
        Text("Preparing demo files...")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(16)
    .frame(minWidth: 1100, minHeight: 720)
    .task {
      guard !didSetup else { return }
      didSetup = true
      await setupDemoFile()
    }
  }

  private var statusPanel: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("playback: \(playerManager.isPlaying ? "playing" : "paused")")
        .font(.caption.monospaced())
        .accessibilityIdentifier("video-tap-playback-state")

      Text("fullscreen: \(interactionMonitor.isFullscreenPresented ? "presented" : "dismissed")")
        .font(.caption.monospaced())
        .accessibilityIdentifier("video-tap-fullscreen-state")

      Text("feedback-count: \(interactionMonitor.immediateFeedbackCount)")
        .font(.caption.monospaced())
        .accessibilityIdentifier("video-tap-feedback-count")
    }
  }

  private func setupDemoFile() async {
    do {
      let file = try makeDemoFile(baseName: "video-tap-playback-demo")
      audioFile = file
      _ = await subtitleLoader.loadSubtitles(for: file)
      await playerManager.selectFile(file, fromStart: true, debounce: false)
    } catch {
      hasSetupError = true
    }
  }

  private func makeDemoFile(baseName: String) throws -> ABFile {
    let relativePath = "ui-testing/\(baseName).mp4"
    let mediaURL = librarySettings.libraryDirectoryURL
      .appendingPathComponent(relativePath)

    try FileManager.default.createDirectory(
      at: mediaURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    if !FileManager.default.fileExists(atPath: mediaURL.path) {
      FileManager.default.createFile(atPath: mediaURL.path, contents: Data())
    }

    let srtURL = mediaURL.deletingPathExtension().appendingPathExtension("srt")
    if !FileManager.default.fileExists(atPath: srtURL.path) {
      let srtContent = [
        "1",
        "00:00:00,000 --> 00:00:03,000",
        "Demo subtitle line",
        "",
      ].joined(separator: "\n")
      try srtContent.write(to: srtURL, atomically: true, encoding: .utf8)
    }

    return ABFile(displayName: "\(baseName).mp4", bookmarkData: Data(), relativePath: relativePath)
  }

  private static func makeDependencies() -> (
    librarySettings: LibrarySettings,
    subtitleLoader: SubtitleLoader,
    sessionTracker: SessionTracker
  ) {
    let librarySettings = LibrarySettings()
    let subtitleLoader = SubtitleLoader(librarySettings: librarySettings)
    let sessionTracker = SessionTracker(modelContainer: makeInMemoryModelContainer())
    return (librarySettings, subtitleLoader, sessionTracker)
  }

  private static func makeInMemoryModelContainer() -> ModelContainer {
    let schema = Schema([
      ABFile.self,
      LoopSegment.self,
      ListeningSession.self,
      PlaybackRecord.self,
      Folder.self,
      SubtitleFile.self,
      Transcription.self,
      Vocabulary.self,
      AnnotationStylePreset.self,
      TextAnnotationGroup.self,
      TextAnnotationSpan.self,
      TextAnnotationGroupV2.self,
      TextAnnotationSpanV2.self,
      NoteCollection.self,
      Note.self,
      NoteEntry.self,
      NoteAnnotationLink.self,
    ])

    do {
      return try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
      )
    } catch {
      fatalError("Failed to create in-memory model container for video tap playback demo: \(error)")
    }
  }
}

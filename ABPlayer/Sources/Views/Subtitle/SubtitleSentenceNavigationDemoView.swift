import SwiftUI

@MainActor
struct SubtitleSentenceNavigationDemoView: View {
  @Environment(PlayerManager.self) private var playerManager
  @Environment(SubtitleLoader.self) private var subtitleLoader
  @Environment(LibrarySettings.self) private var librarySettings

  @State private var demoFile: ABFile?
  @State private var didSetup = false
  @State private var hasSetupError = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Subtitle Sentence Navigation Demo")
        .font(.title2)
        .accessibilityIdentifier("subtitle-sentence-nav-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-subtitle-sentence-navigation")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 16) {
        metric(
          "currentTime",
          value: String(format: "%.3f", playerManager.currentTime),
          id: "subtitle-sentence-nav-current-time"
        )
        metric(
          "activeCue",
          value: activeCueLabel,
          id: "subtitle-sentence-nav-active-cue"
        )
      }
      .font(.caption.monospacedDigit())

      HStack(spacing: 10) {
        Button("Seek to 2.5") {
          Task {
            await playerManager.seek(to: 2.5)
          }
        }
        .accessibilityIdentifier("subtitle-sentence-nav-seed-second")

        Button("Seek to 1.5") {
          Task {
            await playerManager.seek(to: 1.5)
          }
        }
        .accessibilityIdentifier("subtitle-sentence-nav-seed-gap")
      }
      .buttonStyle(.bordered)

      if hasSetupError {
        Text("Failed to prepare demo media")
          .foregroundStyle(.red)
      }

      if let demoFile {
        AudioPlayerView(audioFile: demoFile)
      } else {
        Text("Preparing demo files...")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(16)
    .frame(minWidth: 1100, minHeight: 760)
    .task {
      guard !didSetup else { return }
      didSetup = true
      await setupDemoFile()
    }
  }

  private var demoCues: [SubtitleCue] {
    subtitleLoader.cachedSubtitles(for: demoFile?.id ?? UUID())
  }

  private var activeCueLabel: String {
    guard let index = demoCues.activeCueIndex(at: playerManager.currentTime) else {
      return "nil"
    }
    return String(index + 1)
  }

  @ViewBuilder
  private func metric(_ title: String, value: String, id: String) -> some View {
    Text("\(title): \(value)")
      .accessibilityIdentifier(id)
  }

  private func setupDemoFile() async {
    do {
      let file = try makeDemoFile()
      demoFile = file
      _ = await subtitleLoader.loadSubtitles(for: file)
      await playerManager.selectFile(file, fromStart: true, debounce: false)
      await playerManager.seek(to: 2.5)
    } catch {
      hasSetupError = true
    }
  }

  private func makeDemoFile() throws -> ABFile {
    let relativePath = "ui-testing/subtitle-sentence-navigation-demo.mp3"
    let mediaURL = librarySettings.libraryDirectoryURL
      .appendingPathComponent(relativePath)

    try FileManager.default.createDirectory(
      at: mediaURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    if !FileManager.default.fileExists(atPath: mediaURL.path) {
      let emptyData = Data()
      FileManager.default.createFile(atPath: mediaURL.path, contents: emptyData)
    }

    let srtURL = mediaURL.deletingPathExtension().appendingPathExtension("srt")
    let srtContent = [
      "1",
      "00:00:00,000 --> 00:00:01,000",
      "First sentence",
      "",
      "2",
      "00:00:02,000 --> 00:00:03,000",
      "Second sentence",
      "",
      "3",
      "00:00:04,000 --> 00:00:05,000",
      "Third sentence",
      "",
    ].joined(separator: "\n")
    try srtContent.write(to: srtURL, atomically: true, encoding: .utf8)

    return ABFile(
      displayName: "subtitle-sentence-navigation-demo.mp3",
      bookmarkData: Data(),
      relativePath: relativePath
    )
  }
}

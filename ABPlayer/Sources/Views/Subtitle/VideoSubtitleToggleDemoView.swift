import SwiftUI

@MainActor
struct VideoSubtitleToggleDemoView: View {
  @Environment(SubtitleLoader.self) private var subtitleLoader
  @Environment(PlayerManager.self) private var playerManager

  @State private var withSubtitleFile: ABFile?
  @State private var withoutSubtitleFile: ABFile?
  @State private var didSetup = false
  @State private var hasSetupError = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Video Subtitle Toggle Demo")
        .font(.title2)
        .accessibilityIdentifier("video-subtitle-toggle-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-video-subtitle-toggle")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 10) {
        Button("Load with subtitle") {
          guard let withSubtitleFile else { return }
          Task {
            await playerManager.selectFile(withSubtitleFile, fromStart: true, debounce: false)
          }
        }
        .accessibilityIdentifier("video-subtitle-demo-load-with")

        Button("Load without subtitle") {
          guard let withoutSubtitleFile else { return }
          Task {
            await playerManager.selectFile(withoutSubtitleFile, fromStart: true, debounce: false)
          }
        }
        .accessibilityIdentifier("video-subtitle-demo-load-without")
      }
      .buttonStyle(.bordered)

      if hasSetupError {
        Text("Failed to prepare demo media")
          .foregroundStyle(.red)
      }

      if let currentFile = playerManager.currentFile {
        VideoPlayerView(audioFile: currentFile)
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
      await setupDemoFiles()
    }
  }

  private func setupDemoFiles() async {
    do {
      let withSubtitle = try makeDemoFile(baseName: "video-subtitle-toggle-with", writeSubtitle: true)
      let withoutSubtitle = try makeDemoFile(baseName: "video-subtitle-toggle-without", writeSubtitle: false)

      withSubtitleFile = withSubtitle
      withoutSubtitleFile = withoutSubtitle

      _ = await subtitleLoader.loadSubtitles(for: withSubtitle)
      _ = await subtitleLoader.loadSubtitles(for: withoutSubtitle)
      await playerManager.selectFile(withSubtitle, fromStart: true, debounce: false)
    } catch {
      hasSetupError = true
    }
  }

  private func makeDemoFile(baseName: String, writeSubtitle: Bool) throws -> ABFile {
    let mediaURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(baseName)
      .appendingPathExtension("mp4")

    if !FileManager.default.fileExists(atPath: mediaURL.path) {
      let emptyData = Data()
      FileManager.default.createFile(atPath: mediaURL.path, contents: emptyData)
    }

    let srtURL = mediaURL.deletingPathExtension().appendingPathExtension("srt")

    if writeSubtitle {
      let srtContent = [
        "1",
        "00:00:00,000 --> 00:00:03,000",
        "Demo subtitle line",
        "",
      ].joined(separator: "\n")
      try srtContent.write(to: srtURL, atomically: true, encoding: .utf8)
    } else if FileManager.default.fileExists(atPath: srtURL.path) {
      try FileManager.default.removeItem(at: srtURL)
    }

    let bookmarkData = try mediaURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    return ABFile(displayName: "\(baseName).mp4", bookmarkData: bookmarkData)
  }
}

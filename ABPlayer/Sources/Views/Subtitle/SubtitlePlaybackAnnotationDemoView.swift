import SwiftUI

@MainActor
struct SubtitlePlaybackAnnotationDemoView: View {
  @Environment(AnnotationService.self) private var annotationService
  @Environment(AnnotationStyleService.self) private var annotationStyleService
  @Environment(TranscriptionSettings.self) private var transcriptionSettings

  @State private var playerManager = PlayerManager(engine: MockPlayerEngine())
  @State private var cues: [SubtitleCue] = Self.demoCues
  @State private var didSetup = false
  @State private var activeCueID: UUID?

  private static let audioFileID = UUID(uuidString: "00000000-0000-0000-0000-00000000BEEF") ?? UUID()

  private static let demoCues: [SubtitleCue] = [
    SubtitleCue(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000101") ?? UUID(),
      startTime: 0,
      endTime: 2,
      text: "First cue line for regression testing"
    ),
    SubtitleCue(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000102") ?? UUID(),
      startTime: 2,
      endTime: 4,
      text: "Second cue should become active"
    ),
    SubtitleCue(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000103") ?? UUID(),
      startTime: 4,
      endTime: 6,
      text: "Third cue verifies follow keeps advancing"
    ),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Subtitle Playback + Annotation Demo")
        .font(.title2)
        .accessibilityIdentifier("subtitle-playback-annotation-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-subtitle-playback-annotation")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 12) {
        Text("active: \(activeCueLabel)")
          .accessibilityIdentifier("subtitle-playback-active-cue")

        Text("following: \(isFollowingPlayback ? "true" : "false")")
          .accessibilityIdentifier("subtitle-playback-following")
      }
      .font(.caption.monospaced())

      Button("Apply Annotation + Resume") {
        Task {
          await applyAnnotationAndResume()
        }
      }
      .accessibilityIdentifier("subtitle-playback-apply-annotation")

      SubtitleView(
        cues: cues,
        fontSize: 16,
        onEditSubtitle: { cueID, subtitle in
          guard let index = cues.firstIndex(where: { $0.id == cueID }) else { return }
          let cue = cues[index]
          cues[index] = SubtitleCue(id: cue.id, startTime: cue.startTime, endTime: cue.endTime, text: subtitle)
        },
        onActiveCueChanged: { cueID in
          activeCueID = cueID
        }
      )
      .environment(playerManager)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier("subtitle-playback-annotation-demo-subtitle-view")
    }
    .padding(16)
    .frame(minWidth: 980, minHeight: 640)
    .task {
      guard !didSetup else { return }
      didSetup = true
      await setupDemoState()
    }
  }

  private var activeCueLabel: String {
    guard let activeCueID,
      let index = cues.firstIndex(where: { $0.id == activeCueID })
    else {
      return "nil"
    }
    return "\(index + 1)"
  }

  private var isFollowingPlayback: Bool {
    playerManager.isPlaying && activeCueID != nil
  }

  private func setupDemoState() async {
    transcriptionSettings.pauseOnWordDismiss = false

    let audioFile = try? makeAudioFile()
    guard let audioFile else { return }

    seedDemoAnnotationIfNeeded(audioFileID: audioFile.id)

    await playerManager.load(audioFile: audioFile, fromStart: true)
    await playerManager.play()
  }

  private func makeAudioFile() throws -> ABFile {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("abplayer-ui-subtitle-annotation-audio")
      .appendingPathExtension("m4a")

    if !FileManager.default.fileExists(atPath: fileURL.path) {
      let emptyData = Data()
      FileManager.default.createFile(atPath: fileURL.path, contents: emptyData)
    }

    let bookmarkData = try fileURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    let audioFile = ABFile(
      id: Self.audioFileID,
      displayName: "subtitle-playback-annotation-demo.m4a",
      bookmarkData: bookmarkData
    )
    return audioFile
  }

  private func seedDemoAnnotationIfNeeded(audioFileID: UUID) {
    let targetCue = cues[0]
    let existing = annotationService.annotations(for: targetCue.id)
    if !existing.isEmpty {
      return
    }

    guard let styleID = annotationStyleService.allStyles().first?.id else { return }

    let selection = CrossCueTextSelection(
      segments: [
        .init(
          cueID: targetCue.id,
          cueStartTime: targetCue.startTime,
          cueEndTime: targetCue.endTime,
          localRange: NSRange(location: 0, length: 5),
          text: "First"
        )
      ],
      fullText: "First",
      globalRange: NSRange(location: 0, length: 5)
    )

    _ = annotationService.addAnnotation(
      audioFileID: audioFileID,
      selection: selection,
      stylePresetID: styleID
    )
  }

  private func applyAnnotationAndResume() async {
    guard let audioFileID = playerManager.currentFile?.id else { return }
    let targetCue = cues[0]

    if annotationService.annotations(for: targetCue.id).isEmpty,
      let styleID = annotationStyleService.allStyles().first?.id
    {
      let selection = CrossCueTextSelection(
        segments: [
          .init(
            cueID: targetCue.id,
            cueStartTime: targetCue.startTime,
            cueEndTime: targetCue.endTime,
            localRange: NSRange(location: 0, length: 5),
            text: "First"
          )
        ],
        fullText: "First",
        globalRange: NSRange(location: 0, length: 5)
      )

      _ = annotationService.addAnnotation(
        audioFileID: audioFileID,
        selection: selection,
        stylePresetID: styleID
      )
    }

    await playerManager.pause()
    guard !transcriptionSettings.pauseOnWordDismiss else { return }
    await playerManager.play()
  }
}

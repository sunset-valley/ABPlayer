import SwiftUI

@MainActor
struct SubtitlePlaybackAnnotationDemoView: View {
  @Environment(AnnotationService.self) private var annotationService
  @Environment(AnnotationStyleService.self) private var annotationStyleService
  @Environment(TranscriptionSettings.self) private var transcriptionSettings
  @Environment(LibrarySettings.self) private var librarySettings

  @State private var playerManager = PlayerManager(librarySettings: LibrarySettings(), engine: MockPlayerEngine())
  @State private var cues: [SubtitleCue] = Self.demoCues
  @State private var didSetup = false
  @State private var activeCueID: UUID?

  private static let audioFileID = UUID(uuidString: "00000000-0000-0000-0000-00000000BEEF") ?? UUID()

  private static let demoCues: [SubtitleCue] = makeDemoCues()

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

    clearDemoAnnotations()

    await playerManager.load(audioFile: audioFile, fromStart: true)
    await playerManager.play()
  }

  private func makeAudioFile() throws -> ABFile {
    let relativePath = "ui-testing/subtitle-playback-annotation-audio.m4a"
    let fileURL = librarySettings.libraryDirectoryURL
      .appendingPathComponent(relativePath)

    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    if !FileManager.default.fileExists(atPath: fileURL.path) {
      let emptyData = Data()
      FileManager.default.createFile(atPath: fileURL.path, contents: emptyData)
    }

    let audioFile = ABFile(
      id: Self.audioFileID,
      displayName: "subtitle-playback-annotation-demo.m4a",
      bookmarkData: Data(),
      relativePath: relativePath
    )
    return audioFile
  }
}

extension SubtitlePlaybackAnnotationDemoView {
  private func clearDemoAnnotations() {
    for cue in cues {
      let groups = Set(annotationService.annotations(for: cue.id).map(\.groupID))
      for groupID in groups {
        annotationService.removeAnnotationGroup(groupID: groupID)
      }
    }
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

  private static func makeDemoCues() -> [SubtitleCue] {
    (0..<120).map { index in
      let start = Double(index) * 2.0
      let end = start + 1.8
      return SubtitleCue(
        id: SubtitleCue.generateDeterministicID(
          audioFileID: audioFileID,
          cueIndex: index,
          startTime: start,
          endTime: end
        ),
        startTime: start,
        endTime: end,
        text: "Cue \(index + 1): Subtitle playback annotation regression line for manual-scroll follow-mode testing."
      )
    }
  }
}

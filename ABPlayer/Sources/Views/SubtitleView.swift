import OSLog
import SwiftData
import SwiftUI

struct SubtitleView: View {
  @Environment(PlayerManager.self) private var playerManager
  @Environment(VocabularyService.self) private var vocabularyService
  @Environment(TranscriptionSettings.self) private var transcriptionSettings

  let cues: [SubtitleCue]
  @Binding var countdownSeconds: Int?
  let fontSize: Double
  let onEditSubtitle: (UUID, String) -> Void

  @State private var viewModel = SubtitleViewModel(playerManager: nil)

  private var playbackTrackingID: String {
    let fileID = playerManager.currentFile?.id.uuidString ?? "nil"
    let firstCueID = cues.first?.id.uuidString ?? "nil"
    let lastCueID = cues.last?.id.uuidString ?? "nil"
    return "\(playerManager.isPlaying)-\(fileID)-\(cues.count)-\(firstCueID)-\(lastCueID)"
  }

  var body: some View {
    let output = viewModel.output

    ZStack(alignment: .topTrailing) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(cues) { cue in
                SubtitleCueRow(
                  cue: cue,
                  isActive: cue.id == output.currentCueID,
                  isScrolling: output.scrollState.isUserScrolling,
                  fontSize: fontSize,
                  selectedWordIndex: output.selectedWord?.cueID == cue.id
                    ? output.selectedWord?.wordIndex
                    : nil,
                  onWordSelected: { wordIndex in
                    Task {
                      await viewModel.perform(
                        action: .handleWordSelection(
                          wordIndex: wordIndex,
                          cueID: cue.id,
                          isPlaying: playerManager.isPlaying,
                          onPause: pausePlayback,
                          onPlay: playPlayback
                        )
                      )
                    }
                  },
                  onTap: {
                    Task {
                      await viewModel.perform(
                        action: .handleCueTap(
                          cueID: cue.id,
                          cueStartTime: cue.startTime
                        )
                      )
                    }
                  },
                  onEditSubtitle: onEditSubtitle
                )
              .id(cue.id)
            }
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
        }
        .transaction { $0.animation = nil }
        .onScrollPhaseChange { _, newPhase in
          handleScrollPhaseChange(newPhase)
        }
        .onChange(of: viewModel.currentCueID) { _, newCueID in
          guard !viewModel.scrollState.isUserScrolling, let id = newCueID else { return }
          Logger.ui.info("[currentCueID] \(id.uuidString)")
          withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(id, anchor: .center)
          }
        }
        .onChange(of: cues) { _, _ in
          Task {
            await viewModel.perform(action: .reset)
          }
        }
      }

      VStack(alignment: .trailing, spacing: 8) {
        if let countdown = output.countdown {
          CountdownRingView(countdown: countdown, total: 3)
            .transition(.scale.combined(with: .opacity))
        }
      }
      .padding(12)
    }
    .animation(.easeInOut(duration: 0.2), value: output.countdown != nil)
    .task(id: playbackTrackingID) {
      await viewModel.perform(action: .setPlayerManager(playerManager))

      await withTaskCancellationHandler {
        await viewModel.perform(action: .trackPlayback(cues: cues))
      } onCancel: {
        Task { @MainActor in
          await viewModel.perform(action: .stopTrackingPlayback)
        }
      }
    }
    .onChange(of: viewModel.scrollState.countdown) { _, newValue in
      countdownSeconds = newValue
    }
  }

  private func handleScrollPhaseChange(_ phase: ScrollPhase) {
    guard case .interacting = phase else { return }
    Task {
      await viewModel.perform(action: .handleUserScroll)
    }
  }

  private func pausePlayback() {
    Task {
      await playerManager.pause()
    }
  }

  private func playPlayback() {
    guard !transcriptionSettings.pauseOnWordDismiss else { return }
    Task {
      await playerManager.play()
    }
  }

}

struct SubtitleEmptyView: View {
  var body: some View {
    ContentUnavailableView(
      "No Subtitles",
      systemImage: "text.bubble",
      description: Text("This audio file has no associated subtitle file")
    )
  }
}

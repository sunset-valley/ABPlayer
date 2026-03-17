import AVKit
import Observation
import OSLog
import SwiftData
import SwiftUI

// MARK: - Video Player View

struct VideoPlayerView: View {
  @Environment(PlayerManager.self) private var playerManager
  @Environment(SessionTracker.self) private var sessionTracker
  @Environment(\.modelContext) private var modelContext

  @Bindable var audioFile: ABFile

  @State private var viewModel = VideoPlayerViewModel()
  @State private var fullscreenPresenter = VideoFullscreenPresenter()
  @State private var pendingSingleTap: Task<Void, Never>?

  var body: some View {
    videoPlayerSection
      .focusEffectDisabled()
      .task {
        viewModel.setup(with: playerManager)
        if playerManager.currentFile?.id != audioFile.id,
           playerManager.currentFile != nil
        {
          await playerManager.selectFile(audioFile, fromStart: false, debounce: false)
        }
      }
      .onChange(of: audioFile) { _, newFile in
        Task {
          if playerManager.currentFile?.id != newFile.id {
            await playerManager.selectFile(newFile, fromStart: false, debounce: false)
          }
        }
      }
  }

  // MARK: - Components

  private var videoPlayerSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      // 1. Video Player Area
      ZStack {
        Group {
          if let player = playerManager.player {
            NativeVideoPlayer(player: player)
          } else {
            ZStack {
              Color.black
              ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            }
          }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .layoutPriority(1)

        if let message = viewModel.hudMessage {
          Text(message)
            .font(.title)
            .padding(.all, 16)
            .background(.black.opacity(0.6))
            .foregroundStyle(.white)
            .cornerRadius(8)
            .id(message)
            .opacity(viewModel.isHudVisible ? 1 : 0)
            .scaleEffect(viewModel.isHudVisible ? 1 : 0.5)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture(count: 2) {
        pendingSingleTap?.cancel()
        guard let player = playerManager.player else { return }
        fullscreenPresenter.toggle(player: player, playerManager: playerManager, onSingleTap: viewModel.togglePlayPause)
      }
      .onTapGesture(count: 1) {
        pendingSingleTap?.cancel()
        pendingSingleTap = Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(300))
          guard !Task.isCancelled else { return }
          viewModel.togglePlayPause()
        }
      }

      // 2. Controls Area (Fixed height)
      VStack(spacing: 12) {
        VideoProgressView(
          isSeeking: $viewModel.isSeeking,
          seekValue: $viewModel.seekValue,
          wasPlayingBeforeSeek: $viewModel.wasPlayingBeforeSeek
        )

        VideoControlsView(
          viewModel: viewModel,
          isFullscreen: fullscreenPresenter.isPresented,
          onToggleFullscreen: {
            guard let player = playerManager.player else { return }
            fullscreenPresenter.toggle(player: player, playerManager: playerManager, onSingleTap: viewModel.togglePlayPause)
          }
        )
        .padding(.horizontal)

        Text(audioFile.displayName)
          .font(.title)
          .fontWeight(.semibold)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
      }
    }
  }
}

import SwiftUI
import Observation

struct VideoControlsView: View {
  @Bindable var viewModel: VideoPlayerViewModel
  @Environment(PlayerManager.self) private var playerManager

  var isFullscreen: Bool = false
  var onToggleFullscreen: (() -> Void)? = nil
  
  var body: some View {
    ZStack(alignment: .center) {
      HStack {
        VideoTimeDisplay(isSeeking: viewModel.isSeeking, seekValue: viewModel.seekValue)
        
        Spacer()
        
        HStack {
          loopModeMenu

          Button {
            viewModel.toggleSubtitle()
          } label: {
            Image(.closedCaption).renderingMode(.template).resizable().aspectRatio(contentMode: .fit).frame(width: 24)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("video-controls-subtitle-toggle")
          .disabled(!viewModel.hasAvailableSubtitles)
          .opacity(viewModel.hasAvailableSubtitles ? 1.0 : 0.45)
          .foregroundStyle(
            viewModel.hasAvailableSubtitles
              ? (viewModel.isSubtitleEnabled ? Color.accentColor : .primary)
              : .secondary
          )
          .help(viewModel.hasAvailableSubtitles ? "Toggle subtitles" : "No subtitles available / 没有可用字幕")
          
          if let onToggleFullscreen {
            Button(action: onToggleFullscreen) {
              Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.title2)
            }
            .buttonStyle(.plain)
            .help(isFullscreen ? "Exit fullscreen" : "Enter fullscreen")
          }

          VolumeControl(playerVolume: $viewModel.playerVolume)
        }
      }

      // Playback Controls
      playbackControls
    }
  }
  
  private var loopModeMenu: some View {
    Menu {
      ForEach(PlaybackQueue.LoopMode.allCases, id: \.self) { mode in
        Button {
          viewModel.updateLoopMode(mode)
        } label: {
          HStack {
            Image(systemName: mode.iconName)
            Text(mode.displayName)
          }
        }
      }
    } label: {
      Image(
        systemName: playerManager.loopMode != .none
          ? "\(playerManager.loopMode.iconName)"
          : "repeat"
      )
      .font(.title2)
      .foregroundStyle(playerManager.loopMode != .none ? Color.accentColor : .primary)
    }
    .buttonStyle(.plain)
    .help("Loop mode: \(playerManager.loopMode.displayName)")
  }
  
  private var playbackControls: some View {
    HStack(spacing: 16) {
      Button {
        Task {
          await playerManager.playPrev()
        }
      } label: {
        Image(systemName: "backward.end")
          .font(.title)
      }
      .buttonStyle(.plain)
      
      Button {
        viewModel.seekBack()
      } label: {
        Image(systemName: "gobackward.5")
          .font(.title)
      }
      .buttonStyle(.plain)
      .keyboardShortcut("f", modifiers: [])

      Button {
        viewModel.togglePlayPause()
      } label: {
        Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 36))
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.space, modifiers: [])

      Button {
        viewModel.seekForward()
      } label: {
        Image(systemName: "goforward.10")
          .font(.title)
      }
      .buttonStyle(.plain)
      .keyboardShortcut("g", modifiers: [])

      Button {
        Task {
          await playerManager.playNext()
        }
      } label: {
        Image(systemName: "forward.end")
          .font(.title)
      }
      .buttonStyle(.plain)
    }
  }
}

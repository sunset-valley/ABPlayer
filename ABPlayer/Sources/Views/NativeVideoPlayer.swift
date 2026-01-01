import AVFoundation
import AVKit
import SwiftUI

#if os(macOS)
  /// A simple wrapper around AVPlayerView that hides all native controls.
  struct NativeVideoPlayer: NSViewRepresentable {
    weak var player: AVPlayer?

    func makeNSView(context: Context) -> TrackAVPlayerView {
      let view = TrackAVPlayerView()
      view.player = player
      view.controlsStyle = .none  // Hides all native controls (volume, cast, timeline)
      view.videoGravity = .resizeAspect
      return view
    }

    func updateNSView(_ nsView: TrackAVPlayerView, context: Context) {
      if nsView.player != player {
        nsView.player = player
      }
    }

    static func dismantleNSView(_ nsView: TrackAVPlayerView, coordinator: ()) {
      let playerDesc = nsView.player.map { "\(Unmanaged.passUnretained($0).toOpaque())" } ?? "nil"
      print("[NativeVideoPlayer] dismantleNSView player: \(playerDesc)")
    }
  }

  /// A subclass of AVPlayerView that logs when it's initialized and deallocated
  final class TrackAVPlayerView: AVPlayerView {
    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      print("[TrackAVPlayerView] 🆕 Created - Address: \(Unmanaged.passUnretained(self).toOpaque())")
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      print(
        "[TrackAVPlayerView] 🆕 Created (coder) - Address: \(Unmanaged.passUnretained(self).toOpaque())"
      )
    }

    deinit {
      print(
        "[TrackAVPlayerView] 💀 DEINIT - View deallocated: \(Unmanaged.passUnretained(self).toOpaque())"
      )
    }
  }

#endif

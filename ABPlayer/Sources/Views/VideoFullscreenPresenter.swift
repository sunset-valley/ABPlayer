import AVKit
import SwiftUI

// MARK: - Fullscreen Window

private final class FullscreenWindow: NSWindow {
  var onEscape: (() -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {  // ESC
      onEscape?()
    } else {
      super.keyDown(with: event)
    }
  }
}

// MARK: - Presenter

@Observable
@MainActor
final class VideoFullscreenPresenter {
  private var window: FullscreenWindow?

  private(set) var isPresented: Bool = false

  func toggle(
    playerManager: PlayerManager,
    subtitleText: @escaping @MainActor () -> String?,
    onSingleTap: @escaping () -> Void
  ) {
    if isPresented {
      dismiss()
    } else {
      present(playerManager: playerManager, subtitleText: subtitleText, onSingleTap: onSingleTap)
    }
  }

  private func present(
    playerManager: PlayerManager,
    subtitleText: @escaping @MainActor () -> String?,
    onSingleTap: @escaping () -> Void
  ) {
    guard let screen = NSScreen.main else { return }

    let w = FullscreenWindow(
      contentRect: screen.frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    w.level = .screenSaver
    w.backgroundColor = .black
    w.isMovable = false
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let content = FullscreenVideoContent(
      playerManager: playerManager,
      subtitleText: subtitleText,
      onSingleTap: onSingleTap,
      onDismiss: { [weak self] in self?.dismiss() }
    )
    w.contentView = NSHostingView(rootView: content)
    w.onEscape = { [weak self] in self?.dismiss() }
    w.makeKeyAndOrderFront(nil)

    self.window = w
    isPresented = true
  }

  func dismiss() {
    window?.orderOut(nil)
    window = nil
    isPresented = false
  }
}

// MARK: - Fullscreen Content View

private struct FullscreenVideoContent: View {
  let playerManager: PlayerManager
  let subtitleText: @MainActor () -> String?
  let onSingleTap: () -> Void
  let onDismiss: () -> Void

  @State private var pendingSingleTap: Task<Void, Never>?
  @State private var hudSymbol: String?
  @State private var isHudVisible: Bool = false
  @State private var hudTask: Task<Void, Never>?

  var body: some View {
    ZStack {
      Color.black
      if let player = playerManager.player {
        NativeVideoPlayer(player: player)
      }

      if let text = subtitleText() {
        VStack {
          Spacer()
          VideoSubtitleOverlay(text: text)
            .padding(.horizontal, 28)
            .padding(.bottom, 34)
        }
      }

      hudOverlay
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
      pendingSingleTap?.cancel()
      onDismiss()
    }
    .onTapGesture(count: 1) {
      pendingSingleTap?.cancel()
      pendingSingleTap = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        showHUD(playerManager.isPlaying ? "pause.fill" : "play.fill")
        onSingleTap()
      }
    }
  }

  @ViewBuilder
  private var hudOverlay: some View {
    if let symbol = hudSymbol {
      Image(systemName: symbol)
        .font(.system(size: 64, weight: .regular))
        .foregroundStyle(.white)
        .padding(32)
        .background(.black.opacity(0.5))
        .clipShape(Circle())
        .id(symbol)
        .opacity(isHudVisible ? 1 : 0)
        .scaleEffect(isHudVisible ? 1 : 0.6)
    }
  }

  private func showHUD(_ symbol: String) {
    hudTask?.cancel()
    hudSymbol = symbol
    isHudVisible = false

    hudTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(10))
      guard !Task.isCancelled else { return }

      withAnimation(.spring(duration: 0.2)) { isHudVisible = true }

      try? await Task.sleep(for: .milliseconds(800))
      guard !Task.isCancelled else { return }

      withAnimation(.easeOut(duration: 0.3)) { isHudVisible = false }

      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }

      hudSymbol = nil
    }
  }
}

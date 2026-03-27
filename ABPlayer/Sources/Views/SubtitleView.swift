import OSLog
import SwiftData
import SwiftUI

/// Renders all subtitle cues in a single scrollable `TranscriptTextView`
/// (one `NSTextView` for the whole transcript) enabling cross-cue selection.
struct SubtitleView: View {
  @Environment(PlayerManager.self) private var playerManager
  @Environment(AnnotationService.self) private var annotationService
  @Environment(AnnotationStyleService.self) private var annotationStyleService
  @Environment(TranscriptionSettings.self) private var transcriptionSettings

  let cues: [SubtitleCue]
  let fontSize: Double
  let onEditSubtitle: (UUID, String) -> Void
  let onScrollMetricsChanged: (TranscriptTextView.ScrollMetrics) -> Void

  init(
    cues: [SubtitleCue],
    fontSize: Double,
    onEditSubtitle: @escaping (UUID, String) -> Void,
    onScrollMetricsChanged: @escaping (TranscriptTextView.ScrollMetrics) -> Void = { _ in }
  ) {
    self.cues = cues
    self.fontSize = fontSize
    self.onEditSubtitle = onEditSubtitle
    self.onScrollMetricsChanged = onScrollMetricsChanged
  }

  @State private var viewModel = SubtitleViewModel(playerManager: nil)

  // Edit-subtitle sheet state
  @State private var editingCueID: UUID?

  // Comment-editor sheet state (opened from annotation menu)
  @State private var isShowingCommentEditor = false
  @State private var commentEditingAnnotation: AnnotationRenderData?
  @State private var popoverAnchors: TranscriptTextView.PopoverAnchors?
  @State private var popoverContentSize: CGSize = .zero

  private var playbackTrackingID: String {
    let fileID = playerManager.currentFile?.id.uuidString ?? "nil"
    let firstCueID = cues.first?.id.uuidString ?? "nil"
    let lastCueID = cues.last?.id.uuidString ?? "nil"
    return "\(playerManager.isPlaying)-\(fileID)-\(cues.count)-\(firstCueID)-\(lastCueID)"
  }

  // MARK: - Body

  var body: some View {
    let output = viewModel.output

    ZStack(alignment: .topTrailing) {
      TranscriptTextView(
        cues: cues,
        fontSize: fontSize,
        activeCueID: output.currentCueID,
        isUserScrolling: output.scrollState.isUserScrolling,
        textSelection: output.textSelection,
        annotationVersion: annotationService.version + annotationStyleService.version,
        annotationsProvider: { annotationService.annotations(for: $0) },
        onSelectionChanged: { selection in
          viewModel.handleTextSelection(
            selection: selection,
            isPlaying: playerManager.isPlaying,
            onPause: { Task { await playerManager.pause() } },
            onPlay: { Task { await playerManager.play() } }
          )
        },
        onPopoverAnchorChanged: { anchors in
          popoverAnchors = anchors
        },
        onAnnotationTapped: { groupID, selection, _ in
          viewModel.selectAnnotation(
            groupID: groupID,
            selection: selection,
            isPlaying: playerManager.isPlaying,
            onPause: { Task { await playerManager.pause() } }
          )
        },
        onCueTap: { cueID, startTime in
          Task {
            await viewModel.handleCueTap(cueID: cueID, cueStartTime: startTime)
          }
        },
        onUserScrolled: {
          Task { @MainActor in
            viewModel.handleUserScroll()
            dismissPopoverSelection()
          }
        },
        onEditSubtitleRequested: { cueID in
          editingCueID = cueID
        },
        onScrollMetricsChanged: onScrollMetricsChanged
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay(alignment: .topLeading) {
        GeometryReader { geometry in
          let layout = resolvedPopoverLayout(in: geometry.size)

          ZStack(alignment: .topLeading) {
            if output.textSelection.isActive {
              Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismissPopoverSelection() }
            }

            if output.textSelection.isActive,
              let layout
            {
              let frame = layout.frame
              let panelBackground = Color(nsColor: .windowBackgroundColor).opacity(0.97)

              popoverContent(output: output)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 340, alignment: .leading)
                .background {
                  GeometryReader { proxy in
                    Color.clear
                      .onAppear { popoverContentSize = proxy.size }
                      .onChange(of: proxy.size) { _, newSize in
                        popoverContentSize = newSize
                      }
                  }
                }
                .background(
                  RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(panelBackground)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 8)
                .offset(x: frame.minX, y: frame.minY)
            }

#if DEBUG
            if let layout {
              Circle()
                .fill(.red.opacity(0.85))
                .frame(width: 7, height: 7)
                .position(layout.anchor)
            }
#endif
          }
        }
      }

      // Follow-playback button
      if output.scrollState.isUserScrolling {
        Button {
          Task { viewModel.cancelScrollResume() }
        } label: {
          Label("跟随播放", systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .padding(12)
        .transition(.scale.combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.2), value: output.scrollState.isUserScrolling)
    // Playback tracking
    .task(id: playbackTrackingID) {
      viewModel.setPlayerManager(playerManager)

      await withTaskCancellationHandler {
        await viewModel.trackPlayback(cues: cues)
      } onCancel: {
        Task { @MainActor in
          viewModel.stopTrackingPlayback()
        }
      }
    }
    // Reset when cues change (new file / re-transcription)
    .onChange(of: cues) { _, _ in
      Task { viewModel.reset() }
    }
    .onChange(of: output.textSelection) { _, newSelection in
      guard !newSelection.isActive else { return }
      popoverAnchors = nil
      isShowingCommentEditor = false
      commentEditingAnnotation = nil
    }
    // Edit subtitle sheet
    .sheet(
      isPresented: Binding(
        get: { editingCueID != nil },
        set: { isPresented in
          if !isPresented {
            editingCueID = nil
          }
        }
      )
    ) {
      if let cueID = editingCueID,
        let cue = cues.first(where: { $0.id == cueID })
      {
        SubtitleEditView(subtitle: cue.text) { newSubtitle in
          onEditSubtitle(cueID, newSubtitle)
        }
      }
    }
  }

  // MARK: - Popover content

  @ViewBuilder
  private func popoverContent(output: SubtitleViewModel.Output) -> some View {
    if isShowingCommentEditor, let annotation = commentEditingAnnotation {
      CommentEditorView(
        existingComment: annotation.comment,
        onSave: { comment in
          annotationService.updateComment(groupID: annotation.groupID, comment: comment)
          dismissPopoverSelection()
        },
        onCancel: {
          isShowingCommentEditor = false
          commentEditingAnnotation = nil
        }
      )
    } else {
      let selectedText = selectedTextForPopover(output: output)
      let existingAnnotation = existingAnnotationForPopover(output: output)

      AnnotationMenuView(
        selectedText: selectedText,
        existingAnnotation: existingAnnotation,
        styles: annotationStyleService.allStyles(),
        onAnnotate: { styleID in
          createAnnotation(from: output.textSelection, stylePresetID: styleID)
        },
        onEditComment: {
          if let annotation = existingAnnotation {
            commentEditingAnnotation = annotation
            isShowingCommentEditor = true
          }
        },
        onChangeStyle: { styleID in
          if let annotation = existingAnnotation {
            annotationService.updateStyle(groupID: annotation.groupID, stylePresetID: styleID)
          }
        },
        onDelete: {
          if let annotation = existingAnnotation {
            annotationService.removeAnnotationGroup(groupID: annotation.groupID)
          }
        },
        onLookup: {},
        onCopy: {
          let text = selectedText
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        },
        onDismiss: {
          dismissPopoverSelection()
        }
      )
    }
  }

  // MARK: - Popover helpers

  private func selectedTextForPopover(output: SubtitleViewModel.Output) -> String {
    switch output.textSelection {
    case .none:
      return ""
    case let .selecting(selection):
      return selection.fullText
    case let .annotationSelected(_, selection):
      return selection.fullText
    }
  }

  private func existingAnnotationForPopover(
    output: SubtitleViewModel.Output
  ) -> AnnotationRenderData? {
    if case let .annotationSelected(groupID, _) = output.textSelection {
      return annotationService.annotations(inGroup: groupID).first
    }
    return nil
  }

  /// Create one annotation per cue segment (supports cross-cue selections).
  private func createAnnotation(
    from state: SubtitleViewModel.TextSelectionState,
    stylePresetID: UUID
  ) {
    guard case let .selecting(selection) = state else { return }
    guard let audioFileID = playerManager.currentFile?.id else { return }
    _ = annotationService.addAnnotation(
      audioFileID: audioFileID,
      selection: selection,
      stylePresetID: stylePresetID
    )
  }

  private func dismissPopoverSelection() {
    viewModel.dismissSelection(onPlay: {
      guard !transcriptionSettings.pauseOnWordDismiss else { return }
      Task { await playerManager.play() }
    })
    popoverAnchors = nil
    isShowingCommentEditor = false
    commentEditingAnnotation = nil
  }

  private func clampedPopoverAnchors(in size: CGSize) -> TranscriptTextView.PopoverAnchors? {
    guard let anchors = popoverAnchors else { return nil }
    func clamp(_ point: CGPoint) -> CGPoint {
      let x = min(max(point.x, 0), max(0, size.width - 1))
      let y = min(max(point.y, 0), max(0, size.height - 1))
      return CGPoint(x: x, y: y)
    }
    return TranscriptTextView.PopoverAnchors(
      bottom: clamp(anchors.bottom),
      top: clamp(anchors.top)
    )
  }

  private func resolvedPopoverLayout(in size: CGSize) -> (
    anchor: CGPoint,
    frame: (minX: CGFloat, minY: CGFloat, width: CGFloat, flipsAboveAnchor: Bool)
  )? {
    guard let anchors = clampedPopoverAnchors(in: size) else { return nil }

    let provisionalFrame = popoverFrame(for: anchors.bottom, in: size)
    let useTopAnchor = provisionalFrame.flipsAboveAnchor
    let anchor = useTopAnchor ? anchors.top : anchors.bottom
    let frame = popoverFrame(for: anchor, in: size, forceAbove: useTopAnchor ? true : nil)
    return (anchor, frame)
  }

  private func popoverFrame(
    for anchor: CGPoint,
    in containerSize: CGSize,
    forceAbove: Bool? = nil
  ) -> (
    minX: CGFloat, minY: CGFloat, width: CGFloat, flipsAboveAnchor: Bool
  ) {
    let margin: CGFloat = 10
    let gap: CGFloat = 12
    let maxUsableWidth = max(260, min(440, containerSize.width - margin * 2))
    let width = min(max(popoverContentSize.width, 320), maxUsableWidth)
    let height = max(popoverContentSize.height, 180)

    let preferredX = anchor.x - width / 2
    let minX = min(max(preferredX, margin), max(margin, containerSize.width - width - margin))

    let belowY = anchor.y + gap
    let aboveY = anchor.y - gap - height
    let canShowAbove = aboveY >= margin
    let canShowBelow = belowY + height <= containerSize.height - margin
    let showAbove: Bool
    if let forceAbove {
      showAbove = forceAbove
    } else {
      // Prefer below; only flip above when it fits above but not below.
      showAbove = canShowAbove && !canShowBelow
    }
    let minY = showAbove
      ? max(aboveY, margin)
      : anchor.y + gap

    return (minX, minY, width, showAbove)
  }

}

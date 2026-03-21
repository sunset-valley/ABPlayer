import OSLog
import SwiftData
import SwiftUI

/// Renders all subtitle cues in a single scrollable `TranscriptTextView`
/// (one `NSTextView` for the whole transcript) enabling cross-cue selection.
struct SubtitleView: View {
  @Environment(PlayerManager.self) private var playerManager
  @Environment(AnnotationService.self) private var annotationService
  @Environment(TranscriptionSettings.self) private var transcriptionSettings

  let cues: [SubtitleCue]
  let fontSize: Double
  let onEditSubtitle: (UUID, String) -> Void

  @State private var viewModel = SubtitleViewModel(playerManager: nil)

  // Edit-subtitle sheet state
  @State private var editingCueID: UUID?
  @State private var isShowingEditSheet = false

  // Comment-editor sheet state (opened from annotation menu)
  @State private var isShowingCommentEditor = false
  @State private var commentEditingAnnotation: AnnotationDisplayData?

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
        colorConfig: .default,
        annotationVersion: annotationService.version,
        annotationsProvider: { annotationService.annotations(for: $0) },
        onSelectionChanged: { selection in
          Task {
            await viewModel.perform(
              action: .handleTextSelection(
                selection: selection,
                isPlaying: playerManager.isPlaying,
                onPause: { Task { await playerManager.pause() } },
                onPlay: { Task { await playerManager.play() } }
              )
            )
          }
        },
        onAnnotationTapped: { cueID, annotation in
          viewModel.selectAnnotation(
            cueID: cueID,
            annotationID: annotation.id,
            isPlaying: playerManager.isPlaying,
            onPause: { Task { await playerManager.pause() } }
          )
        },
        onCueTap: { cueID, startTime in
          Task {
            await viewModel.perform(
              action: .handleCueTap(cueID: cueID, cueStartTime: startTime)
            )
          }
        },
        onUserScrolled: {
          Task { await viewModel.perform(action: .handleUserScroll) }
        },
        onEditSubtitleRequested: { cueID in
          editingCueID = cueID
          isShowingEditSheet = true
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // Annotation / selection popover
      .popover(
        isPresented: Binding(
          get: { output.textSelection.isActive },
          set: { presented in
            if !presented {
              viewModel.dismissSelection(onPlay: {
                guard !transcriptionSettings.pauseOnWordDismiss else { return }
                Task { await playerManager.play() }
              })
              isShowingCommentEditor = false
              commentEditingAnnotation = nil
            }
          }
        ),
        arrowEdge: .bottom
      ) {
        popoverContent(output: output)
      }

      // Follow-playback button
      if output.scrollState.isUserScrolling {
        Button {
          Task { await viewModel.perform(action: .cancelScrollResume) }
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
      await viewModel.perform(action: .setPlayerManager(playerManager))

      await withTaskCancellationHandler {
        await viewModel.perform(action: .trackPlayback(cues: cues))
      } onCancel: {
        Task { @MainActor in
          await viewModel.perform(action: .stopTrackingPlayback)
        }
      }
    }
    // Reset when cues change (new file / re-transcription)
    .onChange(of: cues) { _, _ in
      Task { await viewModel.perform(action: .reset) }
    }
    // Edit subtitle sheet
    .sheet(isPresented: $isShowingEditSheet) {
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
          annotationService.updateComment(annotationID: annotation.id, comment: comment)
          isShowingCommentEditor = false
          commentEditingAnnotation = nil
          viewModel.dismissSelection(onPlay: {
            guard !transcriptionSettings.pauseOnWordDismiss else { return }
            Task { await playerManager.play() }
          })
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
        onAnnotate: { type in
          createAnnotation(from: output.textSelection, type: type)
        },
        onEditComment: {
          if let annotation = existingAnnotation {
            commentEditingAnnotation = annotation
            isShowingCommentEditor = true
          }
        },
        onChangeType: { type in
          if let annotation = existingAnnotation {
            annotationService.updateType(annotationID: annotation.id, type: type)
          }
        },
        onDelete: {
          if let annotation = existingAnnotation {
            annotationService.removeAnnotation(id: annotation.id)
          }
        },
        onLookup: {},
        onCopy: {
          let text = selectedText
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        },
        onDismiss: {
          viewModel.dismissSelection(onPlay: {
            guard !transcriptionSettings.pauseOnWordDismiss else { return }
            Task { await playerManager.play() }
          })
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
    case let .annotationSelected(cueID, annotationID):
      return annotationService.annotations(for: cueID)
        .first { $0.id == annotationID }?.selectedText ?? ""
    }
  }

  private func existingAnnotationForPopover(
    output: SubtitleViewModel.Output
  ) -> AnnotationDisplayData? {
    if case let .annotationSelected(cueID, annotationID) = output.textSelection {
      return annotationService.annotations(for: cueID).first { $0.id == annotationID }
    }
    return nil
  }

  /// Create one annotation per cue segment (supports cross-cue selections).
  private func createAnnotation(
    from state: SubtitleViewModel.TextSelectionState,
    type: AnnotationType
  ) {
    guard case let .selecting(selection) = state else { return }
    for segment in selection.segments {
      annotationService.addAnnotation(
        cueID: segment.cueID,
        range: segment.localRange,
        selectedText: segment.text,
        type: type
      )
    }
  }
}

import SwiftData
import SwiftUI

/// View for transcription display and controls
struct TranscriptionView: View {
  enum UITestScenario {
    case loadingCache
    case empty
    case downloading
    case loadingModel
    case extractingAudio
    case transcribing
    case failed
    case content
    case queued
    case queueDownloading
    case queueLoading
    case queueExtractingAudio
    case queueTranscribing
    case queueFailed
  }

  private enum StateActionStyle {
    case bordered
    case prominent
  }

  private struct StateAction {
    let id: String
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let style: StateActionStyle
    let handler: () -> Void
  }

  let audioFile: ABFile
  private let uiTestScenario: UITestScenario?
  private let uiTestCues: [SubtitleCue]

  @Environment(TranscriptionManager.self) private var transcriptionManager
  @Environment(TranscriptionQueueManager.self) private var queueManager
  @Environment(TranscriptionSettings.self) private var settings
  @Environment(SubtitleLoader.self) private var subtitleLoader
  @Environment(\.modelContext) private var modelContext

  @State private var viewModel = TranscriptionViewModel()
  @State private var demoSubtitleFontSize: Double = 16

  init(
    audioFile: ABFile,
    uiTestScenario: UITestScenario? = nil,
    uiTestCues: [SubtitleCue] = []
  ) {
    self.audioFile = audioFile
    self.uiTestScenario = uiTestScenario
    self.uiTestCues = uiTestCues
  }

  var body: some View {
    Group {
      if let uiTestScenario {
        uiTestScenarioView(uiTestScenario)
      } else {
        liveView
      }
    }
    .task(id: audioFile.id) {
      guard uiTestScenario == nil else { return }
      viewModel.setup(
        audioFile: audioFile,
        transcriptionManager: transcriptionManager,
        queueManager: queueManager,
        modelContext: modelContext,
        subtitleLoader: subtitleLoader
      )
    }
  }

  @ViewBuilder
  private var liveView: some View {
    if let task = viewModel.currentTask {
      taskProgressView(task: task)
    } else {
      switch transcriptionManager.state {
      case .unavailable:
        loadingCacheView

      case .idle:
        if viewModel.isLoadingCache {
          loadingCacheView
        } else if viewModel.cachedCues.isEmpty && viewModel.hasCheckedCache {
          noTranscriptionView
        } else if !viewModel.cachedCues.isEmpty {
          transcriptionContentView
        } else {
          loadingCacheView
        }

      case let .downloading(progress, modelName):
        downloadingView(progress: progress, modelName: modelName)

      case let .loading(modelName):
        loadingModelView(modelName: modelName)

      case let .extractingAudio(progress, fileName):
        extractingAudioView(progress: progress, fileName: fileName)

      case let .transcribing(progress, fileName):
        transcribingView(progress: progress, fileName: fileName)

      case .completed:
        if !viewModel.cachedCues.isEmpty {
          transcriptionContentView
        } else {
          loadingCacheView
        }

      case let .failed(error):
        failedView(error: error)

      case .cancelled:
        if !viewModel.cachedCues.isEmpty {
          transcriptionContentView
        } else if viewModel.hasCheckedCache {
          noTranscriptionView
        } else {
          loadingCacheView
        }
      }
    }
  }

  // MARK: - UI Test Scenarios

  @ViewBuilder
  private func uiTestScenarioView(_ scenario: UITestScenario) -> some View {
    switch scenario {
    case .loadingCache:
      loadingCacheView
    case .empty:
      noTranscriptionView
    case .downloading:
      stateView(
        icon: "arrow.down.circle",
        title: "Downloading Model",
        subtitle: "distil-large-v3",
        progress: 0.45,
        showPercentage: true,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {}
        )
      )
    case .loadingModel:
      loadingModelView(modelName: "distil-large-v3")
    case .extractingAudio:
      extractingAudioView(progress: 0.42, fileName: "UI Test Audio")
    case .transcribing:
      transcribingView(progress: 0.68, fileName: "UI Test Audio")
    case .failed:
      stateView(
        icon: "exclamationmark.triangle",
        title: "Transcription Failed",
        subtitle: "Mock transcription failure for UI test",
        progress: nil,
        showPercentage: false,
        footnote: nil,
        showsIndeterminateProgress: false,
        iconSize: 48,
        iconColor: .orange,
        animateIcon: false,
        subtitleLineLimit: nil,
        subtitleMaxWidth: 320,
        action: StateAction(
          id: "transcription-retry-button",
          title: "Retry",
          systemImage: "arrow.clockwise",
          role: nil,
          style: .prominent,
          handler: {}
        )
      )
    case .content:
      transcriptionContentView(
        cues: uiTestCues,
        fontSize: $demoSubtitleFontSize,
        onRetranscribe: {},
        onEditSubtitle: { _, _ in }
      )
    case .queued:
      stateView(
        icon: "clock",
        title: "Queued",
        subtitle: "UI Test Audio",
        progress: nil,
        showPercentage: false,
        footnote: "Waiting for other transcriptions to complete",
        showsIndeterminateProgress: true
      )
    case .queueDownloading:
      stateView(
        icon: "arrow.down.circle",
        title: "Downloading Model",
        subtitle: "distil-large-v3",
        progress: 0.57,
        showPercentage: true,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {}
        )
      )
    case .queueLoading:
      stateView(
        icon: "brain",
        title: "Loading Model",
        subtitle: "distil-large-v3",
        progress: nil,
        showPercentage: false,
        footnote: "This may take a moment on first run",
        showsIndeterminateProgress: true,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {}
        )
      )
    case .queueExtractingAudio:
      stateView(
        icon: "waveform.and.mic",
        title: "Extracting Audio",
        subtitle: "UI Test Audio",
        progress: 0.33,
        showPercentage: true,
        footnote: "Converting video to audio format",
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {}
        )
      )
    case .queueTranscribing:
      stateView(
        icon: "waveform",
        title: "Transcribing",
        subtitle: "UI Test Audio",
        progress: 0.74,
        showPercentage: true,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {}
        )
      )
    case .queueFailed:
      stateView(
        icon: "exclamationmark.triangle",
        title: "Transcription Failed",
        subtitle: "Mock queue transcription failure",
        progress: nil,
        showPercentage: false,
        footnote: nil,
        showsIndeterminateProgress: false,
        iconSize: 48,
        iconColor: .orange,
        animateIcon: false,
        subtitleLineLimit: nil,
        subtitleMaxWidth: 320,
        action: StateAction(
          id: "transcription-retry-button",
          title: "Retry",
          systemImage: "arrow.clockwise",
          role: nil,
          style: .prominent,
          handler: {}
        )
      )
    }
  }

  // MARK: - Content View

  private var transcriptionContentView: some View {
    transcriptionContentView(
      cues: viewModel.cachedCues,
      fontSize: Binding(
        get: { viewModel.subtitleFontSize },
        set: { viewModel.subtitleFontSize = $0 }
      ),
      onRetranscribe: {
        Task {
          await viewModel.clearAndRetranscribe()
        }
      },
      onEditSubtitle: { cueID, subtitle in
        Task {
          await viewModel.updateSubtitle(cueID: cueID, subtitle: subtitle)
        }
      }
    )
  }

  private func transcriptionContentView(
    cues: [SubtitleCue],
    fontSize: Binding<Double>,
    onRetranscribe: @escaping () -> Void,
    onEditSubtitle: @escaping (UUID, String) -> Void
  ) -> some View {
    VStack(spacing: 0) {
      HStack {
        Button(action: onRetranscribe) {
          HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
            Text("Re-transcribe")
          }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("transcription-retranscribe-button")

        Spacer()

        HStack(spacing: 0) {
          ForEach([("Small", 14.0), ("Medium", 16.0), ("Large", 18.0)], id: \.0) { label, size in
            Button {
              fontSize.wrappedValue = size
            } label: {
              Text(label)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(
              fontSize.wrappedValue == size ? Color.accentColor : Color.secondary.opacity(0.15)
            )
            .foregroundStyle(fontSize.wrappedValue == size ? .white : .secondary)
            .accessibilityIdentifier(fontSizeIdentifier(for: label))
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .accessibilityIdentifier("transcription-content-toolbar")

      Divider()

      SubtitleView(
        cues: cues,
        fontSize: fontSize.wrappedValue,
        onEditSubtitle: onEditSubtitle
      )
      .accessibilityIdentifier("transcription-subtitle-content")
    }
  }

  private func fontSizeIdentifier(for label: String) -> String {
    switch label {
    case "Small":
      return "transcription-font-size-small"
    case "Medium":
      return "transcription-font-size-medium"
    case "Large":
      return "transcription-font-size-large"
    default:
      return "transcription-font-size-unknown"
    }
  }

  // MARK: - Loading and Empty State

  private var loadingCacheView: some View {
    stateView(
      icon: "clock.arrow.circlepath",
      title: "Checking Cache",
      subtitle: "Checking cache...",
      progress: nil,
      showPercentage: false,
      showsIndeterminateProgress: true,
      iconColor: .secondary,
      animateIcon: false
    )
  }

  private var noTranscriptionView: some View {
    stateView(
      icon: "text.bubble",
      title: "No Transcription",
      subtitle: "Generate subtitles with on-device speech recognition",
      progress: nil,
      showPercentage: false,
      footnote:
      "If you are transcribing English-only audio or video, we recommend Distil Large v3 in Settings. For other languages, use Large v3. If auto-detection is not accurate, choose the language manually in Settings.",
      showsIndeterminateProgress: false,
      iconSize: 56,
      iconColor: Color.secondary.opacity(0.5),
      animateIcon: false,
      subtitleLineLimit: nil,
      subtitleMaxWidth: 320,
      action: StateAction(
        id: "transcription-primary-action",
        title: "Transcribe Audio",
        systemImage: "waveform",
        role: nil,
        style: .prominent,
        handler: {
          viewModel.startTranscription()
        }
      )
    )
  }

  // MARK: - Progress Views

  private func downloadingView(progress: Double, modelName: String) -> some View {
    stateView(
      icon: "arrow.down.circle",
      title: "Downloading Model",
      subtitle: modelName,
      progress: progress,
      showPercentage: true,
      action: StateAction(
        id: "transcription-cancel-button",
        title: "Cancel",
        systemImage: nil,
        role: nil,
        style: .bordered,
        handler: {
          transcriptionManager.cancelDownload()
          transcriptionManager.cancelTranscription()
          settings.deleteDownloadCache(modelName: modelName)
        }
      )
    )
  }

  private func loadingModelView(modelName: String) -> some View {
    stateView(
      icon: "brain",
      title: "Loading Model",
      subtitle: modelName,
      progress: nil,
      showPercentage: false,
      footnote: "This may take a moment on first run",
      showsIndeterminateProgress: true,
      animateIcon: true
    )
  }

  private func extractingAudioView(progress: Double, fileName: String) -> some View {
    stateView(
      icon: "waveform.and.mic",
      title: "Extracting Audio",
      subtitle: fileName,
      progress: progress > 0 ? progress : nil,
      showPercentage: progress > 0,
      footnote: "Converting video to audio format",
      showsIndeterminateProgress: progress <= 0
    )
  }

  private func transcribingView(progress: Double, fileName: String) -> some View {
    stateView(
      icon: "waveform",
      title: "Transcribing",
      subtitle: fileName,
      progress: progress > 0 ? progress : nil,
      showPercentage: progress > 0,
      showsIndeterminateProgress: progress <= 0
    )
  }

  /// View for queue task progress
  @ViewBuilder
  private func taskProgressView(task: TranscriptionTask) -> some View {
    switch task.status {
    case .queued:
      stateView(
        icon: "clock",
        title: "Queued",
        subtitle: task.audioFileName,
        progress: nil,
        showPercentage: false,
        footnote: "Waiting for other transcriptions to complete",
        showsIndeterminateProgress: true
      )

    case .checkingExistingSubtitles:
      stateView(
        icon: "magnifyingglass",
        title: "Checking Subtitles",
        subtitle: task.audioFileName,
        progress: nil,
        showPercentage: false,
        footnote: "Looking for existing subtitle files",
        showsIndeterminateProgress: true,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {
            queueManager.cancelTask(id: task.id)
          }
        )
      )

    case .loadingExistingSubtitles:
      stateView(
        icon: "text.bubble",
        title: "Loading Subtitles",
        subtitle: task.audioFileName,
        progress: nil,
        showPercentage: false,
        showsIndeterminateProgress: true,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {
            queueManager.cancelTask(id: task.id)
          }
        )
      )

    case let .downloading(progress):
      stateView(
        icon: "arrow.down.circle",
        title: "Downloading Model",
        subtitle: settings.modelName,
        progress: progress,
        showPercentage: true,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {
            queueManager.cancelTask(id: task.id)
          }
        )
      )

    case .loading:
      stateView(
        icon: "brain",
        title: "Loading Model",
        subtitle: settings.modelName,
        progress: nil,
        showPercentage: false,
        footnote: "This may take a moment on first run",
        showsIndeterminateProgress: true,
        animateIcon: true,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {
            queueManager.cancelTask(id: task.id)
          }
        )
      )

    case let .extractingAudio(progress):
      stateView(
        icon: "waveform.and.mic",
        title: "Extracting Audio",
        subtitle: task.audioFileName,
        progress: progress > 0 ? progress : nil,
        showPercentage: progress > 0,
        footnote: "Converting video to audio format",
        showsIndeterminateProgress: progress <= 0,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {
            queueManager.cancelTask(id: task.id)
          }
        )
      )

    case let .transcribing(progress):
      stateView(
        icon: "waveform",
        title: "Transcribing",
        subtitle: task.audioFileName,
        progress: progress > 0 ? progress : nil,
        showPercentage: progress > 0,
        showsIndeterminateProgress: progress <= 0,
        animateIcon: false,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {
            queueManager.cancelTask(id: task.id)
          }
        )
      )

    case .savingSubtitles:
      stateView(
        icon: "square.and.arrow.down",
        title: "Saving Subtitles",
        subtitle: task.audioFileName,
        progress: nil,
        showPercentage: false,
        showsIndeterminateProgress: true,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {
            queueManager.cancelTask(id: task.id)
          }
        )
      )

    case .reloadingSubtitles:
      stateView(
        icon: "arrow.clockwise",
        title: "Reloading Subtitles",
        subtitle: task.audioFileName,
        progress: nil,
        showPercentage: false,
        showsIndeterminateProgress: true,
        action: StateAction(
          id: "transcription-cancel-button",
          title: "Cancel",
          systemImage: nil,
          role: nil,
          style: .bordered,
          handler: {
            queueManager.cancelTask(id: task.id)
          }
        )
      )

    case .completed:
      if !viewModel.cachedCues.isEmpty {
        transcriptionContentView
      } else {
        loadingCacheView
          .task {
            await viewModel.loadCachedTranscription()
            queueManager.removeTask(id: task.id)
          }
      }

    case let .failed(error):
      stateView(
        icon: "exclamationmark.triangle",
        title: "Transcription Failed",
        subtitle: error,
        progress: nil,
        showPercentage: false,
        footnote: nil,
        showsIndeterminateProgress: false,
        iconSize: 48,
        iconColor: .orange,
        animateIcon: false,
        subtitleLineLimit: nil,
        subtitleMaxWidth: 320,
        action: StateAction(
          id: "transcription-retry-button",
          title: "Retry",
          systemImage: "arrow.clockwise",
          role: nil,
          style: .prominent,
          handler: {
            queueManager.retryTask(id: task.id)
          }
        )
      )

    case .cancelled:
      noTranscriptionView
        .task {
          queueManager.removeTask(id: task.id)
        }
    }
  }

  // MARK: - Failed View

  private func failedView(error: String) -> some View {
    stateView(
      icon: "exclamationmark.triangle",
      title: "Transcription Failed",
      subtitle: error,
      progress: nil,
      showPercentage: false,
      footnote: nil,
      showsIndeterminateProgress: false,
      iconSize: 48,
      iconColor: .orange,
      animateIcon: false,
      subtitleLineLimit: nil,
      subtitleMaxWidth: 320,
      action: StateAction(
        id: "transcription-retry-button",
        title: "Retry",
        systemImage: "arrow.clockwise",
        role: nil,
        style: .prominent,
        handler: {
          viewModel.retryTranscriptionFromStart()
        }
      )
    )
  }

  // MARK: - Shared State View

  private func stateView(
    icon: String,
    title: String,
    subtitle: String,
    progress: Double?,
    showPercentage: Bool,
    footnote: String? = nil,
    showsIndeterminateProgress: Bool = false,
    iconSize: CGFloat = 40,
    iconColor: Color = .accentColor,
    animateIcon: Bool = true,
    subtitleLineLimit: Int? = 1,
    subtitleMaxWidth: CGFloat? = nil,
    action: StateAction? = nil
  ) -> some View {
    VStack(spacing: 20) {
      Group {
        if animateIcon {
          Image(systemName: icon)
            .symbolEffect(.pulse, options: .repeating)
        } else {
          Image(systemName: icon)
        }
      }
      .font(.system(size: iconSize, weight: .light))
      .foregroundStyle(iconColor)
      .accessibilityIdentifier("transcription-state-icon")

      VStack(spacing: 8) {
        Text(title)
          .font(.title2)
          .fontWeight(.medium)
          .accessibilityIdentifier("transcription-state-title")

        Group {
          if subtitleLineLimit == nil {
            Text(subtitle)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          } else {
            Text(subtitle)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(subtitleLineLimit)
              .truncationMode(.middle)
              .multilineTextAlignment(.center)
          }
        }
        .frame(maxWidth: subtitleMaxWidth)
        .accessibilityIdentifier("transcription-state-subtitle")
      }

      if let progress {
        VStack(spacing: 8) {
          ProgressView(value: min(max(progress, 0), 1))
            .progressViewStyle(.linear)
            .frame(maxWidth: 220)
            .accessibilityIdentifier("transcription-state-progress")

          if showPercentage {
            Text("\(Int(progress * 100))%")
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .accessibilityIdentifier("transcription-state-percentage")
          }
        }
      } else if showsIndeterminateProgress {
        ProgressView()
          .controlSize(.regular)
          .accessibilityIdentifier("transcription-state-progress")
      }

      if let footnote {
        Text(footnote)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 300)
          .accessibilityIdentifier("transcription-state-footnote")
      }

      if let action {
        actionButton(action)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
    .accessibilityIdentifier("transcription-state-view")
  }

  @ViewBuilder
  private func actionButton(_ action: StateAction) -> some View {
    if action.style == .prominent {
      Button(role: action.role) {
        action.handler()
      } label: {
        actionButtonLabel(action)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .accessibilityIdentifier(action.id)
    } else {
      Button(role: action.role) {
        action.handler()
      } label: {
        actionButtonLabel(action)
      }
      .buttonStyle(.bordered)
      .controlSize(.regular)
      .accessibilityIdentifier(action.id)
    }
  }

  private func actionButtonLabel(_ action: StateAction) -> some View {
    HStack(spacing: 6) {
      if let systemImage = action.systemImage {
        Image(systemName: systemImage)
      }
      Text(action.title)
    }
    .font(.body.weight(.medium))
  }
}

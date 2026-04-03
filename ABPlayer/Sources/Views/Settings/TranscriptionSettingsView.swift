import SwiftUI

struct TranscriptionSettingsView: View {
  @Environment(TranscriptionSettings.self) private var settings
  @Environment(TranscriptionManager.self) private var transcriptionManager

  @State private var viewModel = TranscriptionSettingsViewModel()
  @State private var isFileImporterPresented = false
  @State private var fileImportType: FileImportType?
  @State private var showManualDownload: Bool = false

  var body: some View {
    Form {
      transcriptionSection
      networkSection
      downloadedModelsSection
    }
    .formStyle(.grouped)
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: fileImportType == .ffmpegPath ? [.unixExecutable] : [.folder],
      allowsMultipleSelection: false
    ) { result in
      handleFileImportResult(result)
    }
    .confirmationDialog(
      "Delete Model",
      isPresented: Binding(
        get: { viewModel.output.showDeleteConfirmation },
        set: { if !$0 { viewModel.transform(input: .init(event: .cancelDeleteModel)) } }
      ),
      presenting: viewModel.output.modelToDelete
    ) { model in
      Button("Delete \(model)", role: .destructive) {
        viewModel.transform(input: .init(event: .confirmDeleteModel))
      }
      Button("Cancel", role: .cancel) {}
    } message: { model in
      Text("Are you sure you want to delete the model \"\(model)\"? This cannot be undone.")
    }
    .alert("Migration Error", isPresented: Binding(
      get: { viewModel.output.migrationError != nil },
      set: { _ in viewModel.transform(input: .init(event: .dismissMigrationError)) }
    )) {
      Button("OK") { viewModel.transform(input: .init(event: .dismissMigrationError)) }
    } message: {
      if let error = viewModel.output.migrationError {
        Text(error)
      }
    }
    .onAppear {
      viewModel.configureIfNeeded(settings: settings, transcriptionManager: transcriptionManager)
      viewModel.transform(input: .init(event: .onAppear))
    }
    .onChange(of: settings.modelName) { _, _ in
      viewModel.transform(input: .init(event: .modelNameChanged))
    }
    .onChange(of: settings.ffmpegPath) { _, _ in
      viewModel.transform(input: .init(event: .ffmpegPathChanged))
    }
  }

  // MARK: - Transcription Section

  private var transcriptionSection: some View {
    Section {
      // Model Selection
      Picker(
        "Model",
        selection: Binding(
          get: { settings.modelName },
          set: { settings.modelName = $0 }
        )
      ) {
        ForEach(TranscriptionSettings.availableModels, id: \.id) { model in
          Text(model.name).tag(model.id)
        }
      }

      // Model Status
      HStack {
        Text("Status")
        Spacer()
        if case let .downloading(progress, modelName) = transcriptionManager.state,
           modelName == settings.modelName
        {
          HStack(spacing: 8) {
            ProgressView(value: progress)
              .progressViewStyle(.linear)
              .frame(width: 60)
              .controlSize(.small)

            Text("\(Int(progress * 100))%")
              .monospacedDigit()
              .foregroundStyle(.secondary)
              .font(.caption)

            Button {
              viewModel.transform(input: .init(event: .cancelModelDownload))
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel download")
          }
        } else if viewModel.output.modelDownloadStatus == .unknown
          || viewModel.output.modelDownloadStatus == .checking
        {
          ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.small)
        } else if viewModel.output.modelDownloadStatus == .downloaded {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text("Downloaded")
              .foregroundStyle(.secondary)
          }
        } else {
          Button {
            viewModel.transform(input: .init(event: .downloadModel))
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "arrow.down.circle")
              Text("Download")
            }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        }
      }

      // Manual Download Instructions
      DisclosureGroup("Manual Download Instructions", isExpanded: $showManualDownload) {
        let repoURL =
          "\(settings.effectiveDownloadEndpoint)/argmaxinc/whisperkit-coreml/tree/main"
        let modelDir =
          settings.modelDirectoryURL
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .path
        VStack(alignment: .leading, spacing: 10) {
          Text("1. Open the model repository in your browser:")
          if let url = URL(string: repoURL) {
            Link(repoURL, destination: url)
              .captionStyle()
          }
          Text(
            "2. Find and download the folder whose name contains **\(settings.modelName)**."
          )
          Text("3. Place the downloaded folder at:")
          HStack {
            Text(modelDir)
              .font(.caption.monospaced())
              .textSelection(.enabled)
            Button("Open in Finder") {
              NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: modelDir)
            }
            .buttonStyle(.borderless)
          }
          Text("4. The folder should contain these files:")
          Text(
            "<model-folder>/\n  AudioEncoder.mlmodelc\n  TextDecoder.mlmodelc\n  config.json\n  (and other .mlmodelc files)"
          )
          .font(.caption.monospaced())
          .padding(8)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 4)
      }

      // Language Selection
      Picker(
        "Language",
        selection: Binding(
          get: { settings.language },
          set: { settings.language = $0 }
        )
      ) {
        ForEach(TranscriptionSettings.availableLanguages, id: \.id) { language in
          Text(language.name).tag(language.id)
        }
      }

      // Model Directory
      LabeledContent("Model Directory") {
        HStack {
          Text(viewModel.output.displayDirectory)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

          Button("Choose...") {
            fileImportType = .modelDirectory
            isFileImporterPresented = true
          }
        }
      }

      // Auto-transcribe toggle
      Toggle(
        "Auto-transcribe new files",
        isOn: Binding(
          get: { settings.autoTranscribe },
          set: { settings.autoTranscribe = $0 }
        )
      )

      Toggle(
        "Keep paused after looking up a word",
        isOn: Binding(
          get: { settings.pauseOnWordDismiss },
          set: { settings.pauseOnWordDismiss = $0 }
        )
      )

      // FFmpeg Path
      LabeledContent("FFmpeg") {
        HStack(spacing: 8) {
          Text(viewModel.output.displayFFmpegPath)
            .foregroundStyle(ffmpegStatusColor)
            .lineLimit(1)
            .truncationMode(.middle)

          Button("Choose...") {
            fileImportType = .ffmpegPath
            isFileImporterPresented = true
          }
        }
      }

    } header: {
      Label("Transcription", systemImage: "text.bubble")
    } footer: {
      VStack(alignment: .leading, spacing: 8) {
        Text(
          "WhisperKit uses on-device speech recognition. Larger models are more accurate but require more storage and memory."
        )

        HStack(spacing: 4) {
          Text("Models will be saved to:")
          Button {
            let url =
              settings.modelDirectory.isEmpty
                ? TranscriptionSettings.defaultModelDirectory
                : URL(fileURLWithPath: settings.modelDirectory)
            NSWorkspace.shared.open(url)
          } label: {
            Text(
              settings.modelDirectory.isEmpty
                ? TranscriptionSettings.defaultModelDirectory.path
                : settings.modelDirectory
            )
            .underline()
            .foregroundStyle(.primary)
          }
          .buttonStyle(.plain)
          .onHover { inside in
            if inside {
              NSCursor.pointingHand.push()
            } else {
              NSCursor.pop()
            }
          }
        }
        .captionStyle()

        Text(
          "FFmpeg is required for extracting audio from video files. If not installed, video transcription will fail."
        )
        .captionStyle()

        if viewModel.output.ffmpegPathStatus != .valid {
          Text("FFmpeg not found. Install manually with: brew install ffmpeg")
            .captionStyle()
        }
      }
    }
  }

  // MARK: - Network Section (Download Mirror)

  private var networkSection: some View {
    Section {
      LabeledContent("Download Mirror") {
        VStack {
          HStack {
            if viewModel.output.mirrorSelection == TranscriptionSettingsViewModel.customMirrorSentinel {
              TextField(
                "",
                text: Binding(
                  get: { viewModel.output.customEndpointDraft },
                  set: { viewModel.transform(input: .init(event: .customEndpointDraftChanged($0))) }
                )
              )
              .textFieldStyle(.roundedBorder)
              .frame(minWidth: 180)
              .onSubmit {
                viewModel.transform(input: .init(event: .applyCustomEndpoint))
              }

              Button("Apply") {
                viewModel.transform(input: .init(event: .applyCustomEndpoint))
              }
              .disabled(!viewModel.output.canApplyCustomEndpoint)
            }

            Picker(
              "",
              selection: Binding(
                get: { viewModel.output.mirrorSelection },
                set: { viewModel.transform(input: .init(event: .mirrorSelectionChanged($0))) }
              )
            ) {
              Text("HuggingFace (Official)").tag("")
              Text("HF Mirror (hf-mirror.com)").tag(TranscriptionSettingsViewModel.hfMirror)
              Text("HF Mirror (hf-cdn.sufy.com)").tag(TranscriptionSettingsViewModel.hfCDNMirror)
              Text("Custom").tag(TranscriptionSettingsViewModel.customMirrorSentinel)
            }
            .labelsHidden()
            .fixedSize()
          }
        }
      }

      endpointStatusRow(viewModel.output.modelEndpointTestStatus)
    } header: {
      Label("Download Mirror", systemImage: "network")
    } footer: {
      Text("中国用户：将下载镜像设为 hf-mirror.com 即可无需翻墙下载模型。")
        .captionStyle()
    }
  }

  // MARK: - Downloaded Models Section

  private var downloadedModelsSection: some View {
    Section {
      if viewModel.output.isMigrating {
        HStack {
          ProgressView()
            .controlSize(.small)
          Text("Moving models...")
            .foregroundStyle(.secondary)
        }
      } else if viewModel.output.downloadedModels.isEmpty {
        Text("No models downloaded")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.output.downloadedModels, id: \.name) { model in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(model.name)
                .bodyStyle()
              Text(TranscriptionSettings.formatSize(model.size))
                .captionStyle()
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let invalidName = transcriptionManager.invalidModelName,
               model.name.contains(invalidName)
            {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("This model failed to load and may be corrupted. Try deleting and re-downloading it.")
            }

            Button {
              viewModel.transform(input: .init(event: .requestDeleteModel(model.name)))
            } label: {
              Image(systemName: "trash")
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
          }
          .padding(.vertical, 2)
        }
      }
    } header: {
      Label("Downloaded Models", systemImage: "square.and.arrow.down")
    } footer: {
      if !viewModel.output.downloadedModels.isEmpty {
        let totalSize = viewModel.output.downloadedModels.reduce(0) { $0 + $1.size }
        Text("Total: \(TranscriptionSettings.formatSize(totalSize))")
      }
    }
  }

  // MARK: - Helpers

  private var ffmpegStatusColor: Color {
    switch viewModel.output.ffmpegPathStatus {
    case .valid:
      return .green
    case .invalid, .notFound:
      return .red
    case .unchecked:
      return .secondary
    }
  }

  private func handleFileImportResult(_ result: Result<[URL], Error>) {
    guard let importType = fileImportType else { return }
    switch importType {
    case .ffmpegPath:
      if case let .success(urls) = result, let url = urls.first {
        viewModel.transform(input: .init(event: .ffmpegPathSelected(url)))
      }
    case .modelDirectory:
      if case let .success(urls) = result, let url = urls.first {
        viewModel.transform(input: .init(event: .directorySelected(url)))
      }
    case .libraryDirectory:
      break
    }
  }

  @ViewBuilder
  private func endpointStatusRow(_ testStatus: TranscriptionSettingsViewModel.EndpointTestStatus) -> some View {
    switch testStatus {
    case .idle:
      EmptyView()
    case .testing:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Testing...")
      }
      .foregroundStyle(.secondary)
      .font(.callout)
    case let .success(ms):
      Label("Connected (\(ms) ms)", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.callout)
    case let .failure(msg):
      Label(msg, systemImage: "xmark.circle.fill")
        .foregroundStyle(.red)
        .font(.callout)
        .lineLimit(2)
    }
  }
}

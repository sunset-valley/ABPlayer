import SwiftUI

struct TranscriptionSettingsView: View {
  @Environment(TranscriptionSettings.self) private var settings
  @Environment(TranscriptionManager.self) private var transcriptionManager

  @State private var isFileImporterPresented = false
  @State private var fileImportType: FileImportType?
  @State private var downloadedModels: [(name: String, size: Int64)] = []
  @State private var modelToDelete: String?
  @State private var showDeleteConfirmation = false
  @State private var isMigrating = false
  @State private var migrationError: String?
  @State private var previousDirectory: String = ""
  @State private var ffmpegPathStatus: FFmpegStatus = .unchecked
  @State private var isDownloadingFFmpeg = false
  @State private var ffmpegDownloadProgress: Double = 0
  @State private var ffmpegDownloadTask: Task<Void, Never>?
  @State private var showFFmpegDeleteConfirmation = false
  @State private var mirrorSelection: String = ""
  @State private var ffmpegMirrorSelection: String = ""
  @State private var showManualDownload: Bool = false
  @State private var modelEndpointTestTask: Task<Void, Never>?
  @State private var ffmpegEndpointTestTask: Task<Void, Never>?
  @State private var modelEndpointTestStatus: EndpointTestStatus = .idle
  @State private var ffmpegEndpointTestStatus: EndpointTestStatus = .idle
  @State private var modelDownloadStatus: ModelDownloadStatus = .unknown

  private static let kcodingFFmpegMirror = "https://s3.kcoding.cn/d/aliyun/ffmpeg/ffmpeg-8.1.zip"
  private static let hfMirror = "https://hf-mirror.com"
  private static let hfCDNMirror = "https://hf-cdn.sufy.com"
  private static let customMirrorSentinel = "__custom__"

  enum ModelDownloadStatus: Equatable {
    case unknown, checking, downloaded, notDownloaded
  }

  enum EndpointTestStatus {
    case idle
    case testing
    case success(latency: Int)
    case failure(String)
  }

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
      isPresented: $showDeleteConfirmation,
      presenting: modelToDelete
    ) { model in
      Button("Delete \(model)", role: .destructive) {
        deleteModel(named: model)
      }
      Button("Cancel", role: .cancel) {
        modelToDelete = nil
      }
    } message: { model in
      Text("Are you sure you want to delete the model \"\(model)\"? This cannot be undone.")
    }
    .alert("Migration Error", isPresented: .constant(migrationError != nil)) {
      Button("OK") { migrationError = nil }
    } message: {
      if let error = migrationError {
        Text(error)
      }
    }
    .onAppear {
      checkModelStatus()
      refreshModels()
      refreshFFmpegStatus()
    }
    .onChange(of: settings.modelName) { _, _ in
      checkModelStatus()
    }
    .onChange(of: settings.ffmpegPath) { _, _ in
      refreshFFmpegStatus()
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
              transcriptionManager.cancelDownload()
              settings.deleteDownloadCache(modelName: modelName)
              refreshModels()
              checkModelStatus()
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel download")
          }
        } else if modelDownloadStatus == .unknown || modelDownloadStatus == .checking {
          ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.small)
        } else if modelDownloadStatus == .downloaded {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text("Downloaded")
              .foregroundStyle(.secondary)
          }
        } else {
          Button {
            Task {
              await downloadCurrentModel()
            }
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
          Text(displayDirectory)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

          Button("Choose...") {
            previousDirectory = settings.modelDirectory
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
          if isDownloadingFFmpeg {
            HStack(spacing: 8) {
              ProgressView(value: ffmpegDownloadProgress)
                .progressViewStyle(.linear)
                .frame(width: 60)

              Text("\(Int(ffmpegDownloadProgress * 100))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .font(.caption)

              Button {
                ffmpegDownloadTask?.cancel()
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
              .help("Cancel download")
            }
          } else {
            Text(displayFFmpegPath)
              .foregroundStyle(ffmpegStatusColor)
              .lineLimit(1)
              .truncationMode(.middle)
          }

          if !isDownloadingFFmpeg {
            if ffmpegPathStatus != .valid {
              Button("Download") {
                ffmpegDownloadTask = Task { await downloadFFmpeg() }
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
            }

            if settings.isFFmpegDownloaded {
              Button {
                showFFmpegDeleteConfirmation = true
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.plain)
              .foregroundStyle(.red)
            }

            Button("Choose...") {
              fileImportType = .ffmpegPath
              isFileImporterPresented = true
            }
          }
        }
      }
      .confirmationDialog(
        "Delete FFmpeg",
        isPresented: $showFFmpegDeleteConfirmation
      ) {
        Button("Delete", role: .destructive) {
          try? settings.deleteDownloadedFFmpeg()
          refreshFFmpegStatus()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Delete the downloaded FFmpeg binary?")
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

        if ffmpegPathStatus != .valid {
          Text("Use the Download button to install FFmpeg, or install manually with: brew install ffmpeg")
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
            if mirrorSelection == Self.customMirrorSentinel {
              TextField(
                "",
                text: Binding(
                  get: { settings.downloadEndpoint },
                  set: { settings.downloadEndpoint = $0 }
                )
              )
              .textFieldStyle(.roundedBorder)
              .frame(minWidth: 180)
            }

            Picker("", selection: $mirrorSelection) {
              Text("HuggingFace (Official)").tag("")
              Text("HF Mirror (hf-mirror.com)").tag(Self.hfMirror)
              Text("HF Mirror (hf-cdn.sufy.com)").tag(Self.hfCDNMirror)
              Text("Custom").tag(Self.customMirrorSentinel)
            }
            .labelsHidden()
            .fixedSize()
          }
        }
      }
      .onChange(of: mirrorSelection) { _, newValue in
        if newValue != Self.customMirrorSentinel {
          settings.downloadEndpoint = newValue
        }
        if settings.downloadEndpoint.isEmpty {
          return
        }
        modelEndpointTestTask?.cancel()
        modelEndpointTestTask = Task { await testModelEndpoint() }
      }

      endpointStatusRow(modelEndpointTestStatus)

      LabeledContent("FFmpeg Mirror") {
        HStack {
          Picker("", selection: $ffmpegMirrorSelection) {
            Text("evermeet.cx (Official)").tag("")
            Text("kcoding.cn").tag(Self.kcodingFFmpegMirror)
            Text("Custom").tag(Self.customMirrorSentinel)
          }
          .labelsHidden()
          .fixedSize()
          if ffmpegMirrorSelection == Self.customMirrorSentinel {
            TextField(
              "",
              text: Binding(
                get: { settings.ffmpegMirror },
                set: { settings.ffmpegMirror = $0 }
              )
            )
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 180)
          }
        }
      }
      .onChange(of: ffmpegMirrorSelection) { _, newValue in
        if newValue != Self.customMirrorSentinel {
          settings.ffmpegMirror = newValue
        }
        if settings.ffmpegMirror.isEmpty {
          return
        }
        ffmpegEndpointTestTask?.cancel()
        ffmpegEndpointTestTask = Task { await testFFmpegEndpoint() }
      }

      endpointStatusRow(ffmpegEndpointTestStatus)
    } header: {
      Label("Download Mirror", systemImage: "network")
    } footer: {
      Text("中国用户：将下载镜像设为 hf-mirror.com 即可无需翻墙下载模型。")
        .captionStyle()
    }
    .onAppear {
      // Sync HuggingFace mirror state
      if settings.downloadEndpoint.isEmpty ||
        settings.downloadEndpoint == Self.hfMirror ||
        settings.downloadEndpoint == Self.hfCDNMirror
      {
        mirrorSelection = settings.downloadEndpoint
      } else {
        mirrorSelection = Self.customMirrorSentinel
      }
      // Sync ffmpeg mirror state
      if settings.ffmpegMirror.isEmpty ||
        settings.ffmpegMirror == Self.kcodingFFmpegMirror
      {
        ffmpegMirrorSelection = settings.ffmpegMirror
      } else {
        ffmpegMirrorSelection = Self.customMirrorSentinel
      }

      // Auto-test endpoints on appear
      modelEndpointTestTask?.cancel()
      modelEndpointTestTask = Task { await testModelEndpoint() }
      ffmpegEndpointTestTask?.cancel()
      ffmpegEndpointTestTask = Task { await testFFmpegEndpoint() }
    }
  }

  // MARK: - Downloaded Models Section

  private var downloadedModelsSection: some View {
    Section {
      if isMigrating {
        HStack {
          ProgressView()
            .controlSize(.small)
          Text("Moving models...")
            .foregroundStyle(.secondary)
        }
      } else if downloadedModels.isEmpty {
        Text("No models downloaded")
          .foregroundStyle(.secondary)
      } else {
        ForEach(downloadedModels, id: \.name) { model in
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
              modelToDelete = model.name
              showDeleteConfirmation = true
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
      if !downloadedModels.isEmpty {
        let totalSize = downloadedModels.reduce(0) { $0 + $1.size }
        Text("Total: \(TranscriptionSettings.formatSize(totalSize))")
      }
    }
  }

  // MARK: - Helpers

  private var displayFFmpegPath: String {
    if !settings.ffmpegPath.isEmpty, ffmpegPathStatus == .valid {
      return settings.ffmpegPath
    }
    if settings.isFFmpegDownloaded {
      return "Downloaded"
    }
    if let detected = TranscriptionSettings.autoDetectFFmpegPath() {
      return "Auto-detected: \(detected)"
    }
    return "Not found"
  }

  private var displayDirectory: String {
    if settings.modelDirectory.isEmpty {
      return "Default"
    }
    return (settings.modelDirectory as NSString).lastPathComponent
  }

  private var ffmpegStatusColor: Color {
    switch ffmpegPathStatus {
    case .valid:
      return .green
    case .invalid, .notFound:
      return .red
    case .unchecked:
      return .secondary
    }
  }

  private func refreshFFmpegStatus() {
    if !settings.ffmpegPath.isEmpty {
      ffmpegPathStatus = TranscriptionSettings.isFFmpegValid(at: settings.ffmpegPath) ? .valid : .invalid
    } else if settings.isFFmpegDownloaded || TranscriptionSettings.autoDetectFFmpegPath() != nil {
      ffmpegPathStatus = .valid
    } else {
      ffmpegPathStatus = .notFound
    }
  }

  @MainActor
  private func downloadFFmpeg() async {
    isDownloadingFFmpeg = true
    ffmpegDownloadProgress = 0
    defer {
      isDownloadingFFmpeg = false
      ffmpegDownloadTask = nil
    }
    do {
      try await settings.downloadFFmpeg { progress in
        Task { @MainActor in
          self.ffmpegDownloadProgress = progress
        }
      }
      refreshFFmpegStatus()
    } catch is CancellationError {
      ffmpegDownloadProgress = 0
    } catch {
      // Leave status as-is; user can retry
    }
  }

  private func handleFileImportResult(_ result: Result<[URL], Error>) {
    guard let importType = fileImportType else { return }

    switch importType {
    case .ffmpegPath:
      handleFFmpegPathSelection(result)
    case .modelDirectory:
      handleDirectorySelection(result)
    case .libraryDirectory:
      break
    }
  }

  private func handleFFmpegPathSelection(_ result: Result<[URL], Error>) {
    switch result {
    case let .success(urls):
      if let url = urls.first {
        settings.ffmpegPath = url.path
        refreshFFmpegStatus()
      }
    case .failure:
      break
    }
  }

  private func checkModelStatus() {
    let currentModel = settings.modelName
    modelDownloadStatus = .checking
    Task.detached(priority: .utility) {
      let exists = await settings.isModelDownloaded(modelName: currentModel)
      await MainActor.run {
        guard settings.modelName == currentModel else { return }
        modelDownloadStatus = exists ? .downloaded : .notDownloaded
      }
    }
  }

  private func refreshModels() {
    Task {
      downloadedModels = await settings.listDownloadedModelsAsync()
    }
  }

  private func downloadCurrentModel() async {
    if modelDownloadStatus == .downloaded { return }

    do {
      try await transcriptionManager.downloadModel(
        modelName: settings.modelName,
        downloadBase: settings.modelDirectoryURL,
        endpoint: settings.effectiveDownloadEndpoint
      )
      checkModelStatus()
      refreshModels()
    } catch is CancellationError {
      checkModelStatus()
      refreshModels()
    } catch {
      checkModelStatus()
      refreshModels()
      migrationError = "Failed to download model: \(error.localizedDescription)"
    }
  }

  private func deleteModel(named name: String) {
    do {
      try settings.deleteModel(named: name)
      refreshModels()
      checkModelStatus()
    } catch {
      migrationError = "Failed to delete model: \(error.localizedDescription)"
    }
    modelToDelete = nil
  }

  private func handleDirectorySelection(_ result: Result<[URL], Error>) {
    switch result {
    case let .success(urls):
      if let url = urls.first {
        if (try? url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )) != nil {
          let newPath = url.path
          let oldPath =
            previousDirectory.isEmpty
              ? TranscriptionSettings.defaultModelDirectory.path
              : previousDirectory

          if !downloadedModels.isEmpty, oldPath != newPath {
            migrateModels(from: oldPath, to: newPath)
          }

          settings.modelDirectory = newPath
          refreshModels()
        }
      }
    case .failure:
      break
    }
  }

  private func migrateModels(from oldPath: String, to newPath: String) {
    isMigrating = true

    Task {
      do {
        let oldURL = URL(fileURLWithPath: oldPath)
        let newURL = URL(fileURLWithPath: newPath)
        try settings.migrateModels(from: oldURL, to: newURL)
      } catch {
        await MainActor.run {
          migrationError = "Failed to migrate models: \(error.localizedDescription)"
        }
      }

      await MainActor.run {
        isMigrating = false
        refreshModels()
      }
    }
  }

  @ViewBuilder
  private func endpointStatusRow(_ testStatus: EndpointTestStatus) -> some View {
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

  private func testModelEndpoint() async {
    modelEndpointTestStatus = .testing
    modelEndpointTestStatus = await performEndpointTest(urlString: settings.effectiveDownloadEndpoint)
  }

  private func testFFmpegEndpoint() async {
    ffmpegEndpointTestStatus = .testing
    ffmpegEndpointTestStatus = await performEndpointTest(urlString: settings.effectiveFFmpegDownloadURL)
  }

  private func performEndpointTest(urlString: String) async -> EndpointTestStatus {
    guard let url = URL(string: urlString) else {
      return .failure("Invalid URL")
    }
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    let session = URLSession(configuration: config)
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    let start = Date()
    do {
      let (_, response) = try await session.data(for: request)
      let ms = Int(Date().timeIntervalSince(start) * 1000)
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      if statusCode < 500 {
        return .success(latency: ms)
      } else {
        return .failure("Server returned \(statusCode)")
      }
    } catch {
      if error.localizedDescription == "cancelled" {
        return .idle
      }
      return .failure(error.localizedDescription)
    }
  }
}

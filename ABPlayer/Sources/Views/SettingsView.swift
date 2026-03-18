import KeyboardShortcuts
import SwiftUI
import Observation

/// FFmpeg path validation status
enum FFmpegStatus {
  case unchecked
  case valid
  case invalid
  case notFound
}

enum FileImportType {
  case ffmpegPath
  case modelDirectory
  case libraryDirectory
}

/// Settings view for configuring application options
struct SettingsView: View {
  @Environment(TranscriptionSettings.self) private var settings
  @Environment(LibrarySettings.self) private var librarySettings
  @Environment(PlayerSettings.self) private var playerSettings
  @Environment(ProxySettings.self) private var proxySettings
  @Environment(TranscriptionManager.self) private var transcriptionManager

  // Navigation selection
  @State private var selectedTab: SettingsTab? = .media

  @State private var isFileImporterPresented = false
  @State private var fileImportType: FileImportType?
  @State private var downloadedModels: [(name: String, size: Int64)] = []
  @State private var modelToDelete: String?
  @State private var showDeleteConfirmation = false
  @State private var isMigrating = false
  @State private var migrationError: String?
  @State private var previousDirectory: String = ""

  @State private var libraryPathError: String?

  @State private var ffmpegPathStatus: FFmpegStatus = .unchecked

  // Mirror/endpoint states
  @State private var mirrorSelection: String = ""
  @State private var showManualDownload: Bool = false

  // Proxy test states
  @State private var proxyTestStatus: ProxyTestStatus = .idle

  enum ProxyTestStatus {
    case idle
    case testing
    case success(latency: Int)
    case failure(String)
  }

  // Shortcuts states
  @State private var showResetConfirmation = false

  var body: some View {
    NavigationSplitView {
      //      EmptyView()
      //        .toolbar(removing: .sidebarToggle)
      //    } content: {
      List(selection: $selectedTab) {
        ForEach(SettingsTab.allCases) { tab in
          NavigationLink(value: tab) {
            Label(tab.rawValue, systemImage: tab.icon)
          }
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .navigationSplitViewColumnWidth(min: 200, ideal: 200)
    } detail: {
      Group {
        if let selectedTab {
          switch selectedTab {
          case .media:
            mediaSettingsView
          case .shortcuts:
            shortcutsView
          case .transcription:
            transcriptionSettingsView
          case .plugins:
            pluginsView
          }
        } else {
          ContentUnavailableView("Select a setting", systemImage: "gear")
        }
      }
      .navigationTitle("Settings")
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 400, idealWidth: 600)
    .frame(minHeight: 400, idealHeight: 600)
    // Common modifiers
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
    .alert("Library Path Error", isPresented: .constant(libraryPathError != nil)) {
      Button("OK") { libraryPathError = nil }
    } message: {
      if let error = libraryPathError {
        Text(error)
      }
    }
    .confirmationDialog(
      "Reset Keyboard Shortcuts",
      isPresented: $showResetConfirmation
    ) {
      Button("Reset to Defaults", role: .destructive) {
        resetAllShortcuts()
      }
      Button("Cancel", role: .cancel) {
        showResetConfirmation = false
      }
    } message: {
      Text("Are you sure you want to reset all keyboard shortcuts to their default values?")
    }
    .onAppear {
      if selectedTab == .transcription {
        refreshModels()
        refreshFFmpegStatus()
      }
    }
    .onChange(of: selectedTab) { _, newValue in
      if newValue == .transcription {
        refreshModels()
        refreshFFmpegStatus()
      }
    }
    .onChange(of: settings.ffmpegPath) { _, _ in
      refreshFFmpegStatus()
    }
  }

  // MARK: - Shortcuts View

  private var shortcutsView: some View {
    Form {
      Section("Playback") {
        shortcutRow(title: "Play/Pause:", name: .playPause)
        shortcutRow(title: "Rewind 5s:", name: .rewind5s)
        shortcutRow(title: "Forward 10s:", name: .forward10s)
      }

      Section("Loop Controls") {
        shortcutRow(title: "Set Point A:", name: .setPointA)
        shortcutRow(title: "Set Point B:", name: .setPointB)
        shortcutRow(title: "Clear Loop:", name: .clearLoop)
        shortcutRow(title: "Save Segment:", name: .saveSegment)
      }

      Section("Navigation") {
        shortcutRow(title: "Previous Segment:", name: .previousSegment)
        shortcutRow(title: "Next Segment:", name: .nextSegment)
      }

      Section {
        HStack {
          Spacer()
          Button("Reset to Defaults") {
            showResetConfirmation = true
          }
          .buttonStyle(.borderedProminent)
          Spacer()
        }
      } footer: {
        Text("Reset all keyboard shortcuts to their default values")
          .captionStyle()
      }
    }
    .formStyle(.grouped)
  }

  private func shortcutRow(title: String, name: KeyboardShortcuts.Name) -> some View {
    KeyboardShortcuts.Recorder(title, name: name)
  }

  private func resetAllShortcuts() {
    KeyboardShortcuts.reset(.playPause)
    KeyboardShortcuts.reset(.rewind5s)
    KeyboardShortcuts.reset(.forward10s)
    KeyboardShortcuts.reset(.setPointA)
    KeyboardShortcuts.reset(.setPointB)
    KeyboardShortcuts.reset(.clearLoop)
    KeyboardShortcuts.reset(.saveSegment)
    KeyboardShortcuts.reset(.previousSegment)
    KeyboardShortcuts.reset(.nextSegment)
    KeyboardShortcuts.reset(.counterIncrement)
    KeyboardShortcuts.reset(.counterDecrement)
    KeyboardShortcuts.reset(.counterReset)
  }
  
  private var pluginsView: some View {
    Form {
      Section("Counter") {
        Toggle(
          "Always on Top",
          isOn: Binding(
            get: { CounterPlugin.shared.settings.alwaysOnTop },
            set: { newValue in
              CounterPlugin.shared.settings.alwaysOnTop = newValue
              CounterPlugin.shared.updateWindowLevel()
            }
          ))
        
        shortcutRow(title: "Increment (+):", name: .counterIncrement)
        shortcutRow(title: "Decrement (-):", name: .counterDecrement)
        shortcutRow(title: "Reset:", name: .counterReset)
      }
    }
    .formStyle(.grouped)
  }

  private var mediaSettingsView: some View {
    Form {
      librarySection
      playerSection
    }
    .formStyle(.grouped)
  }

  private var playerSection: some View {
    Section {
      Toggle(
        "Prevent sleep during playback",
        isOn: Binding(
          get: { playerSettings.preventSleep },
          set: { playerSettings.preventSleep = $0 }
        ))
    } header: {
      Label("Player", systemImage: "play.circle")
    }
  }

  // MARK: - Transcription Settings View

  private var transcriptionSettingsView: some View {
    Form {
      transcriptionSection
      networkSection
      downloadedModelsSection
    }
    .formStyle(.grouped)
  }

  private var librarySection: some View {
    Section {
      LabeledContent("Library Directory") {
        HStack {
          Text(displayLibraryDirectory)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

          Button("Choose...") {
            fileImportType = .libraryDirectory
            isFileImporterPresented = true
          }
        }
      }
    } header: {
      Label("Library", systemImage: "books.vertical")
    } footer: {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 4) {
          Text("Library stored at:")
          Button {
            let url = librarySettings.libraryDirectoryURL
            NSWorkspace.shared.open(url)
          } label: {
            Text(displayLibraryDirectory)
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
      }
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
        if case .downloading(let progress, let modelName) = transcriptionManager.state,
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
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel download")
          }
        } else if isCurrentModelDownloaded {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text("Downloaded")
              .foregroundStyle(.secondary)
          }
        } else {
          Button {
            Task { await downloadCurrentModel() }
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
        ))

      Toggle(
        "Keep paused after looking up a word",
        isOn: Binding(
          get: { settings.pauseOnWordDismiss },
          set: { settings.pauseOnWordDismiss = $0 }
        ))

      // FFmpeg Path
      #if FULL_EDITION
      LabeledContent("FFmpeg") {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Bundled")
            .foregroundStyle(.secondary)
        }
      }
      #else
      LabeledContent("FFmpeg Path") {
        HStack {
          Text(displayFFmpegPath)
            .foregroundStyle(ffmpegStatusColor)
            .lineLimit(1)
            .truncationMode(.middle)

          Button("Choose...") {
            fileImportType = .ffmpegPath
            isFileImporterPresented = true
          }
        }
      }
      #endif

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

        #if !FULL_EDITION
        Text(
          "FFmpeg is required for extracting audio from video files. If not installed, video transcription will fail."
        )
        .captionStyle()

        if ffmpegPathStatus != .valid {
          Text("Install with: brew install ffmpeg")
            .captionStyle()
        }
        #endif
      }
    }
  }

  // MARK: - Network Section

  private var networkSection: some View {
    Section {
      LabeledContent("Download Mirror") {
        HStack {
          Picker("", selection: $mirrorSelection) {
            Text("HuggingFace (Official)").tag("")
            Text("HF Mirror (hf-mirror.com)").tag("https://hf-mirror.com")
            Text("Custom").tag("__custom__")
          }
          .labelsHidden()
          .fixedSize()
          if mirrorSelection == "__custom__" {
            TextField(
              "https://...",
              text: Binding(
                get: { settings.downloadEndpoint },
                set: { settings.downloadEndpoint = $0 }
              )
            )
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 180)
          }
        }
      }
      .onChange(of: mirrorSelection) { _, newValue in
        if newValue == "__custom__" {
          // Keep existing custom value
        } else {
          settings.downloadEndpoint = newValue
        }
      }

      // Proxy
      Toggle(
        "Use HTTP/SOCKS Proxy",
        isOn: Binding(
          get: { proxySettings.isEnabled },
          set: {
            proxySettings.isEnabled = $0
            proxyTestStatus = .idle
          }
        )
      )

      if proxySettings.isEnabled {
        Picker(
          "Proxy Type",
          selection: Binding(
            get: { proxySettings.type },
            set: { proxySettings.type = $0 }
          )
        ) {
          Text("HTTP").tag("http")
          Text("SOCKS5").tag("socks5")
        }
        .pickerStyle(.segmented)

        LabeledContent("Host") {
          TextField(
            "proxy.example.com",
            text: Binding(
              get: { proxySettings.host },
              set: { proxySettings.host = $0 }
            )
          )
          .textFieldStyle(.roundedBorder)
          .frame(minWidth: 180)
        }

        LabeledContent("Port") {
          TextField(
            "8080",
            value: Binding(
              get: { proxySettings.port },
              set: { proxySettings.port = $0 }
            ),
            format: .number
          )
          .textFieldStyle(.roundedBorder)
          .frame(width: 80)
        }

        HStack {
          Button {
            Task { await testProxy() }
          } label: {
            if case .testing = proxyTestStatus {
              HStack(spacing: 6) {
                ProgressView()
                  .controlSize(.small)
                Text("Testing...")
              }
            } else {
              Text("Test Connection")
            }
          }
          .disabled(!proxySettings.isConfigured || {
            if case .testing = proxyTestStatus { return true }
            return false
          }())
          .buttonStyle(.bordered)
          .controlSize(.small)

          switch proxyTestStatus {
          case .idle:
            EmptyView()
          case .testing:
            EmptyView()
          case .success(let ms):
            Label("Connected (\(ms) ms)", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .font(.caption)
          case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
              .foregroundStyle(.red)
              .font(.caption)
          }
        }
      }
    } header: {
      Label("Network", systemImage: "network")
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text("中国用户：将下载镜像设为 hf-mirror.com 即可无需翻墙下载模型。")
        if proxySettings.isEnabled {
          if proxySettings.isConfigured {
            Text(
              "Proxy: \(proxySettings.type.uppercased()) → \(proxySettings.host):\(proxySettings.port)"
            )
            .foregroundStyle(.green)
          } else {
            Text("Proxy enabled but host/port not configured.")
              .foregroundStyle(.red)
          }
        }
      }
      .captionStyle()
    }
    .onAppear {
      // Sync state with stored value
      let stored = settings.downloadEndpoint
      if stored.isEmpty || stored == "https://hf-mirror.com" {
        mirrorSelection = stored
      } else {
        mirrorSelection = "__custom__"
      }
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
    if settings.ffmpegPath.isEmpty {
      if let detected = TranscriptionSettings.autoDetectFFmpegPath() {
        return "Auto-detected: \(detected)"
      }
      return "Not found"
    }
    return settings.ffmpegPath
  }

  private var displayLibraryDirectory: String {
    if librarySettings.libraryPath.isEmpty {
      return LibrarySettings.defaultLibraryDirectory.path
    }
    return librarySettings.libraryPath
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
    if settings.ffmpegPath.isEmpty {
      if TranscriptionSettings.autoDetectFFmpegPath() != nil {
        ffmpegPathStatus = .valid
      } else {
        ffmpegPathStatus = .notFound
      }
    } else {
      ffmpegPathStatus = TranscriptionSettings.isFFmpegValid(at: settings.ffmpegPath) ? .valid : .invalid
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
      handleLibraryDirectorySelection(result)
    }
  }

  private func handleFFmpegPathSelection(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      if let url = urls.first {
        settings.ffmpegPath = url.path
        refreshFFmpegStatus()
      }
    case .failure:
      break
    }
  }

  private var displayDirectory: String {
    if settings.modelDirectory.isEmpty {
      return "Default"
    }
    return (settings.modelDirectory as NSString).lastPathComponent
  }

  /// Check if the currently selected model is downloaded
  private var isCurrentModelDownloaded: Bool {
    // WhisperKit uses naming like "openai_whisper-tiny" or "distil-whisper_distil-large-v3"
    downloadedModels.contains { model in
      model.name.contains(settings.modelName)
    }
  }

  private func refreshModels() {
    Task {
      downloadedModels = await settings.listDownloadedModelsAsync()
    }
  }

  private func downloadCurrentModel() async {
    do {
      try await transcriptionManager.loadModel(
        modelName: settings.modelName,
        downloadBase: settings.modelDirectoryURL,
        endpoint: settings.effectiveDownloadEndpoint
      )
      refreshModels()
    } catch is CancellationError {
      // Download cancelled, no need to show error
    } catch {
      migrationError = "Failed to download model: \(error.localizedDescription)"
    }
  }

  private func deleteModel(named name: String) {
    do {
      try settings.deleteModel(named: name)
      refreshModels()
    } catch {
      migrationError = "Failed to delete model: \(error.localizedDescription)"
    }
    modelToDelete = nil
  }

  private func handleDirectorySelection(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
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

          if !downloadedModels.isEmpty && oldPath != newPath {
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

  private func handleLibraryDirectorySelection(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      if (try? url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )) != nil {
        librarySettings.libraryPath = url.path
        do {
          try librarySettings.ensureLibraryDirectoryExists()
        } catch {
          libraryPathError = "Failed to create library directory: \(error.localizedDescription)"
        }
      } else {
        libraryPathError = "Unable to access selected folder."
      }
    case .failure(let error):
      libraryPathError = error.localizedDescription
    }
  }

  private func testProxy() async {
    proxyTestStatus = .testing

    let host = proxySettings.host.trimmingCharacters(in: .whitespaces)
    let port = proxySettings.port
    let type = proxySettings.type

    let proxyDict: [AnyHashable: Any]
    if type == "socks5" {
      proxyDict = [
        kCFStreamPropertySOCKSProxyHost as AnyHashable: host,
        kCFStreamPropertySOCKSProxyPort as AnyHashable: port,
      ]
    } else {
      proxyDict = [
        kCFNetworkProxiesHTTPEnable as AnyHashable: true,
        kCFNetworkProxiesHTTPProxy as AnyHashable: host,
        kCFNetworkProxiesHTTPPort as AnyHashable: port,
        "HTTPSEnable" as AnyHashable: true,
        "HTTPSProxy" as AnyHashable: host,
        "HTTPSPort" as AnyHashable: port,
      ]
    }

    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = proxyDict
    config.timeoutIntervalForRequest = 10
    let session = URLSession(configuration: config)

    let testURL = URL(string: "https://huggingface.co")!
    let start = Date()

    do {
      var request = URLRequest(url: testURL)
      request.httpMethod = "HEAD"
      let (_, response) = try await session.data(for: request)
      let ms = Int(Date().timeIntervalSince(start) * 1000)
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      if statusCode < 500 {
        proxyTestStatus = .success(latency: ms)
      } else {
        proxyTestStatus = .failure("Server returned \(statusCode)")
      }
    } catch {
      proxyTestStatus = .failure(error.localizedDescription)
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
}

// MARK: - Supporting Views

enum SettingsTab: String, CaseIterable, Identifiable {
  case media = "Media"
  case shortcuts = "Shortcuts"
  case transcription = "Transcription"
  case plugins = "Plugins"

  var id: Self { self }

  var icon: String {
    switch self {
    case .media: return "books.vertical"
    case .shortcuts: return "keyboard"
    case .transcription: return "text.bubble"
    case .plugins: return "puzzlepiece.extension"
    }
  }
}

// MARK: - Preview

#Preview {
  SettingsView()
    .environment(TranscriptionSettings())
    .environment(TranscriptionManager())
    .environment(ProxySettings())
    .frame(width: 800, height: 600)
}

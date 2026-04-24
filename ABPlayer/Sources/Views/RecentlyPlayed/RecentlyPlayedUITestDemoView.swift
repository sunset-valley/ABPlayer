import SwiftData
import SwiftUI

@MainActor
struct RecentlyPlayedUITestDemoView: View {
  @State private var demoRootURL: URL
  @State private var modelContext: ModelContext

  @State private var librarySettings = LibrarySettings()
  @State private var playerManager: PlayerManager
  @State private var folderNavigationViewModel: FolderNavigationViewModel
  @State private var showRecentlyPlayed = false
  @State private var isSettingUp = false
  @State private var didSetup = false
  @State private var setupTask: Task<Void, Never>?

  private static let folderRelativePath = "ui-testing/recently-played"

  init() {
    let container = Self.makeInMemoryModelContainer()
    let modelContext = ModelContext(container)
    let librarySettings = LibrarySettings()
    let demoRootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("ABPlayer-RecentlyPlayed-UI-")
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    librarySettings.libraryPath = demoRootURL.path
    let playerManager = PlayerManager(librarySettings: librarySettings, engine: MockPlayerEngine())
    let viewModel = FolderNavigationViewModel(
      modelContext: modelContext,
      playerManager: playerManager,
      librarySettings: librarySettings
    )

    _demoRootURL = State(initialValue: demoRootURL)
    _modelContext = State(initialValue: modelContext)
    _librarySettings = State(initialValue: librarySettings)
    _playerManager = State(initialValue: playerManager)
    _folderNavigationViewModel = State(initialValue: viewModel)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Recently Played UI Test Demo")
        .font(.title2)
        .accessibilityIdentifier("recently-played-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-recently-played")
        .font(.caption)
        .foregroundStyle(.secondary)

      metricsPanel

      if let item = folderNavigationViewModel.recentlyPlayedItemInCurrentFolder {
        RecentlyPlayedCardView(item: item) {
          Task { @MainActor in
            await folderNavigationViewModel.playRecentlyPlayed(item.file)
          }
        }
      }

      HStack(spacing: 12) {
        Button("Play 84_10") {
          Task { @MainActor in
            await play84_10()
          }
        }
        .accessibilityIdentifier("recently-played-demo-play-84_10")
      }

      Spacer()
    }
    .padding(16)
    .frame(minWidth: 900, minHeight: 620)
    .onAppear {
      startSetupIfNeeded()
    }
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          showRecentlyPlayed = true
        } label: {
          Label("Recently Played", systemImage: "clock.arrow.circlepath")
        }
        .accessibilityIdentifier("recently-played-menu-button")
        .help("Recently Played")
        .popover(isPresented: $showRecentlyPlayed, arrowEdge: .top) {
          RecentlyPlayedToolbarMenuView(
            items: folderNavigationViewModel.globalRecentlyPlayedItems,
            isLoading: folderNavigationViewModel.isLoadingGlobalRecentlyPlayed,
            onPlayItem: { file in
              await folderNavigationViewModel.playRecentlyPlayed(file)
              showRecentlyPlayed = false
            }
          )
        }
      }
    }
    .onChange(of: showRecentlyPlayed) { _, isPresented in
      guard isPresented else { return }
      Task { @MainActor in
        await folderNavigationViewModel.refreshGlobalRecentlyPlayedIfNeeded()
      }
    }
  }

  private var metricsPanel: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("card-file: \(folderNavigationViewModel.recentlyPlayedItemInCurrentFolder?.file.displayName ?? "none")")
        .font(.caption.monospaced())
        .accessibilityIdentifier("recently-played-metric-card-file")

      Text("card-now-playing: \(cardNowPlayingText)")
        .font(.caption.monospaced())
        .accessibilityIdentifier("recently-played-metric-card-now-playing")

      Text("card-progress-visible: \(cardProgressVisibleText)")
        .font(.caption.monospaced())
        .accessibilityIdentifier("recently-played-metric-card-progress-visible")

      Text("global-84-now-playing: \(global84NowPlayingText)")
        .font(.caption.monospaced())
        .accessibilityIdentifier("recently-played-metric-global-84-now-playing")

      Text("global-84-progress-visible: \(global84ProgressVisibleText)")
        .font(.caption.monospaced())
        .accessibilityIdentifier("recently-played-metric-global-84-progress-visible")

      Text("setup-state: \(setupStateText)")
        .font(.caption.monospaced())
        .accessibilityIdentifier("recently-played-metric-setup-state")

      Text("popover-presented: \(popoverPresentedText)")
        .font(.caption.monospaced())
        .accessibilityIdentifier("recently-played-metric-popover-presented")
    }
  }

  private func startSetupIfNeeded() {
    guard !didSetup, !isSettingUp, setupTask == nil else { return }
    isSettingUp = true

    setupTask = Task { @MainActor in
      defer {
        isSettingUp = false
        setupTask = nil
      }

      await setupDemoData()
      didSetup = true
    }
  }

  private var cardNowPlayingText: String {
    guard let item = folderNavigationViewModel.recentlyPlayedItemInCurrentFolder else { return "false" }
    return item.isNowPlaying ? "true" : "false"
  }

  private var cardProgressVisibleText: String {
    guard let item = folderNavigationViewModel.recentlyPlayedItemInCurrentFolder else { return "false" }
    return (!item.isNowPlaying && item.progress != nil) ? "true" : "false"
  }

  private var global84Item: FolderNavigationViewModel.RecentlyPlayedItem? {
    folderNavigationViewModel.globalRecentlyPlayedItems.first(where: { $0.file.displayName == "84_10" })
  }

  private var global84NowPlayingText: String {
    guard let item = global84Item else { return "false" }
    return item.isNowPlaying ? "true" : "false"
  }

  private var global84ProgressVisibleText: String {
    guard let item = global84Item else { return "false" }
    return (!item.isNowPlaying && item.progress != nil) ? "true" : "false"
  }

  private var setupStateText: String {
    if didSetup {
      return "done"
    }

    if isSettingUp {
      return "running"
    }

    return "idle"
  }

  private var popoverPresentedText: String {
    showRecentlyPlayed ? "true" : "false"
  }

  private func setupDemoData() async {
    try? FileManager.default.createDirectory(at: demoRootURL, withIntermediateDirectories: true)

    let folder = Folder(name: "UI Recent", relativePath: Self.folderRelativePath)
    modelContext.insert(folder)

    let file83 = ABFile(
      displayName: "83_9.mp4",
      bookmarkData: Data(),
      folder: folder,
      relativePath: "\(Self.folderRelativePath)/83_9.mp4"
    )
    file83.cachedDuration = 100
    file83.currentPlaybackPosition = 90
    file83.playbackRecord?.lastPlayedAt = Date().addingTimeInterval(-30)

    let file84 = ABFile(
      displayName: "84_10.mp4",
      bookmarkData: Data(),
      folder: folder,
      relativePath: "\(Self.folderRelativePath)/84_10.mp4"
    )
    file84.cachedDuration = 100
    file84.currentPlaybackPosition = 25
    file84.playbackRecord?.lastPlayedAt = Date().addingTimeInterval(-600)

    modelContext.insert(file83)
    modelContext.insert(file84)
    try? modelContext.save()

    let folderURL = librarySettings.libraryDirectoryURL.appendingPathComponent(Self.folderRelativePath)
    try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: librarySettings.mediaFileURL(for: file83).path, contents: Data())
    FileManager.default.createFile(atPath: librarySettings.mediaFileURL(for: file84).path, contents: Data())

    folderNavigationViewModel.currentFolder = folder
    playerManager.currentFile = file83
    playerManager.isPlaying = false
    await folderNavigationViewModel.refreshCurrentFolderRecentlyPlayed()
    await folderNavigationViewModel.refreshGlobalRecentlyPlayed(limit: 8)
  }

  private func play84_10() async {
    guard
      let file = folderNavigationViewModel.currentAudioFiles().first(where: { $0.displayName == "84_10" })
    else {
      return
    }

    await playerManager.playFile(file, fromStart: false)
    await folderNavigationViewModel.handlePlaybackRecordTouched(file)
    await folderNavigationViewModel.refreshGlobalRecentlyPlayed(limit: 8)
  }

  private static func makeInMemoryModelContainer() -> ModelContainer {
    let schema = Schema([
      ABFile.self,
      LoopSegment.self,
      PlaybackRecord.self,
      Folder.self,
      SubtitleFile.self,
      Transcription.self,
    ])

    do {
      return try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
      )
    } catch {
      fatalError("Failed to create in-memory model container for recently played demo: \(error)")
    }
  }
}

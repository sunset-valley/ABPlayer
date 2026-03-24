import KeyboardShortcuts
import OSLog
import Sentry
import Sparkle
import SwiftData
import SwiftUI
import TelemetryDeck

extension Logger {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "cc.ihugo.ABPlayer"

  static let audio = Logger(subsystem: subsystem, category: "audio")
  static let ui = Logger(subsystem: subsystem, category: "ui")
  static let data = Logger(subsystem: subsystem, category: "data")
  static let general = Logger(subsystem: subsystem, category: "general")
}

enum UpdateFeedSource: String, CaseIterable, Identifiable {
  case kcoding

  var id: Self {
    self
  }

  var appcastURL: String {
    switch self {
    case .kcoding:
      return "https://s3.kcoding.cn/d/ABPlayerRelease/appcast.xml"
    }
  }
}

@MainActor
@Observable
final class SparkleUpdater {
  @ObservationIgnored
  private let controller: SPUStandardUpdaterController

  @ObservationIgnored
  @AppStorage(UserDefaultsKey.updateFeedSource) private var _selectedFeedSourceRawValue: String =
    UpdateFeedSource.kcoding.rawValue

  var selectedFeedSource: UpdateFeedSource {
    get {
      access(keyPath: \.selectedFeedSource)
      return UpdateFeedSource(rawValue: _selectedFeedSourceRawValue) ?? .kcoding
    }
    set {
      withMutation(keyPath: \.selectedFeedSource) {
        _selectedFeedSourceRawValue = newValue.rawValue
        applyFeedURLOverride(for: newValue)
      }
    }
  }

  var selectedFeedURL: String {
    selectedFeedSource.appcastURL
  }

  init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    applyFeedURLOverride(for: selectedFeedSource)
  }

  func checkForUpdates() {
    applyFeedURLOverride(for: selectedFeedSource)
    controller.checkForUpdates(nil)
  }

  private func applyFeedURLOverride(for source: UpdateFeedSource) {
    UserDefaults.standard.set(source.appcastURL, forKey: UserDefaultsKey.sparkleFeedURL)
  }
}

@main
struct ABPlayerApp: App {
  @Environment(\.scenePhase) private var scenePhase

  private let modelContainer: ModelContainer
  private let playerManager = PlayerManager()
  private let sessionTracker: SessionTracker
  private let transcriptionManager = TranscriptionManager()
  private let transcriptionSettings = TranscriptionSettings()
  private let librarySettings = LibrarySettings()
  private let playerSettings = PlayerSettings()
  private let proxySettings = ProxySettings()
  private let annotationStyleService: AnnotationStyleService
  private let annotationService: AnnotationService
  private let notesBrowserService: NotesBrowserService
  private let subtitleLoader = SubtitleLoader()

  private let queueManager: TranscriptionQueueManager
  private let updater = SparkleUpdater()

  private var isAnnotationDemoUITesting: Bool {
    Self.hasLaunchArgument("--ui-testing-annotation-demo")
      || Self.hasLaunchEnvironment("ABP_UI_TESTING_ANNOTATION_DEMO")
  }

  private var isSubtitleEditUITesting: Bool {
    Self.hasLaunchArgument("--ui-testing-subtitle-edit")
      || Self.hasLaunchEnvironment("ABP_UI_TESTING_SUBTITLE_EDIT")
  }

  private var isTranscriptScrollUITesting: Bool {
    Self.hasLaunchArgument("--ui-testing-transcript-scroll")
      || Self.hasLaunchEnvironment("ABP_UI_TESTING_TRANSCRIPT_SCROLL")
  }

  private static func hasLaunchArgument(_ argument: String) -> Bool {
    ProcessInfo.processInfo.arguments.contains(argument)
  }

  private static func hasLaunchEnvironment(_ key: String) -> Bool {
    guard let value = ProcessInfo.processInfo.environment[key] else { return false }
    return value == "1" || value.lowercased() == "true"
  }

  init() {
    let isUITesting =
      Self.hasLaunchArgument("--ui-testing")
        || Self.hasLaunchEnvironment("ABP_UI_TESTING")
    let isSubtitleEditUITesting =
      Self.hasLaunchArgument("--ui-testing-subtitle-edit")
        || Self.hasLaunchEnvironment("ABP_UI_TESTING_SUBTITLE_EDIT")

    if isSubtitleEditUITesting {
      _ = KeyboardInputSourceManager.selectEnglishInputSource()
    }

    URLSessionProxyInjector.install(settings: proxySettings)

    if !isUITesting {
      let config = TelemetryDeck.Config(appID: "A4A99FD4-3F84-49FA-AF97-0806D61D0539")
      TelemetryDeck.initialize(config: config)
    }

    do {
      if !isUITesting {
        SentrySDK.start { (options: Sentry.Options) in
          options.dsn =
            "https://0e00826ef2b3fbc195fb428a468fd995@o4504292283580416.ingest.us.sentry.io/4510502660341760"
          options.debug = false
          options.enableAppHangTracking = false
          options.sendDefaultPii = true
        }
      }

      let schema = Schema([
        ABFile.self,
        LoopSegment.self,
        ListeningSession.self,
        PlaybackRecord.self,
        Folder.self,
        SubtitleFile.self,
        Transcription.self,
        Vocabulary.self,
        AnnotationStylePreset.self,
        TextAnnotationGroup.self,
        TextAnnotationSpan.self,
        TextAnnotationGroupV2.self,
        TextAnnotationSpanV2.self,
        NoteCollection.self,
        Note.self,
        NoteEntry.self,
        NoteAnnotationLink.self,
      ])

      guard let appSupportDir = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first else {
        throw CocoaError(.fileNoSuchFile, userInfo: [
          NSLocalizedDescriptionKey: "Application Support directory not found",
        ])
      }
      let folderName = Bundle.main.bundleIdentifier ?? "cc.ihugo.app.ABPlayer"

      let storeURL = appSupportDir.appendingPathComponent(
        folderName, isDirectory: true
      )
      .appendingPathComponent("ABPlayer.sqlite")

      if isUITesting {
        try Self.deletePersistentStoreIfNeeded(at: storeURL)
      } else if Self.shouldResetLegacyPersistentStoreForCurrentVersion() {
        try Self.deletePersistentStoreIfNeeded(at: storeURL)
        Self.markLegacyPersistentStoreResetCompleted()
      }

      let modelConfiguration = ModelConfiguration(url: storeURL)
      modelContainer = try ModelContainer(for: schema, configurations: modelConfiguration)
      modelContainer.mainContext.autosaveEnabled = true

      sessionTracker = SessionTracker(modelContainer: modelContainer)
      annotationStyleService = AnnotationStyleService(modelContext: modelContainer.mainContext)
      annotationService = AnnotationService(
        modelContext: modelContainer.mainContext,
        styleService: annotationStyleService
      )
      notesBrowserService = NotesBrowserService(modelContext: modelContainer.mainContext)

      queueManager = TranscriptionQueueManager(
        transcriptionManager: transcriptionManager,
        settings: transcriptionSettings
      )
      queueManager.modelContext = modelContainer.mainContext
      playerManager.playerSettings = playerSettings

      KeyboardShortcuts.onKeyUp(for: .playPause) { [playerManager] in
        Task { @MainActor in
          await playerManager.togglePlayPause()
        }
      }

      KeyboardShortcuts.onKeyUp(for: .rewind5s) { [playerManager] in
        Task { @MainActor in
          await playerManager.seek(to: -5)
        }
      }

      KeyboardShortcuts.onKeyUp(for: .forward10s) { [playerManager] in
        Task { @MainActor in
          await playerManager.seek(to: 10)
        }
      }

      KeyboardShortcuts.onKeyUp(for: .setPointA) { [playerManager] in
        Task { @MainActor in
          playerManager.setPointA()
        }
      }

      KeyboardShortcuts.onKeyUp(for: .setPointB) { [playerManager] in
        Task { @MainActor in
          playerManager.setPointB()
        }
      }

      KeyboardShortcuts.onKeyUp(for: .clearLoop) { [playerManager] in
        Task { @MainActor in
          playerManager.clearLoop()
        }
      }

      KeyboardShortcuts.onKeyUp(for: .saveSegment) { [playerManager] in
        Task { @MainActor in
          _ = playerManager.saveCurrentSegment()
        }
      }

      KeyboardShortcuts.onKeyUp(for: .previousSegment) { [playerManager] in
        Task { @MainActor in
          playerManager.selectPreviousSegment()
        }
      }

      KeyboardShortcuts.onKeyUp(for: .nextSegment) { [playerManager] in
        Task { @MainActor in
          playerManager.selectNextSegment()
        }
      }

      KeyboardShortcuts.onKeyUp(for: .counterIncrement) {
        Task { @MainActor in
          CounterPlugin.shared.increment()
        }
      }

      KeyboardShortcuts.onKeyUp(for: .counterDecrement) {
        Task { @MainActor in
          CounterPlugin.shared.decrement()
        }
      }

      KeyboardShortcuts.onKeyUp(for: .counterReset) {
        Task { @MainActor in
          CounterPlugin.shared.reset()
        }
      }

    } catch {
      fatalError("Failed to create model container: \(error)")
    }
  }

  private static func deletePersistentStoreIfNeeded(at storeURL: URL) throws {
    let fileManager = FileManager.default
    let storeDirectoryURL = storeURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: storeDirectoryURL,
      withIntermediateDirectories: true
    )

    let storeFiles = ["", "-wal", "-shm"]
    for suffix in storeFiles {
      let fileURL = URL(fileURLWithPath: storeURL.path + suffix)
      guard fileManager.fileExists(atPath: fileURL.path) else { continue }
      try fileManager.removeItem(at: fileURL)
      Logger.data.notice("Removed persistent store file: \(fileURL.lastPathComponent, privacy: .public)")
    }
  }

  private static func shouldResetLegacyPersistentStoreForCurrentVersion() -> Bool {
    let hasReset = UserDefaults.standard.bool(
      forKey: UserDefaultsKey.legacyPersistentStoreResetCompleted
    )
    guard !hasReset else { return false }

    let targetVersion = "0.2.17"
    let currentVersion =
      (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        ?? "0.0.0"

    return currentVersion.compare(targetVersion, options: .numeric) == .orderedAscending
  }

  private static func markLegacyPersistentStoreResetCompleted() {
    UserDefaults.standard.set(true, forKey: UserDefaultsKey.legacyPersistentStoreResetCompleted)
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if isTranscriptScrollUITesting {
          TranscriptScrollDemoView()
        } else if isSubtitleEditUITesting {
          SubtitleEditDemoView()
        } else if isAnnotationDemoUITesting {
          AnnotationMenuDemoView()
        } else {
          MainSplitView()
        }
      }
      .focusEffectDisabled()
      .onChange(of: playerSettings.preventSleep) {
        playerManager.updateSleepPrevention()
      }
      .environment(playerManager)
      .environment(sessionTracker)
      .environment(transcriptionManager)
      .environment(transcriptionSettings)
      .environment(librarySettings)
      .environment(playerSettings)
      .environment(proxySettings)
      .environment(queueManager)
      .environment(annotationStyleService)
      .environment(annotationService)
      .environment(notesBrowserService)
      .environment(subtitleLoader)
    }
    .defaultSize(width: 1600, height: 900)
    .windowResizability(.contentSize)
    .modelContainer(modelContainer)
    .commands {
      SettingsCommands()
      NotesBrowserCommands()
      PluginCommands()
      CommandGroup(replacing: .appInfo) {
        Button("About ABPlayer") {
          NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
              string: "Developed by Sunset Valley",
              attributes: [
                NSAttributedString.Key.font: NSFont.systemFont(
                  ofSize: 11
                ),
              ]
            ),
          ])
        }

        Button("Check for Updates...") {
          updater.checkForUpdates()
        }
      }
    }

    #if os(macOS)
      WindowGroup(id: "settings-window") {
        SettingsView()
          .environment(transcriptionSettings)
          .environment(librarySettings)
          .environment(playerSettings)
          .environment(proxySettings)
          .environment(annotationStyleService)
          .environment(transcriptionManager)
          .environment(updater)
      }
      .defaultPosition(.center)
      .commandsRemoved()

      WindowGroup(id: "annotation-style-manager") {
        AnnotationStyleManagerView()
          .environment(annotationStyleService)
          .environment(annotationService)
      }
      .defaultSize(width: 640, height: 480)
      .defaultPosition(.center)
      .commandsRemoved()

      WindowGroup(id: "notes-browser") {
        NotesBrowserView()
          .environment(notesBrowserService)
      }
      .defaultSize(width: 1280, height: 820)
      .defaultPosition(.center)
      .commandsRemoved()
    #endif
  }
}

// MARK: - Plugin Commands

struct PluginCommands: Commands {
  var body: some Commands {
    CommandMenu("Plugins") {
      ForEach(PluginManager.shared.plugins, id: \.id) { plugin in
        Button(plugin.name) {
          plugin.open()
        }
      }
    }
  }
}

// MARK: - Notes Browser Commands

struct NotesBrowserCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("Window") {
      Button("Notes Browser") {
        openWindow(id: "notes-browser")
      }
      .keyboardShortcut("n", modifiers: [.command, .shift])
    }
  }
}

// MARK: - Settings Commands

struct SettingsCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings...") {
        openWindow(id: "settings-window")
      }
      .keyboardShortcut(",", modifiers: .command)
    }
  }
}

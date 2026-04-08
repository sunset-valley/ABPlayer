import KeyboardShortcuts
import OSLog
import Sentry
import SwiftData
import TelemetryDeck

@MainActor
final class AppDependencyContainer {
  let modelContainer: ModelContainer
  let playerManager: PlayerManager
  let sessionTracker: SessionTracker
  let transcriptionManager: TranscriptionManager
  let transcriptionSettings: TranscriptionSettings
  let librarySettings: LibrarySettings
  let playerSettings: PlayerSettings
  let proxySettings: ProxySettings
  let annotationStyleService: AnnotationStyleService
  let annotationService: AnnotationService
  let notesBrowserService: NotesBrowserService
  let listeningStatsService: ListeningStatsService
  let subtitleLoader: SubtitleLoader
  let queueManager: TranscriptionQueueManager
  #if !APPSTORE
    let updater: SparkleUpdater
  #endif

  init(isUITesting: Bool) throws {
    let proxySettings = ProxySettings()
    let transcriptionManager = TranscriptionManager()
    let transcriptionSettings = TranscriptionSettings()
    let librarySettings = LibrarySettings()
    let playerSettings = PlayerSettings()
    let playerManager = PlayerManager(librarySettings: librarySettings)
    let subtitleLoader = SubtitleLoader(librarySettings: librarySettings)
    #if !APPSTORE
      let updater = SparkleUpdater()
    #endif

    URLSessionProxyInjector.install(settings: proxySettings)

    librarySettings.beginLibraryAccessSession()

    if !isUITesting {
      let config = TelemetryDeck.Config(appID: "A4A99FD4-3F84-49FA-AF97-0806D61D0539")
      TelemetryDeck.initialize(config: config)

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
    let storeURL = appSupportDir
      .appendingPathComponent(folderName, isDirectory: true)
      .appendingPathComponent("ABPlayer.sqlite")

    if isUITesting {
      try Self.deletePersistentStoreIfNeeded(at: storeURL)
    } else if Self.shouldResetLegacyPersistentStoreForCurrentVersion() {
      try Self.deletePersistentStoreIfNeeded(at: storeURL)
      Self.markLegacyPersistentStoreResetCompleted()
    }

    let modelConfiguration = ModelConfiguration(url: storeURL)
    let modelContainer = try ModelContainer(for: schema, configurations: modelConfiguration)
    modelContainer.mainContext.autosaveEnabled = true

    let sessionTracker = SessionTracker(modelContainer: modelContainer)
    let annotationStyleService = AnnotationStyleService(modelContext: modelContainer.mainContext)
    let annotationService = AnnotationService(
      modelContext: modelContainer.mainContext,
      styleService: annotationStyleService
    )
    let notesBrowserService = NotesBrowserService(modelContext: modelContainer.mainContext)
    let listeningStatsService = ListeningStatsService(modelContext: modelContainer.mainContext)

    let queueManager = TranscriptionQueueManager(
      transcriptionManager: transcriptionManager,
      settings: transcriptionSettings,
      subtitleLoader: subtitleLoader,
      librarySettings: librarySettings
    )
    queueManager.modelContext = modelContainer.mainContext
    playerManager.playerSettings = playerSettings

    self.modelContainer = modelContainer
    self.playerManager = playerManager
    self.sessionTracker = sessionTracker
    self.transcriptionManager = transcriptionManager
    self.transcriptionSettings = transcriptionSettings
    self.librarySettings = librarySettings
    self.playerSettings = playerSettings
    self.proxySettings = proxySettings
    self.annotationStyleService = annotationStyleService
    self.annotationService = annotationService
    self.notesBrowserService = notesBrowserService
    self.listeningStatsService = listeningStatsService
    self.subtitleLoader = subtitleLoader
    self.queueManager = queueManager
    #if !APPSTORE
      self.updater = updater
    #endif

    Self.registerKeyboardShortcuts(playerManager: playerManager)
  }

  // MARK: - Keyboard Shortcuts

  private static func registerKeyboardShortcuts(playerManager: PlayerManager) {
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
  }

  // MARK: - Persistent Store Helpers

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
      do {
        try fileManager.removeItem(at: fileURL)
        Logger.data.notice("Removed persistent store file: \(fileURL.lastPathComponent, privacy: .public)")
      } catch let error as NSError where error.code == NSFileNoSuchFileError {
        continue
      }
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
}

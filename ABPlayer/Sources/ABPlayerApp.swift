import SwiftUI

@main
struct ABPlayerApp: App {
  @Environment(\.scenePhase) private var scenePhase

  private let container: AppDependencyContainer
  private let uiFlags: UITestingFlags

  init() {
    let uiFlags = UITestingFlags()
    self.uiFlags = uiFlags

    if uiFlags.isSubtitleEdit {
      _ = KeyboardInputSourceManager.selectEnglishInputSource()
    }

    do {
      container = try AppDependencyContainer(isUITesting: uiFlags.isAny)
    } catch {
      fatalError("Failed to initialize app dependencies: \(error)")
    }
  }

  var body: some Scene {
    mainWindowScene
    #if os(macOS)
      settingsWindowScene
      annotationStyleManagerWindowScene
      notesBrowserWindowScene
      listeningStatsWindowScene
    #endif
  }

  @ViewBuilder
  private var mainWindowRootView: some View {
    if uiFlags.isTranscriptScroll {
      TranscriptScrollDemoView()
    } else if uiFlags.isVideoSubtitleToggle {
      VideoSubtitleToggleDemoView()
    } else if uiFlags.isSubtitleEdit {
      SubtitleEditDemoView()
    } else if uiFlags.isSubtitlePlaybackAnnotation {
      SubtitlePlaybackAnnotationDemoView()
    } else if uiFlags.isAnnotationDemo {
      AnnotationMenuDemoView()
    } else if uiFlags.isNotesExport {
      NotesBrowserExportDemoView()
    } else if uiFlags.isListeningStats {
      ListeningStatsDemoView()
    } else {
      MainSplitView()
    }
  }

  private var mainWindowScene: some Scene {
    WindowGroup {
      mainWindowRootView
        .focusEffectDisabled()
        .onChange(of: container.playerSettings.preventSleep) {
          container.playerManager.updateSleepPrevention()
        }
        .environment(container.playerManager)
        .environment(container.sessionTracker)
        .environment(container.transcriptionManager)
        .environment(container.transcriptionSettings)
        .environment(container.librarySettings)
        .environment(container.playerSettings)
        .environment(container.proxySettings)
        .environment(container.queueManager)
        .environment(container.annotationStyleService)
        .environment(container.annotationService)
        .environment(container.notesBrowserService)
        .environment(container.listeningStatsService)
        .environment(container.subtitleLoader)
    }
    .defaultSize(width: 1600, height: 900)
    .windowResizability(.contentSize)
    .modelContainer(container.modelContainer)
    .commands {
      SettingsCommands()
      NotesBrowserCommands()
      CommandGroup(replacing: .appInfo) {
        Button("About ABPlayer") {
          NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
              string: "Developed by Sunset Valley",
              attributes: [
                NSAttributedString.Key.font: NSFont.systemFont(ofSize: 11),
              ]
            ),
          ])
        }

        Button("Check for Updates...") {
          container.updater.checkForUpdates()
        }
      }
    }
  }

  private var settingsWindowScene: some Scene {
    WindowGroup(id: "settings-window") {
      SettingsView()
        .environment(container.transcriptionSettings)
        .environment(container.librarySettings)
        .environment(container.playerSettings)
        .environment(container.proxySettings)
        .environment(container.annotationStyleService)
        .environment(container.transcriptionManager)
        .environment(container.updater)
    }
    .defaultPosition(.center)
    .commandsRemoved()
  }

  private var annotationStyleManagerWindowScene: some Scene {
    WindowGroup(id: "annotation-style-manager") {
      AnnotationStyleManagerView()
        .environment(container.annotationStyleService)
        .environment(container.annotationService)
    }
    .defaultSize(width: 640, height: 480)
    .defaultPosition(.center)
    .commandsRemoved()
  }

  private var notesBrowserWindowScene: some Scene {
    Window("Notes Browser", id: "notes-browser") {
      NotesBrowserView()
        .environment(container.annotationStyleService)
        .environment(container.annotationService)
        .environment(container.notesBrowserService)
    }
    .defaultSize(width: 1280, height: 820)
    .defaultPosition(.center)
    .commandsRemoved()
  }

  private var listeningStatsWindowScene: some Scene {
    Window("Daily Listening Time", id: "listening-stats") {
      ListeningStatsView()
        .environment(container.listeningStatsService)
    }
    .defaultSize(width: 980, height: 620)
    .defaultPosition(.center)
    .commandsRemoved()
  }
}

// MARK: - UI Testing Flags

private struct UITestingFlags {
  let isAny: Bool
  let isAnnotationDemo: Bool
  let isSubtitleEdit: Bool
  let isSubtitlePlaybackAnnotation: Bool
  let isTranscriptScroll: Bool
  let isVideoSubtitleToggle: Bool
  let isNotesExport: Bool
  let isListeningStats: Bool

  init() {
    let args = ProcessInfo.processInfo.arguments
    let env = ProcessInfo.processInfo.environment
    isAny = Self.check(args, env, "--ui-testing", "ABP_UI_TESTING")
    isAnnotationDemo = Self.check(args, env, "--ui-testing-annotation-demo", "ABP_UI_TESTING_ANNOTATION_DEMO")
    isSubtitleEdit = Self.check(args, env, "--ui-testing-subtitle-edit", "ABP_UI_TESTING_SUBTITLE_EDIT")
    isSubtitlePlaybackAnnotation = Self.check(
      args, env,
      "--ui-testing-subtitle-playback-annotation",
      "ABP_UI_TESTING_SUBTITLE_PLAYBACK_ANNOTATION")
    isTranscriptScroll = Self.check(args, env, "--ui-testing-transcript-scroll", "ABP_UI_TESTING_TRANSCRIPT_SCROLL")
    isVideoSubtitleToggle = Self.check(args, env, "--ui-testing-video-subtitle-toggle", "ABP_UI_TESTING_VIDEO_SUBTITLE_TOGGLE")
    isNotesExport = Self.check(args, env, "--ui-testing-notes-export", "ABP_UI_TESTING_NOTES_EXPORT")
    isListeningStats = Self.check(args, env, "--ui-testing-listening-stats", "ABP_UI_TESTING_LISTENING_STATS")
  }

  private static func check(
    _ args: [String], _ env: [String: String], _ argument: String, _ envKey: String
  ) -> Bool {
    if args.contains(argument) { return true }
    guard let value = env[envKey] else { return false }
    return value == "1" || value.lowercased() == "true"
  }
}

// MARK: - Notes Browser Commands

struct NotesBrowserCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("Study") {
      Button("Notes Browser") {
        openWindow(id: "notes-browser")
      }
      .keyboardShortcut("n", modifiers: [.command, .shift])

      Button("Daily Listening Time") {
        openWindow(id: "listening-stats")
      }
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

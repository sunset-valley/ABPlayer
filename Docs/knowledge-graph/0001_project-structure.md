# ABPlayer Architecture Overview

## Summary

ABPlayer is a macOS SwiftUI application for audio/video playback with subtitle display, on-device transcription (WhisperKit), and text annotation. The architecture follows MVVM with `@Observable` services injected via SwiftUI `.environment()`. All UI state lives on `@MainActor`; heavy I/O (SwiftData writes, file parsing) runs on background actors or detached tasks. For paths, build commands, and target configuration see [CLAUDE.md](../../CLAUDE.md).

## Details

### Layer Diagram

```
┌─────────────────────────────────────────────────────┐
│  Views/          SwiftUI + NSViewRepresentable       │
│  (reads @Observable state, dispatches user intent)   │
├─────────────────────────────────────────────────────┤
│  ViewModels/     @Observable @MainActor              │
│  (presentation logic, coordinates multiple services) │
├─────────────────────────────────────────────────────┤
│  Services/       @Observable @MainActor              │
│  (business logic, external I/O, settings)            │
├─────────────────────────────────────────────────────┤
│  Models/         @Model (SwiftData) + value types    │
│  (persisted domain objects, no business logic)       │
└─────────────────────────────────────────────────────┘
```

Dependencies flow **downward only**: Views → ViewModels → Services → Models.

### Module Responsibilities

| Module | Role | Key Types |
|--------|------|-----------|
| **Models/** | SwiftData `@Model` entities and value types | `ABFile`, `Folder`, `Vocabulary`, `TextAnnotation`, `Transcription`, `SubtitleFile`, `PlaybackRecord`, `LoopSegment`, `ListeningSession` |
| **Services/** | Business logic, external I/O, state management | `PlayerManager`, `TranscriptionManager`, `TranscriptionQueueManager`, `AnnotationService`, `SubtitleLoader`, `SessionTracker` |
| **Services/PlayerManager/** | Playback engine with AB-loop and segment support | `PlayerManager` (coordinator), `PlayerEngine` (AVPlayer wrapper), `PlayerEngineProtocol` (testable boundary) |
| **Services/FolderNavigation** | Sub-services delegated from `FolderNavigationViewModel` | `NavigationService` (folder stack), `SelectionStateService` (selection + UserDefaults persistence), `DeletionService` (file/folder delete), `ImportService` (import + refresh) |
| **Services/*Settings** | UserDefaults-backed preferences | `TranscriptionSettings`, `PlayerSettings`, `LibrarySettings`, `ProxySettings` |
| **Services/URLSessionProxyInjector** | Installs global URLSession proxy via method swizzling so WhisperKit and swift-transformers route through the configured proxy at startup | `URLSessionProxyInjector.install(settings:)` called once in `ABPlayerApp.init()` |
| **ViewModels/** | Presentation logic binding Services to Views | `BasePlayerViewModel` (shared), `Audio/VideoPlayerViewModel`, `TranscriptionViewModel`, `MainSplitViewModel` (split layout + pane allocation), `FolderNavigationViewModel` (delegates sub-concerns to folder-navigation services) |
| **Views/** | SwiftUI screens and AppKit-bridged components | Split layout, player views, subtitle overlay, settings panels |
| **Views/TextView/** | Custom transcript renderer (NSTextView-backed) | `TranscriptTextView` (unified multi-cue), `AnnotatedTextView` (per-cue), `ECTextNativeView` |
| **Plugins/** | Extensible plugin system | `Plugin` protocol, `PluginManager` (registry), `CounterPlugin` (sample) |
| **Design/** | Font token (`Font.sm`) and semantic view modifiers (`bodyStyle()`, `captionStyle()`) | `Typography.swift` |
| **Utils/** | Small helpers | `SortingUtility`, `URL+Unique` |

### Dependency Injection

`ABPlayerApp.init()` is the single wiring point. All services are created there and passed to the view tree via `.environment()`:

```
ABPlayerApp (creates & owns all services)
  ├─ ModelContainer → .modelContainer() modifier
  ├─ PlayerManager, SessionTracker, SubtitleLoader
  ├─ TranscriptionManager, TranscriptionQueueManager, TranscriptionSettings
  ├─ AnnotationService(modelContext)
  ├─ LibrarySettings, PlayerSettings, ProxySettings
  └─ SparkleUpdater
       ↓  .environment(...)
  Views consume via @Environment(ServiceType.self)
```

ViewModels that need multiple dependencies receive them via constructor injection (e.g. `FolderNavigationViewModel(modelContext:playerManager:librarySettings:)`).

### Concurrency Model

| Isolation | Used By | Purpose |
|-----------|---------|---------|
| `@MainActor` | All Services, all ViewModels, all Settings | UI state safety; SwiftUI observation requires main thread |
| `@ModelActor` | `SessionTracker.SessionRecorder` | Background SwiftData writes for listening sessions |
| `Task.detached` | `SubtitleLoader`, `TranscriptionManager` | File parsing, audio extraction off main thread |
| Background `actor` | `PlayerEngine` | AVPlayer time observer callbacks, audio I/O |

Pattern: UI state mutations always happen on `@MainActor`. Heavy I/O dispatches to background, then posts results back via `@MainActor`-isolated closures.

### Data Persistence (SwiftData)

9 `@Model` types share a single `ModelContainer` (SQLite at `~/Library/Application Support/{bundleID}/ABPlayer.sqlite`):

```
ABFile ──┬── playbackRecord: PlaybackRecord?  (cascade delete)
         ├── segments: [LoopSegment]
         ├── subtitleFile: SubtitleFile?
         └── folder: Folder?

Folder ──┬── subfolders: [Folder]
         └── audioFiles: [ABFile]

Transcription (linked via audioFileId: String)
TextAnnotation (linked via cueID: UUID)
Vocabulary (unique word, difficulty tracking)
ListeningSession (duration, timestamps)
```

Services that need DB access receive `ModelContext` at init. `SessionRecorder` uses a dedicated `@ModelActor` context to avoid blocking the main thread.

### External Dependencies

| Framework | Purpose | Used In |
|-----------|---------|---------|
| **WhisperKit** | On-device speech-to-text | `TranscriptionManager` |
| **SwiftData** | Persistence | All Models, services with DB access |
| **AVFoundation** | Audio/video playback | `PlayerEngine` |
| **Sparkle** | Auto-update | `ABPlayerApp` (`SparkleUpdater`) |
| **Sentry** | Error tracking | `ABPlayerApp.init()` |
| **TelemetryDeck** | Analytics | `ABPlayerApp.init()` |
| **KeyboardShortcuts** | Global hotkeys | `ABPlayerApp` (9 shortcuts) |

### Key Protocols

- **`PlayerEngineProtocol`** — Actor protocol abstracting AVPlayer. Enables `PlayerManager` to be tested with a mock engine. Exposes callbacks (`onTimeUpdate`, `onLoopCheck`, `onPlaybackStateChange`) instead of direct state access.
- **`Plugin`** — `@MainActor protocol Plugin: Identifiable` with `name`, `icon`, `open()`. Managed by `PluginManager` singleton registry.

---

### Core Data Flows

#### 1. Playback

```
User tap → ViewModel.togglePlayPause()
  → PlayerManager.play/pause()
    → PlayerEngine (AVPlayer, background actor)
      → onTimeUpdate callback (0.1s interval)
    → PlayerManager updates observable state (isPlaying, currentTime, duration)
  → Views re-render
```

**AB-Loop**: `PlayerManager` holds `pointA`/`pointB`. The engine's `onLoopCheck` fires every 0.1s; when `currentTime >= pointB`, it seeks back to `pointA`. Segments persist loop points to `LoopSegment` in SwiftData.

**Queue**: `PlaybackQueue` manages file ordering with loop modes (none, repeatOne, repeatAll, shuffle, autoPlayNext). `PlayerManager.handlePlaybackEnded()` respects the mode and auto-advances.

#### 2. Transcription Pipeline

```
User trigger → TranscriptionQueueManager.enqueue(audioFile)
  → processQueue() (one task at a time)
    → TranscriptionManager.transcribe(audioURL, settings)
      → download model if needed (progress tracking)
      → extract audio for video files in-process (AVAssetReader -> WAV)
      → WhisperKit.transcribe() → [TranscriptionResult]
      → map to [SubtitleCue]
    → write .srt file + upsert Transcription record
  → UI observes task status changes
```

`TranscriptionSettings` configures model selection (tiny→large-v3), language, model directory, auto-transcribe, pause-after-lookup behavior, and download endpoint (official/HuggingFace mirror/custom). For the current media extraction details, see [0010_transcription-media-extraction.md](./0010_transcription-media-extraction.md).

#### 3. Subtitle Display

```
SubtitleLoader.loadSubtitles(for: ABFile)
  → resolve media URL from LibrarySettings.libraryDirectoryURL + ABFile.relativePath
  → derive sibling .srt path from media basename
  → SubtitleParser.parse() (detects .srt/.vtt, background thread)
  → [SubtitleCue] → TranscriptionViewModel.cachedCues
    → TranscriptTextView (single NSTextView for all cues, enables cross-cue selection)
      → AnnotatedStringBuilder applies annotation color highlights
      → auto-scrolls to active cue based on PlayerManager.currentTime
```

#### 4. Annotation & Vocabulary

```
User selects text in TranscriptTextView
  → CrossCueTextSelection → show AnnotationMenuView popover
  → user picks type (vocabulary / collocation / goodSentence)
    → AnnotationService.addAnnotation() → SwiftData insert
    → version counter increments → views rebuild attributed string with colors

VocabularyService:
  → normalized word lookup in cached map
  → tracks forgotCount / rememberedCount → difficultyLevel
```

#### 5. Navigation & Selection

`FolderNavigationViewModel` delegates each concern to a dedicated sub-service:

```
NavigationService        → folder stack (navigateInto / navigateBack), currentFolder, navigationPath
SelectionStateService    → current file/folder selection, persists IDs to UserDefaults for restore on relaunch
DeletionService          → delete file or folder (optionally from disk), player/selection cleanup
ImportService            → import from file picker, folder refresh; fires onImportCompleted callback
  → callback bumps FolderNavigationViewModel.refreshToken → invalidates currentFolders()/currentAudioFiles()

Selection change → PlayerManager file load + subtitle load
MainSplitViewModel.restoreLastSelectionIfNeeded() → restores navigation path + file selection on launch
```

Permission boundary note:

- Media access is **library-scoped**. `LibrarySettings` is the only permission owner.
- `ABFile.relativePath` and `Folder.relativePath` are the source of truth for path resolution.
- Bookmark fields in models are retained only for store compatibility and are not used by active media flows.

`MainSplitViewModel` manages per-media-type pane allocation:

```
PaneContent (allocatable tabs: transcription, segments, …)
  → leftTabs / rightTabs: ordered tab lists for bottomLeft / right pane
  → leftSelection / rightSelection: active tab per pane
  → all state persisted to UserDefaults keyed by mediaType (audio/video)
  → switchMediaType() swaps full layout state on audio↔video switch
  → sanitizeAllocations() prevents duplicates and overlap between panes
```

### Test Coverage

Tests live in `ABPlayer/Tests/` and cover:

- **Business logic**: looping, timestamp parsing, formatting, sorting, session tracking (`BusinessLogicTests`)
- **Player integration**: queue ordering, selection behavior (`ABPlayerTests`)
- **Subtitle interaction**: playback-follow, edit behavior (`SubtitleViewModelTests`)
- **Annotations**: service CRUD, domain model (`AnnotationServiceTests`, `TextAnnotationTests`)
- **Transcript rendering**: attributed string building, cross-cue selection, cue layout (`AnnotatedStringBuilderTests`, `UnifiedStringBuilderTests`, `CrossCueTextSelectionTests`, `CueLayoutTests`)
- **Transcription**: state machine, settings, manager logic (`TranscriptionTests`)

UI tests live in `ABPlayer/UITests/` and are a required quality gate:

- **Annotation menu interaction**: add style, rename style, kind switch, and delete protection (`AnnotationMenuUITests`)
- **Run command**: `tuist test -- -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData"`

## Related Docs

- [Agent entry and rule map](../../CLAUDE.md)
- [Build/test target configuration](../../Project.swift)
- [Getting started and product overview](../../README.md)

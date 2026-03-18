# ABPlayer 代码结构详解

> 基于代码库实际状态梳理（2026-03-17）。`01_Architecture.md` 中部分文件路径已过时，以本文档为准。

---

## 目录

1. [文件目录结构](#文件目录结构)
2. [线程模型](#线程模型)
3. [依赖注入与生命周期](#依赖注入与生命周期)
4. [MVVM 层边界](#mvvm-层边界)
5. [核心数据流](#核心数据流)
6. [并发架构](#并发架构)
7. [插件系统](#插件系统)

---

## 文件目录结构

```
ABPlayer/Sources/
├── ABPlayerApp.swift                   # App 入口：DI 容器 + 快捷键注册
│
├── Design/
│   ├── Theme.swift                     # 颜色 token
│   └── Typography.swift                # 字体样式
│
├── Models/                             # SwiftData @Model 数据层
│   ├── AudioModels.swift               # ABFile, LoopSegment
│   ├── Folder.swift                    # 嵌套文件夹
│   ├── PlaybackRecord.swift            # 播放位置记录（cascade delete）
│   ├── ListeningSession.swift          # 练习时间会话
│   ├── SubtitleFile.swift              # 字幕 + SRT/VTT 解析器
│   ├── Transcription.swift             # AI 转录缓存
│   ├── Vocabulary.swift                # 词汇学习记录
│   └── DeterministicID.swift          # 基于路径的幂等 UUID 生成
│
├── Services/                           # 业务逻辑层
│   ├── PlayerManager/
│   │   ├── PlayerManager.swift         # @MainActor 播放状态机（原 AudioPlayerManager）
│   │   ├── PlayerEngine.swift          # background actor，封装 AVPlayer
│   │   ├── PlayerEngineProtocol.swift  # 可 mock 的引擎接口
│   │   ├── AudioPlayerManager+Loop.swift       # A-B loop 扩展
│   │   └── AudioPlayerManager+Segments.swift   # 段落管理扩展
│   ├── SessionTracker.swift            # 练习时间累积（主线程缓冲 + 后台写入）
│   ├── TranscriptionManager.swift      # WhisperKit 集成
│   ├── TranscriptionQueueManager.swift # 转录任务队列
│   ├── FolderImporter.swift            # 递归导入 + 自动配对
│   ├── SubtitleLoader.swift            # 字幕加载服务
│   ├── VocabularyService.swift         # 词汇难度追踪
│   ├── PlaybackQueue.swift             # 播放队列（随机/顺序/重复）
│   ├── PlayerSettings.swift            # 播放偏好持久化
│   ├── TranscriptionSettings.swift     # 转录配置持久化
│   ├── LibrarySettings.swift           # 库路径管理
│   ├── NavigationService.swift         # 文件夹导航状态
│   ├── SelectionStateService.swift     # 多视图文件选中同步
│   ├── DeletionService.swift           # 安全删除（文件+DB）
│   └── ShortcutNames.swift             # 快捷键名称常量
│
├── ViewModels/
│   ├── AudioPlayerViewModel.swift      # 音频播放 UI 状态
│   ├── VideoPlayerViewModel.swift      # 视频播放 UI 状态
│   ├── TranscriptionViewModel.swift    # 转录进度 UI 状态
│   ├── FolderNavigationViewModel.swift # 文件夹树 + 排序状态
│   └── MainSplitViewModel.swift        # 主窗口协调（播放队列同步、文件导入）
│
├── Views/
│   ├── MainSplitView.swift             # 三栏根布局
│   ├── AudioPlayerView.swift           # 音频播放器
│   ├── VideoPlayerView.swift           # 视频播放器
│   ├── FolderNavigationView.swift      # 侧边栏
│   ├── TranscriptionView.swift         # AI 转录面板
│   ├── SubtitleView.swift              # 字幕面板
│   ├── PDFContentView.swift            # PDF 阅读
│   ├── SettingsView.swift              # 偏好设置
│   ├── NativeVideoPlayer.swift         # AVPlayer NSView 包装
│   ├── VideoFullscreenPresenter.swift  # 全屏管理
│   ├── Components/                     # 18 个可复用组件
│   │   ├── AudioProgressView.swift
│   │   ├── VideoProgressView.swift
│   │   ├── SegmentsSection.swift
│   │   ├── FolderNavigationHeaderView.swift
│   │   ├── FolderRowView.swift
│   │   ├── FileRowView.swift
│   │   ├── VolumeControl.swift
│   │   ├── VideoControlsView.swift
│   │   ├── VideoTimeDisplay.swift
│   │   ├── EmptyStateView.swift
│   │   ├── FPSMonitor.swift            # Debug FPS 计数器
│   │   ├── ResizableSplitPanel.swift
│   │   ├── MainSplitDetailView.swift
│   │   ├── MainSplitPaneContentView.swift
│   │   ├── MainSplitSidebarView.swift
│   │   ├── PaneContent.swift
│   │   ├── ThreePanelLayout.swift
│   │   ├── DynamicPaneView.swift
│   │   └── ResizePlaceholder.swift
│   └── Subtitle/                       # 交互式字幕 UI
│       ├── SubtitleEditView.swift
│       ├── SubtitleViewModel.swift
│       ├── SubtitleCueRow.swift
│       ├── Components/
│       │   ├── InteractiveAttributedTextView.swift
│       │   ├── CountdownRingView.swift
│       │   └── WordMenuView.swift
│       ├── Models/
│       │   └── WordVocabularyData.swift
│       └── Utilities/
│           ├── AttributedStringBuilder.swift
│           └── WordLayoutManager.swift
│
├── Plugins/
│   ├── PluginManager.swift
│   ├── PluginProtocol.swift
│   ├── CounterPlugin.swift
│   └── CounterPluginView.swift
│
└── Utils/
    ├── AttributedStringCache.swift     # 字幕富文本缓存（解决渲染性能瓶颈）
    └── SortingUtility.swift            # 文件名字典序排序
```

---

## 线程模型

```
┌────────────────────────────────────────────────────┐
│  Main Thread (@MainActor)                          │
│  PlayerManager · SessionTracker · ViewModels       │
│  Views · NavigationService · SelectionStateService │
└────────────────────────┬───────────────────────────┘
                         │  Task { ... }
          ┌──────────────┴──────────────┐
          ▼                             ▼
┌─────────────────┐         ┌──────────────────────┐
│  PlayerEngine   │         │  SessionRecorder     │
│  (actor)        │         │  (@ModelActor)       │
│  AVPlayer KVO   │         │  SwiftData 写入      │
└─────────────────┘         └──────────────────────┘
```

| 组件 | 隔离方式 | 说明 |
|------|----------|------|
| `PlayerManager` | `@MainActor` | 所有播放状态、UI 可观测属性 |
| `PlayerEngine` | `actor` | AVPlayer 生命周期，KVO 观察通过 `Task { @MainActor }` 回调 |
| `SessionRecorder` | `@ModelActor` | SwiftData 后台写入，避免阻塞主线程 |
| `TranscriptionManager` | `@MainActor` | 转录任务通过 async Task 派发 |

---

## 依赖注入与生命周期

`ABPlayerApp.init()` 统一创建所有服务，通过 `.environment()` 注入视图树：

```swift
// ABPlayerApp.swift
@main struct ABPlayerApp: App {
    let modelContainer: ModelContainer
    let playerManager: PlayerManager
    let sessionTracker: SessionTracker
    let transcriptionManager: TranscriptionManager
    // ...

    init() {
        modelContainer = try! ModelContainer(for: schema)
        playerManager = PlayerManager()
        sessionTracker = SessionTracker()
        sessionTracker.setModelContainer(modelContainer)  // ⚠️ 延迟初始化
        // ...
    }

    var body: some Scene {
        WindowGroup {
            MainSplitView()
                .environment(playerManager)
                .environment(sessionTracker)
                .environment(transcriptionManager)
                // ...
                .modelContainer(modelContainer)
        }
    }
}
```

---

## MVVM 层边界

### 各层职责

| 层 | 类型 | 职责 | 不应包含 |
|----|------|------|----------|
| **Model** | `@Model` class | SwiftData 持久化、关系定义 | UI 逻辑、服务调用 |
| **Service** | `@Observable` class | 业务逻辑、外部 SDK 封装 | SwiftUI 类型、视图状态 |
| **ViewModel** | `@Observable @MainActor` class | UI 状态派生、用户意图路由 | 直接操作 SwiftData |
| **View** | SwiftUI `struct` | 渲染、手势/按钮绑定 | 业务逻辑 |

### 当前边界状态

- **遵守较好**：`PlayerEngine`、`SessionTracker`、`TranscriptionManager` 无 SwiftUI 依赖。
- **存在越界**：
  - `AudioPlayerView` 直接绑定 `@Bindable var audioFile: ABFile`，View 依赖 Model。
  - `MainSplitViewModel` 既协调 `PlayerManager` 等服务，又处理导航状态，职责偏重。

---

## 核心数据流

### 音频播放

```
用户点击播放
    │
    ▼
AudioPlayerView / 快捷键 (ABPlayerApp)
    │  await playerManager.togglePlayPause()
    ▼
PlayerManager (@MainActor)
    ├─ isPlaying / currentTime / duration → View 响应式刷新
    ├─ sessionTracker.addListeningTime(delta)
    └─ await engine.play()
         │
         ▼
    PlayerEngine (actor)
         └─ AVPlayer.play()
              │ KVO rate/status 变化
              ▼
         Task { @MainActor in onPlaybackStateChange(...) }
              │
              ▼
         PlayerManager 更新 isPlaying
```

### A-B 循环

```
setPointA()  →  pointA = currentTime
setPointB()  →  pointB = currentTime, isLooping = true

PlayerEngine 定时回调 (100ms)
    │
    ▼
PlayerManager.handleLoopCheck(seconds)
    if seconds >= pointB → seek(to: pointA)
```

### 练习时间

```
PlayerManager 时间更新 (100ms)
    │  sessionTracker.addListeningTime(0.1)
    ▼
SessionTracker (主线程缓冲)
    bufferedListeningTime += delta
    if now - lastCommitTime > 5s
        │  await recorder.commit(delta)
        ▼
    SessionRecorder (@ModelActor)
        ListeningSession.duration += delta
        modelContext.save()
```

### 文件导入

```
用户选择文件夹
    │
    ▼
FolderImporter.syncFolder(at:)
    ├─ startAccessingSecurityScopedResource()
    ├─ 递归遍历目录
    │   ├─ 音频文件 → ABFile (Security-Scoped Bookmark)
    │   ├─ 同名字幕 → SubtitleFile 自动配对
    │   ├─ 同名 PDF → pdfBookmarkData 关联
    │   └─ 子目录 → 递归 Folder
    └─ modelContext.save()
```

---

## 并发架构

### PlayerEngine 与主线程通信

```swift
// PlayerEngine (background actor) → Main Thread
rateObservation = player.observe(\.rate) { player, _ in
    Task { @MainActor in
        onPlaybackStateChange(player.rate != 0)
    }
}
```

### PlayerManager 调用引擎

```swift
// PlayerManager (@MainActor) → PlayerEngine (actor)
func togglePlayPause() async {
    if isPlaying {
        await engine.pause()
    } else {
        await engine.play()
    }
}
```

### 回调 vs async/await

目前 `PlayerManager` 混用两种模式：

| 方式 | 用途 | 实例 |
|------|------|------|
| 闭包回调 | 引擎事件通知 | `onTimeUpdate`, `onPlaybackEnded`, `onSegmentSaved` |
| async/await | 主动控制操作 | `load()`, `play()`, `pause()`, `seek()` |

---

## 插件系统

`Plugins/` 下有一套简单插件机制（目前仅内置 CounterPlugin）：

```swift
protocol PluginProtocol {
    var id: String { get }
    var name: String { get }
    func view() -> AnyView
}
```

`PluginManager` 维护已注册插件列表，通过 `CounterPluginView` 提供计数器 UI（含快捷键）。插件系统尚未暴露外部扩展入口。

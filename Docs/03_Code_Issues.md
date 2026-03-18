# ABPlayer 代码问题记录

> 梳理时间：2026-03-17。严重程度：🔴 高 / 🟡 中 / 🟢 低。

---

## 目录

1. [崩溃风险（Force Unwrap）](#1-崩溃风险force-unwrap)
2. [架构越界](#2-架构越界)
3. [错误处理不足](#3-错误处理不足)
4. [线程/并发隐患](#4-线程并发隐患)
5. [服务初始化设计缺陷](#5-服务初始化设计缺陷)
6. [回调设计导致可测试性差](#6-回调设计导致可测试性差)
7. [TODO 未完成项](#7-todo-未完成项)
8. [测试覆盖缺口](#8-测试覆盖缺口)
9. [性能关注点](#9-性能关注点)

---

## 1. 崩溃风险（Force Unwrap）

### 🔴 ABPlayerApp.swift — App Support 目录

```swift
// ABPlayerApp.swift
let appSupportDir = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask
).first!   // 极少数情况下返回空数组会崩溃
```

**风险**：在系统目录异常时崩溃，启动即死。
**建议**：
```swift
guard let appSupportDir = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask
).first else {
    // fallback 或 fatalError with message
}
```

---

### 🔴 PlaybackQueue.swift — 空数组随机元素

```swift
let file = files.randomElement()!   // files 为空时崩溃
randomFile = files.randomElement()! // 同上
```

**风险**：随机播放模式下，若队列为空则崩溃。
**建议**：用 `guard let` 处理 nil，或在调用处保证非空后再进入随机逻辑。

---

### 🔴 TranscriptionManager.swift — 音频提取结果

```swift
workingURL = extractedWavURL!   // 提取失败时崩溃
```

**风险**：音频格式不支持或磁盘空间不足时，`extractAudio` 返回 nil，随后 force unwrap 崩溃。
**建议**：
```swift
guard let url = extractedWavURL else {
    throw TranscriptionError.audioExtractionFailed
}
workingURL = url
```

---

### 🟡 PlayerEngine.swift — Security-Scoped 断言

```swift
guard url.startAccessingSecurityScopedResource() else {
    assertionFailure("Unable to access security scoped resource")
    return nil
}
```

**风险**：Debug 构建中断言失败会崩溃；Release 静默返回 nil，调用方收到 nil 后的行为依赖各处 guard，不统一。
**建议**：抛出具体 Error 而非 assertionFailure。

---

## 2. 架构越界

### 🟡 View 直接绑定 Model

```swift
// AudioPlayerView.swift
@Bindable var audioFile: ABFile   // View 直接持有 SwiftData Model
```

**问题**：View 与 Model 层耦合，难以在不启动 SwiftData 的情况下测试 View；Model 字段变更会直接影响 View 编译。
**建议**：引入 `AudioFileDisplayModel`（值类型）作为中间层，由 ViewModel 转换。

---

### 🟡 MainSplitViewModel 职责过重

`MainSplitViewModel` 同时负责：
- 播放队列同步
- 文件导入协调
- 窗口/面板状态管理
- 多 Service 协调（PlayerManager、SessionTracker、FolderImporter 等）

**建议**：拆分为：
- `PlaybackCoordinator`：管理 PlayerManager + PlaybackQueue
- `LibraryCoordinator`：管理 FolderImporter + NavigationService
- `MainSplitViewModel`：仅负责窗口布局状态

---

## 3. 错误处理不足

### 🟡 大量 `try?` 静默吞掉错误

以下调用在失败时不记录任何信息：

| 位置 | 代码 | 影响 |
|------|------|------|
| FolderImporter | `try? extractAudio(...)` | 转录前提取失败无提示 |
| 多处 | `try? modelContext.save()` | DB 写入失败无感知 |
| DeletionService | `try? FileManager.default.removeItem(at:)` | 文件未删除，只删了 DB 记录 |

**建议**：至少在 `try?` 失败时通过 `Sentry.capture` 或日志记录错误上下文。

---

### 🟡 DeletionService — 书签失效时文件未清理

```swift
if let url = file.resolvedURL() {
    try? FileManager.default.removeItem(at: url)  // 书签过期时 url 为 nil，文件留在磁盘
}
// DB 记录仍会被删除
```

**问题**：DB 与磁盘状态不一致，用户以为文件已删除，实际磁盘未清理。
**建议**：检测 `resolvedURL()` 返回 nil 时给用户提示，或记录孤立文件供后续清理。

---

## 4. 线程/并发隐患

### 🟡 SessionTracker 缓冲区时序

```swift
// SessionTracker.swift (@MainActor)
private var bufferedListeningTime: Double = 0

func addListeningTime(_ delta: Double) {
    bufferedListeningTime += delta   // 每 100ms 调用一次
    if shouldCommit {
        Task { await recorder.commit(bufferedListeningTime) }
        bufferedListeningTime = 0
    }
}
```

**潜在问题**：`Task { await recorder.commit(...) }` 是异步的，commit 执行前如果又有新的 `addListeningTime` 调用，`bufferedListeningTime = 0` 已经清空，但新累积的值会在下次 commit 中一起提交，整体不丢数据。但若 commit 失败（DB 异常），这段时间的记录将丢失。
**建议**：commit 后捕获错误并决定是否回滚 bufferedListeningTime。

---

### 🟡 playbackTimeObservers 字典中的闭包捕获

```swift
// PlayerManager.swift
private var playbackTimeObservers: [UUID: @MainActor (Double) -> Void] = [:]
```

存储的闭包若捕获了对外部对象的强引用，且外部对象反过来持有 `PlayerManager`，将形成循环引用。
**建议**：定期审查向此字典注册的所有闭包，确认捕获列表中有 `[weak self]`。

---

## 5. 服务初始化设计缺陷

### 🟡 SessionTracker 延迟设置 ModelContainer

```swift
// ABPlayerApp.swift
sessionTracker = SessionTracker()
sessionTracker.setModelContainer(modelContainer)  // 两步初始化
```

**问题**：两步初始化使 `SessionTracker` 在第一步后处于无效状态，若有代码在 `setModelContainer` 之前调用 `addListeningTime`，数据将被静默丢弃。
**建议**：
```swift
// 单步初始化
sessionTracker = SessionTracker(modelContainer: modelContainer)
```

---

## 6. 回调设计导致可测试性差

### 🟢 PlayerManager 使用闭包回调而非 async/await

```swift
var onSegmentSaved: ((LoopSegment) -> Void)?
var onPlaybackEnded: ((ABFile?) -> Void)?
```

**问题**：
- 闭包回调难以在 Swift 6 并发模型中安全地跨 actor 使用（需手动标注 `@Sendable`）
- 测试时需要手动设置回调并管理期望
- 无法使用 `async for ... in` 的结构化并发方式消费事件

**建议**：改用 `AsyncStream` 或 Combine `PassthroughSubject`：
```swift
let segmentSavedStream: AsyncStream<LoopSegment>
let playbackEndedStream: AsyncStream<ABFile?>
```

---

## 7. TODO 未完成项

### 🟡 PlayerManager.swift — 播放进度恢复

```swift
// PlayerManager.swift
// TODO: refactor it：always play from start and show a button to restore playing progress
```

当前行为：加载文件时是否从上次位置恢复不稳定。
**影响**：用户体验不一致，长音频重新从头播放需要手动跳转。

---

## 8. 测试覆盖缺口

| 业务逻辑 | 当前状态 | 风险 |
|----------|----------|------|
| A-B 循环边界条件（pointA == pointB，pointA > pointB） | ❌ 无测试 | 循环逻辑静默失效 |
| `handleLoopCheck` 精度（浮点比较） | ❌ 无测试 | 可能漏触发或过早触发 |
| SessionTracker 时间累积精度 | ❌ 无测试 | 统计数据偏差无从发现 |
| FolderImporter 文件配对（同名不同扩展名） | ❌ 无测试 | 字幕配对失败无感知 |
| SubtitleParser SRT/VTT 时间戳解析 | ❌ 无测试 | 异常格式导致字幕错位 |
| DeletionService 级联删除 + 磁盘清理 | ❌ 无测试 | 数据残留 |
| PlaybackQueue 随机模式空队列 | ❌ 无测试 | 直接对应上述 force unwrap 崩溃 |

**现有测试**（仅供参考）：

| 文件 | 覆盖内容 |
|------|----------|
| ABPlayerTests.swift | 重复模式索引环绕、文件名排序、选中状态同步 |
| TranscriptionTests.swift | 字幕编码/解码、转录状态机、设置管理 |
| SubtitleViewModelTests.swift | SubtitleViewModel 基础行为 |
| BusinessLogicTests.swift | 部分业务逻辑 |

---

## 9. 性能关注点

### 🟢 播放时间回调频率

`PlayerEngine` 使用 100ms 间隔的 `AVPlayer.addPeriodicTimeObserver`，每秒 10 次回调触发主线程更新。
**影响**：低功耗场景（笔记本电池）可能有轻微影响。
**建议**：非活跃窗口时降低至 500ms 间隔。

---

### 🟢 字幕富文本渲染

`AttributedStringCache` 的存在说明字幕渲染曾出现性能瓶颈（CPU 占用高）。当前已缓存，但缓存失效策略未见文档。
**建议**：确认缓存上限和 LRU/TTL 策略，避免长会话内存持续增长。

---

## 改进优先级建议

| 优先级 | 问题 | 原因 |
|--------|------|------|
| P0 | PlaybackQueue force unwrap（空队列崩溃） | 用户可轻易触发 |
| P0 | TranscriptionManager force unwrap | 常见操作路径 |
| P1 | DeletionService 磁盘/DB 不一致 | 数据安全 |
| P1 | SessionTracker 单步初始化 | 避免隐式无效状态 |
| P2 | try? 错误日志补全 | 可观测性 |
| P2 | AudioPlayerView 解耦 Model | 可测试性 |
| P3 | 回调改 AsyncStream | 并发安全 + 可测试性 |
| P3 | 补充缺失单元测试 | 防回归 |

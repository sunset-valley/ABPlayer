import AVFoundation
import Foundation

@MainActor
@Observable
public final class PlaybackQueue {
  struct Snapshot: Codable, Equatable {
    let fileIDs: [UUID]
    let currentFileID: UUID
    let sourceFolderID: UUID?
  }

  enum PlaybackDirection {
    case next
    case previous
  }
  
  enum LoopMode: String, CaseIterable {
    case none
    case repeatOne
    case repeatAll
    case shuffle
    case autoPlayNext
    
    var displayName: String {
      switch self {
        case .none: "Off"
        case .repeatOne: "Repeat One"
        case .repeatAll: "Repeat All"
        case .shuffle: "Shuffle"
        case .autoPlayNext: "Auto Play Next"
      }
    }
    
    var iconName: String {
      switch self {
        case .none: "repeat"
        case .repeatOne: "repeat.1"
        case .repeatAll: "repeat"
        case .shuffle: "shuffle"
        case .autoPlayNext: "arrow.forward.to.line"
      }
    }
  }
  
  var loopMode: LoopMode = .none
  private let snapshotStorageKey = UserDefaultsKey.playbackQueueSnapshot

  private var files: [ABFile] = []
  private(set) var sourceFolderID: UUID?
  private var currentFileID: UUID?

  var hasQueue: Bool {
    currentFile != nil
  }

  var currentFile: ABFile? {
    guard let currentFileID else { return nil }
    return files.first(where: { $0.id == currentFileID })
  }

  var queuedFiles: [ABFile] {
    files
  }
  
  init() {}

  func updateQueue(_ files: [ABFile]) {
    self.files = files

    if let currentFileID,
       !files.contains(where: { $0.id == currentFileID }) {
      self.currentFileID = nil
    }

    persistSnapshot()
  }

  func replaceQueue(
    files: [ABFile],
    currentFile: ABFile,
    sourceFolderID: UUID?
  ) {
    var orderedFiles = files
    if !orderedFiles.contains(where: { $0.id == currentFile.id }) {
      orderedFiles.append(currentFile)
    }

    self.files = orderedFiles
    self.currentFileID = currentFile.id
    self.sourceFolderID = sourceFolderID
    persistSnapshot()
  }

  func syncQueue(files: [ABFile], sourceFolderID: UUID?) {
    guard self.sourceFolderID == sourceFolderID else { return }

    self.files = files
    if let currentFileID,
       !files.contains(where: { $0.id == currentFileID }) {
      self.currentFileID = nil
    }

    persistSnapshot()
  }

  func clearQueue() {
    files = []
    currentFileID = nil
    sourceFolderID = nil
    clearPersistedSnapshot()
  }

  @discardableResult
  func removeFiles(withIDs ids: Set<UUID>) -> Bool {
    guard !ids.isEmpty else { return false }

    let originalCount = files.count
    files.removeAll { ids.contains($0.id) }

    if let currentFileID, ids.contains(currentFileID) {
      self.currentFileID = nil
    }

    if files.isEmpty {
      sourceFolderID = nil
    }

    let changed = files.count != originalCount
    if changed {
      persistSnapshot()
    }
    return changed
  }

  func setCurrentFile(_ file: ABFile?) {
    currentFileID = file?.id
    persistSnapshot()
  }

  func snapshot() -> Snapshot? {
    guard let currentFile = currentFile,
          !files.isEmpty else {
      return nil
    }

    return Snapshot(
      fileIDs: files.map(\.id),
      currentFileID: currentFile.id,
      sourceFolderID: sourceFolderID
    )
  }

  @discardableResult
  func restorePersistedSnapshot(
    fileResolver: ([UUID]) -> [UUID: ABFile]
  ) -> Bool {
    guard let data = UserDefaults.standard.data(forKey: snapshotStorageKey) else {
      clearQueueStateOnly()
      return false
    }

    let decoder = JSONDecoder()
    guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else {
      clearQueue()
      return false
    }

    let filesByID = fileResolver(snapshot.fileIDs)
    let resolvedFiles = snapshot.fileIDs.compactMap { filesByID[$0] }
    guard resolvedFiles.count == snapshot.fileIDs.count,
          resolvedFiles.contains(where: { $0.id == snapshot.currentFileID }) else {
      clearQueue()
      return false
    }

    files = resolvedFiles
    currentFileID = snapshot.currentFileID
    sourceFolderID = snapshot.sourceFolderID
    persistSnapshot()
    return true
  }

  func clearPersistedSnapshot() {
    UserDefaults.standard.removeObject(forKey: snapshotStorageKey)
  }
  
  /// Auto-play next file — respects loopMode (called when playback ends).
  @discardableResult
  func playNext() -> ABFile? {
    let nextFile = nextFile()
    if let nextFile {
      currentFileID = nextFile.id
      persistSnapshot()
    }
    return nextFile
  }

  /// Auto-play previous file — respects loopMode.
  @discardableResult
  func playPrev() -> ABFile? {
    let previousFile = previousFile()
    if let previousFile {
      currentFileID = previousFile.id
      persistSnapshot()
    }
    return previousFile
  }

  /// Manual navigate to next file — always works regardless of loopMode.
  @discardableResult
  func navigateNext() -> ABFile? {
    navigate(direction: .next)
  }

  /// Manual navigate to previous file — always works regardless of loopMode.
  @discardableResult
  func navigatePrev() -> ABFile? {
    navigate(direction: .previous)
  }
  
  private func nextFile() -> ABFile? {
    nextFile(direction: .next)
  }

  private func previousFile() -> ABFile? {
    nextFile(direction: .previous)
  }

  private func navigate(direction: PlaybackDirection) -> ABFile? {
    guard !files.isEmpty else { return nil }

    if loopMode == .shuffle {
      if files.count == 1 { return files.first }
      if let currentFileID {
        var randomFile: ABFile
        repeat {
          guard let random = files.randomElement() else { return nil }
          randomFile = random
        } while randomFile.id == currentFileID
        self.currentFileID = randomFile.id
        persistSnapshot()
        return randomFile
      }
      guard let file = files.randomElement() else { return nil }
      currentFileID = file.id
      persistSnapshot()
      return file
    }

    let index = currentIndex() ?? (direction == .next ? -1 : files.count)
    let nextIndex = direction == .next
      ? (index + 1) % files.count
      : (index - 1 + files.count) % files.count
    let file = files[nextIndex]
    currentFileID = file.id
    persistSnapshot()
    return file
  }
  
  private func nextFile(direction: PlaybackDirection) -> ABFile? {
    guard !files.isEmpty else { return nil }
    
    switch loopMode {
      case .none, .repeatOne:
        return nil
        
      case .repeatAll:
        if let index = currentIndex() {
          let nextIndex = direction == .next
          ? (index + 1) % files.count
          : (index - 1 + files.count) % files.count
          return files[nextIndex]
        }
        return files.first
        
      case .shuffle:
        if files.count == 1 {
          return files.first
        }

        if let currentFileID {
          var randomFile: ABFile
          repeat {
            guard let random = files.randomElement() else { return nil }
            randomFile = random
          } while randomFile.id == currentFileID
          return randomFile
        }

        return files.randomElement()
        
      case .autoPlayNext:
        guard let index = currentIndex() else { return nil }
        let nextIndex = direction == .next
        ? (index + 1) % files.count
        : (index - 1 + files.count) % files.count
        return files[nextIndex]
    }
  }
  
  private func currentIndex() -> Int? {
    guard let currentFileID else { return nil }
    return files.firstIndex(where: { $0.id == currentFileID })
  }

  private func persistSnapshot() {
    guard let snapshot = snapshot() else {
      clearPersistedSnapshot()
      return
    }

    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(snapshot) else { return }
    UserDefaults.standard.set(data, forKey: snapshotStorageKey)
  }

  private func clearQueueStateOnly() {
    files = []
    currentFileID = nil
    sourceFolderID = nil
  }
}

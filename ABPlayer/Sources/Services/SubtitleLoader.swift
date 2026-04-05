import Foundation
import Observation
import OSLog

/// Service for loading subtitles from files on-demand
@Observable
@MainActor
final class SubtitleLoader {
  enum LoadResult: Equatable {
    case loaded([SubtitleCue])
    case notFound
    case failed(String)
  }

  private static let maxCacheEntries = 8

  private var cachedSubtitlesByAudioFileID: [UUID: [SubtitleCue]] = [:]
  private var cacheAccessOrder: [UUID] = []
  private(set) var revisionMap: [UUID: Int] = [:]

  func cachedSubtitles(for audioFileID: UUID) -> [SubtitleCue] {
    cachedSubtitlesByAudioFileID[audioFileID] ?? []
  }

  /// Load subtitles from the SRT file associated with an audio file
  /// - Parameter audioFile: The audio file to load subtitles for
  /// - Returns: Array of subtitle cues, empty if no subtitles found
  func loadSubtitles(for audioFile: ABFile) async -> [SubtitleCue] {
    let result = await loadSubtitlesResult(for: audioFile)
    switch result {
    case let .loaded(cues):
      return cues
    case .notFound, .failed:
      return []
    }
  }

  func loadSubtitlesResult(for audioFile: ABFile) async -> LoadResult {
    guard let srtURL = audioFile.srtFileURL else {
      cacheSubtitles([], for: audioFile.id)
      return .notFound
    }

    guard let audioURL = try? resolveURL(from: audioFile.bookmarkData) else {
      return .failed("Failed to resolve audio file bookmark")
    }

    let gotAccess = audioURL.startAccessingSecurityScopedResource()
    defer {
      if gotAccess {
        audioURL.stopAccessingSecurityScopedResource()
      }
    }

    if !FileManager.default.fileExists(atPath: srtURL.path) {
      cacheSubtitles([], for: audioFile.id)
      return .notFound
    }

    return await loadSubtitlesResult(from: srtURL, audioFileID: audioFile.id)
  }

  /// Load subtitles from a specific URL
  /// - Parameters:
  ///   - url: The URL of the subtitle file
  /// - Returns: Array of subtitle cues, empty if loading fails
  func loadSubtitles(from url: URL, audioFileID: UUID) async -> [SubtitleCue] {
    let result = await loadSubtitlesResult(from: url, audioFileID: audioFileID)
    switch result {
    case let .loaded(cues):
      return cues
    case .notFound, .failed:
      return []
    }
  }

  func loadSubtitlesResult(from url: URL, audioFileID: UUID) async -> LoadResult {
    guard FileManager.default.fileExists(atPath: url.path) else {
      cacheSubtitles([], for: audioFileID)
      return .notFound
    }

    let result = await parseSubtitlesResult(at: url, audioFileID: audioFileID)
    switch result {
    case let .success(cues):
      cacheSubtitles(cues, for: audioFileID)
      return .loaded(cues)
    case let .failure(error):
      return .failed(error.localizedDescription)
    }
  }

  func updateSubtitle(for audioFile: ABFile, cueID: UUID, subtitle: String) async -> [SubtitleCue]? {
    var cues = cachedSubtitles(for: audioFile.id)
    if cues.isEmpty {
      cues = await loadSubtitles(for: audioFile)
    }

    guard let index = cues.firstIndex(where: { $0.id == cueID }) else {
      return nil
    }
    guard let srtURL = audioFile.srtFileURL else {
      return nil
    }

    let updatedCue = SubtitleCue(
      id: cues[index].id,
      startTime: cues[index].startTime,
      endTime: cues[index].endTime,
      text: subtitle
    )

    var updatedCues = cues
    updatedCues[index] = updatedCue

    do {
      try withSecurityScopedAccess(to: audioFile.bookmarkData) {
        try SubtitleParser.writeSRT(cues: updatedCues, to: srtURL)
      }
      cacheSubtitles(updatedCues, for: audioFile.id)
      return updatedCues
    } catch {
      Logger.data.error("⚠️ Failed to update subtitle at \(srtURL.path): \(error.localizedDescription)")
      return nil
    }
  }

  private func cacheSubtitles(_ cues: [SubtitleCue], for audioFileID: UUID) {
    if cachedSubtitlesByAudioFileID[audioFileID] == cues {
      touchAccessOrder(audioFileID)
      return
    }

    cachedSubtitlesByAudioFileID[audioFileID] = cues
    revisionMap[audioFileID, default: 0] += 1
    touchAccessOrder(audioFileID)
    evictIfNeeded()
  }

  private func touchAccessOrder(_ id: UUID) {
    cacheAccessOrder.removeAll { $0 == id }
    cacheAccessOrder.append(id)
  }

  private func evictIfNeeded() {
    while cacheAccessOrder.count > Self.maxCacheEntries {
      let evicted = cacheAccessOrder.removeFirst()
      cachedSubtitlesByAudioFileID.removeValue(forKey: evicted)
      revisionMap.removeValue(forKey: evicted)
    }
  }

  /// Parse subtitles from a file URL (runs on background thread)
  /// - Parameter url: The URL of the subtitle file
  /// - Returns: Array of subtitle cues
  private func parseSubtitlesResult(at url: URL, audioFileID: UUID) async -> Result<[SubtitleCue], Error> {
    await Task.detached {
      do {
        return .success(try SubtitleParser.parse(from: url, audioFileID: audioFileID))
      } catch {
        return .failure(error)
      }
    }.value
  }

  private func withSecurityScopedAccess<T>(to bookmarkData: Data, _ body: () throws -> T) throws -> T {
    let audioURL = try resolveURL(from: bookmarkData)
    let gotAccess = audioURL.startAccessingSecurityScopedResource()
    defer {
      if gotAccess {
        audioURL.stopAccessingSecurityScopedResource()
      }
    }

    return try body()
  }

  /// Resolve URL from bookmark data
  private func resolveURL(from bookmarkData: Data) throws -> URL {
    var isStale = false
    return try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
  }
}

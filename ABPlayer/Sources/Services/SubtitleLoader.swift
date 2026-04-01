import Foundation
import Observation
import OSLog

/// Service for loading subtitles from files on-demand
@Observable
@MainActor
final class SubtitleLoader {
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
    guard let srtURL = audioFile.srtFileURL else {
      cacheSubtitles([], for: audioFile.id)
      return []
    }

    guard let audioURL = try? resolveURL(from: audioFile.bookmarkData) else {
      cacheSubtitles([], for: audioFile.id)
      return []
    }

    let gotAccess = audioURL.startAccessingSecurityScopedResource()
    defer {
      if gotAccess {
        audioURL.stopAccessingSecurityScopedResource()
      }
    }

    return await loadSubtitles(from: srtURL, audioFileID: audioFile.id)
  }

  /// Load subtitles from a specific URL
  /// - Parameters:
  ///   - url: The URL of the subtitle file
  /// - Returns: Array of subtitle cues, empty if loading fails
  func loadSubtitles(from url: URL, audioFileID: UUID) async -> [SubtitleCue] {
    let cues = await parseSubtitles(at: url, audioFileID: audioFileID)
    cacheSubtitles(cues, for: audioFileID)
    return cues
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
  private func parseSubtitles(at url: URL, audioFileID: UUID) async -> [SubtitleCue] {
    await Task.detached {
      do {
        return try SubtitleParser.parse(from: url, audioFileID: audioFileID)
      } catch {
        return []
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

import Foundation
import Observation

/// Service for loading subtitles from files on-demand
@Observable
@MainActor
final class SubtitleLoader {
    
    /// Load subtitles from the SRT file associated with an audio file
    /// - Parameter audioFile: The audio file to load subtitles for
    /// - Returns: Array of subtitle cues, empty if no subtitles found
    func loadSubtitles(for audioFile: ABFile) async -> [SubtitleCue] {
        guard let srtURL = audioFile.srtFileURL else { return [] }
        
        // Security-scoped access via audio file bookmark
        guard let audioURL = try? resolveURL(from: audioFile.bookmarkData) else { return [] }
        
        let gotAccess = audioURL.startAccessingSecurityScopedResource()
        defer { if gotAccess { audioURL.stopAccessingSecurityScopedResource() } }
        
        return await loadSubtitles(from: srtURL, audioFileID: audioFile.id)
    }
    
    /// Load subtitles from a specific URL
    /// - Parameters:
    ///   - url: The URL of the subtitle file
    /// - Returns: Array of subtitle cues, empty if loading fails
    func loadSubtitles(from url: URL, audioFileID: UUID) async -> [SubtitleCue] {
        return await parseSubtitles(at: url, audioFileID: audioFileID)
    }
    
    /// Parse subtitles from a file URL (runs on background thread)
    /// - Parameter url: The URL of the subtitle file
    /// - Returns: Array of subtitle cues
    private func parseSubtitles(at url: URL, audioFileID: UUID) async -> [SubtitleCue] {
        return await Task.detached {
            do {
                return try SubtitleParser.parse(from: url, audioFileID: audioFileID)
            } catch {
                return []
            }
        }.value
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

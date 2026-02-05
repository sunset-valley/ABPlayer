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
        
        return await loadSubtitles(from: srtURL)
    }
    
    /// Load subtitles from a SubtitleFile entity using its bookmark
    /// - Parameter subtitleFile: The subtitle file entity
    /// - Returns: Array of subtitle cues, empty if loading fails
    func loadSubtitles(from subtitleFile: SubtitleFile) async -> [SubtitleCue] {
        return await loadSubtitles(from: subtitleFile.bookmarkData)
    }
    
    /// Load subtitles from bookmark data
    /// - Parameter bookmarkData: The security-scoped bookmark data
    /// - Returns: Array of subtitle cues, empty if loading fails
    func loadSubtitles(from bookmarkData: Data) async -> [SubtitleCue] {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return [] }
        
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
        
        return await loadSubtitles(from: url)
    }
    
    /// Load subtitles from a specific URL
    /// - Parameters:
    ///   - url: The URL of the subtitle file
    ///   - bookmarkData: Optional bookmark data for security-scoped access
    /// - Returns: Array of subtitle cues, empty if loading fails
    func loadSubtitles(from url: URL, withSecurityScope bookmarkData: Data? = nil) async -> [SubtitleCue] {
        // If bookmark data is provided, use it for security scope
        if let bookmarkData = bookmarkData {
            var isStale = false
            guard let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return [] }
            
            let gotAccess = resolvedURL.startAccessingSecurityScopedResource()
            defer { if gotAccess { resolvedURL.stopAccessingSecurityScopedResource() } }
            
            return await parseSubtitles(at: url)
        }
        
        // Otherwise, try to load directly
        return await parseSubtitles(at: url)
    }
    
    /// Parse subtitles from a file URL (runs on background thread)
    /// - Parameter url: The URL of the subtitle file
    /// - Returns: Array of subtitle cues
    private func parseSubtitles(at url: URL) async -> [SubtitleCue] {
        return await Task.detached {
            do {
                return try SubtitleParser.parse(from: url)
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

import Foundation
import OSLog
import SwiftData

@MainActor
final class DeletionService {
  private let modelContext: ModelContext
  private let playerManager: PlayerManager
  private let librarySettings: LibrarySettings
  
  init(
    modelContext: ModelContext,
    playerManager: PlayerManager,
    librarySettings: LibrarySettings
  ) {
    self.modelContext = modelContext
    self.playerManager = playerManager
    self.librarySettings = librarySettings
  }
  
  func deleteFolder(
    _ folder: Folder,
    deleteFromDisk: Bool = true,
    selectedFile: inout ABFile?
  ) {
    let affectedFileIDs = collectFileIDs(in: folder)
    preparePlaybackStateForDeletedFiles(affectedFileIDs)

    deleteFolderContents(
      folder,
      deleteFromDisk: deleteFromDisk,
      selectedFile: &selectedFile
    )
    
    do {
      try modelContext.save()
    } catch {
      Logger.data.error(
        "⚠️ Failed to save context before folder deletion: \(error.localizedDescription)")
    }
    
    if deleteFromDisk {
      let url = folderLibraryURL(for: folder)
      if let url {
        do {
          try FileManager.default.removeItem(at: url)
        } catch {
          Logger.data.error("⚠️ Failed to delete folder \(folder.name) from disk: \(error.localizedDescription)")
        }
      }
    }
    
    modelContext.delete(folder)
  }
  
  func deleteAudioFile(
    _ file: ABFile,
    deleteFromDisk: Bool = true,
    updateSelection: Bool = true,
    checkPlayback: Bool = true,
    selectedFile: inout ABFile?
  ) {
    if deleteFromDisk {
      let url = librarySettings.mediaFileURL(for: file)
      if FileManager.default.fileExists(atPath: url.path) {
        do {
          try FileManager.default.removeItem(at: url)
        } catch {
          Logger.data.error("⚠️ Failed to delete audio file \(file.displayName) from disk: \(error.localizedDescription)")
        }
      }

      let pdfURL = librarySettings.pdfFileURL(for: file)
      if FileManager.default.fileExists(atPath: pdfURL.path) {
        do {
          try FileManager.default.removeItem(at: pdfURL)
        } catch {
          Logger.data.error("⚠️ Failed to delete PDF for \(file.displayName) from disk: \(error.localizedDescription)")
        }
      }
    }
    
    if checkPlayback {
      preparePlaybackStateForDeletedFiles([file.id])

      do {
        try modelContext.save()
      } catch {
        Logger.data.error(
          "⚠️ Failed to save context before file deletion: \(error.localizedDescription)")
      }
    }

    if updateSelection && selectedFile?.id == file.id {
      selectedFile = nil
    }
    
    if deleteFromDisk, let subtitleFile = file.subtitleFile {
      let subtitleURL = librarySettings.subtitleFileURL(for: file)
      if FileManager.default.fileExists(atPath: subtitleURL.path) {
        do {
          try FileManager.default.removeItem(at: subtitleURL)
        } catch {
          Logger.data.error("⚠️ Failed to delete subtitle \(subtitleFile.displayName) from disk: \(error.localizedDescription)")
        }
      }
    }
    
    for segment in file.segments {
      modelContext.delete(segment)
    }
    
    if let subtitleFile = file.subtitleFile {
      modelContext.delete(subtitleFile)
    }
    
    let fileIdString = file.id.uuidString
    let descriptor = FetchDescriptor<Transcription>(
      predicate: #Predicate<Transcription> { $0.audioFileId == fileIdString }
    )
    if let transcriptions = try? modelContext.fetch(descriptor) {
      for transcription in transcriptions {
        modelContext.delete(transcription)
      }
    }
    
    modelContext.delete(file)
  }
  
  private func collectFileIDs(in folder: Folder) -> Set<UUID> {
    var ids = Set(folder.audioFiles.map(\.id))
    for subfolder in folder.subfolders {
      ids.formUnion(collectFileIDs(in: subfolder))
    }
    return ids
  }

  private func preparePlaybackStateForDeletedFiles(_ fileIDs: Set<UUID>) {
    guard !fileIDs.isEmpty else { return }

    if let currentFileID = playerManager.currentFile?.id, fileIDs.contains(currentFileID) {
      if playerManager.isPlaying {
        Task {
          await playerManager.togglePlayPause()
        }
      }
      playerManager.currentFile = nil
    }

    _ = playerManager.playbackQueue.removeFiles(withIDs: fileIDs)
  }
  
  private func deleteFolderContents(
    _ folder: Folder,
    deleteFromDisk: Bool,
    selectedFile: inout ABFile?
  ) {
    for audioFile in folder.audioFiles {
      deleteAudioFile(
        audioFile,
        deleteFromDisk: deleteFromDisk,
        updateSelection: false,
        checkPlayback: false,
        selectedFile: &selectedFile
      )
    }
    
    for subfolder in folder.subfolders {
      deleteFolderContents(
        subfolder,
        deleteFromDisk: deleteFromDisk,
        selectedFile: &selectedFile
      )
      modelContext.delete(subfolder)
    }
  }
  
  private func folderLibraryURL(for folder: Folder) -> URL? {
    let relativePath = folder.relativePath
    guard !relativePath.isEmpty else { return nil }
    return librarySettings.libraryDirectoryURL.appendingPathComponent(relativePath)
  }
}

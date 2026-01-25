import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ImportService {
  private let modelContext: ModelContext
  private let librarySettings: LibrarySettings
  
  var importErrorMessage: String?
  
  init(
    modelContext: ModelContext,
    librarySettings: LibrarySettings
  ) {
    self.modelContext = modelContext
    self.librarySettings = librarySettings
  }
  
  func handleImportResult(
    _ result: Result<[URL], Error>,
    importType: MainSplitView.ImportType?,
    currentFolder: Folder?
  ) {
    switch importType {
    case .file:
      handleFileImportResult(result, currentFolder: currentFolder)
    case .folder:
      handleFolderImportResult(result, currentFolder: currentFolder)
    case .none:
      break
    }
  }
  
  func addAudioFile(from url: URL, currentFolder: Folder?) {
    do {
      try librarySettings.ensureLibraryDirectoryExists()
      
      let fileURL: URL
      let targetFolder: Folder?
      if isInLibrary(url) {
        fileURL = url
        let folderRelativePath = folderRelativePath(for: fileURL)
        targetFolder = findOrCreateFolder(relativePath: folderRelativePath)
      } else {
        let destinationDirectory = currentFolderLibraryURL(currentFolder) ?? librarySettings.libraryDirectoryURL
        fileURL = try copyItemToLibrary(from: url, destinationDirectory: destinationDirectory)
        targetFolder = currentFolder
      }
      
      let relativePath = calculateRelativePath(for: fileURL)
      let bookmarkData = try fileURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      
      let deterministicID = ABFile.generateDeterministicID(from: relativePath)
      let audioFile = ABFile(
        id: deterministicID,
        displayName: fileURL.lastPathComponent,
        bookmarkData: bookmarkData,
        folder: targetFolder,
        relativePath: relativePath
      )
      
      modelContext.insert(audioFile)
      targetFolder?.audioFiles.append(audioFile)
    } catch {
      importErrorMessage = "Failed to import file: \(error.localizedDescription)"
    }
  }
  
  func importFolder(from url: URL, currentFolder: Folder?) {
    Task { @MainActor in
      let importer = FolderImporter(modelContext: modelContext, librarySettings: librarySettings)
      
      do {
        let targetParent: Folder?
        if isInLibrary(url) {
          let folderRelativePath = calculateRelativePath(for: url)
          let parentRelativePath = parentRelativePath(for: folderRelativePath)
          targetParent = findOrCreateFolder(relativePath: parentRelativePath)
        } else {
          targetParent = currentFolder
        }
        _ = try await importer.syncFolder(at: url, parentFolder: targetParent)
      } catch {
        await MainActor.run {
          importErrorMessage = "Failed to import folder: \(error.localizedDescription)"
        }
      }
    }
  }
  
  private func handleFileImportResult(_ result: Result<[URL], Error>, currentFolder: Folder?) {
    switch result {
    case .failure(let error):
      importErrorMessage = error.localizedDescription
    case .success(let urls):
      guard let url = urls.first else { return }
      addAudioFile(from: url, currentFolder: currentFolder)
    }
  }
  
  private func handleFolderImportResult(_ result: Result<[URL], Error>, currentFolder: Folder?) {
    switch result {
    case .failure(let error):
      importErrorMessage = error.localizedDescription
    case .success(let urls):
      guard let url = urls.first else { return }
      importFolder(from: url, currentFolder: currentFolder)
    }
  }
  
  private func copyItemToLibrary(from url: URL, destinationDirectory: URL) throws -> URL {
    let fileManager = FileManager.default
    
    var destinationURL = destinationDirectory.appendingPathComponent(url.lastPathComponent)
    if fileManager.fileExists(atPath: destinationURL.path) {
      destinationURL = uniqueURL(for: destinationURL)
    }
    
    try fileManager.copyItem(at: url, to: destinationURL)
    return destinationURL
  }
  
  private func isInLibrary(_ url: URL) -> Bool {
    let libraryURL = librarySettings.libraryDirectoryURL.standardizedFileURL
    let candidateURL = url.standardizedFileURL
    return candidateURL.path.hasPrefix(libraryURL.path)
  }
  
  private func currentFolderLibraryURL(_ currentFolder: Folder?) -> URL? {
    guard let currentFolder else { return nil }
    let relativePath = currentFolder.relativePath
    guard !relativePath.isEmpty else { return nil }
    return librarySettings.libraryDirectoryURL.appendingPathComponent(relativePath)
  }
  
  private func calculateRelativePath(for fileURL: URL) -> String {
    let libraryURL = librarySettings.libraryDirectoryURL.standardizedFileURL
    let standardizedFileURL = fileURL.standardizedFileURL
    return String(
      standardizedFileURL.path
        .dropFirst(libraryURL.path.count)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    )
  }
  
  private func folderRelativePath(for fileURL: URL) -> String {
    let relativePath = calculateRelativePath(for: fileURL)
    return parentRelativePath(for: relativePath)
  }
  
  private func parentRelativePath(for relativePath: String) -> String {
    let parentPath = (relativePath as NSString).deletingLastPathComponent
    return parentPath == "." ? "" : parentPath
  }
  
  private func findOrCreateFolder(relativePath: String) -> Folder? {
    guard !relativePath.isEmpty else { return nil }
    let components = relativePath.split(separator: "/").map(String.init)
    var parent: Folder?
    var currentPath = ""
    
    for component in components {
      currentPath = currentPath.isEmpty ? component : "\(currentPath)/\(component)"
      let folderId = Folder.generateDeterministicID(from: currentPath)
      let descriptor = FetchDescriptor<Folder>(
        predicate: #Predicate<Folder> { $0.id == folderId }
      )
      
      if let existing = try? modelContext.fetch(descriptor).first {
        if let parent, existing.parent?.id != parent.id {
          existing.parent = parent
          if !parent.subfolders.contains(where: { $0.id == existing.id }) {
            parent.subfolders.append(existing)
          }
        }
        parent = existing
      } else {
        let folder = Folder(
          id: folderId,
          name: component,
          relativePath: currentPath,
          createdAt: Date(),
          parent: parent
        )
        modelContext.insert(folder)
        parent?.subfolders.append(folder)
        parent = folder
      }
    }
    
    return parent
  }
  
  private func uniqueURL(for url: URL) -> URL {
    let fileManager = FileManager.default
    let directory = url.deletingLastPathComponent()
    let baseName = url.deletingPathExtension().lastPathComponent
    let fileExtension = url.pathExtension
    
    var counter = 1
    var candidate = url
    
    while fileManager.fileExists(atPath: candidate.path) {
      let newName = "\(baseName) \(counter)"
      if fileExtension.isEmpty {
        candidate = directory.appendingPathComponent(newName)
      } else {
        candidate = directory.appendingPathComponent(newName).appendingPathExtension(fileExtension)
      }
      counter += 1
    }
    
    return candidate
  }
}

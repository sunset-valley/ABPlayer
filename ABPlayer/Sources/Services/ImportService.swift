import Foundation
import OSLog
import SwiftData
import SwiftUI

@MainActor
final class ImportService {
  private let modelContext: ModelContext
  private let librarySettings: LibrarySettings
  
  var importErrorMessage: String?
  var onImportStarted: (@MainActor () -> Void)?
  var onImportCompleted: (@MainActor () -> Void)?
  var onSyncStateChanged: (@MainActor (_ isRunning: Bool, _ message: String?) -> Void)?
  
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
      if librarySettings.isInLibrary(url) {
        fileURL = url
        let folderRelativePath = folderRelativePath(for: fileURL)
        targetFolder = findOrCreateFolder(relativePath: folderRelativePath)
      } else if currentFolder == nil {
        // Auto-wrap: copy into a new subfolder named after the file
        let folderName = url.deletingPathExtension().lastPathComponent
        let wrapperDirectory = librarySettings.libraryDirectoryURL.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: wrapperDirectory, withIntermediateDirectories: true)
        fileURL = try copyItemToLibrary(from: url, destinationDirectory: wrapperDirectory)
        targetFolder = findOrCreateFolder(relativePath: folderName)
      } else {
        let destinationDirectory = currentFolderLibraryURL(currentFolder) ?? librarySettings.libraryDirectoryURL
        fileURL = try copyItemToLibrary(from: url, destinationDirectory: destinationDirectory)
        targetFolder = currentFolder
      }
      
      let relativePath = calculateRelativePath(for: fileURL)

      let deterministicID = ABFile.generateDeterministicID(from: relativePath)
      let audioFile = ABFile(
        id: deterministicID,
        displayName: fileURL.lastPathComponent,
        fileType: ABFile.inferFileType(from: fileURL),
        bookmarkData: Data(),
        folder: targetFolder,
        relativePath: relativePath
      )
      
      modelContext.insert(audioFile)
      targetFolder?.audioFiles.append(audioFile)
      finishSync()
    } catch {
      importErrorMessage = "Failed to import file: \(error.localizedDescription)"
      finishSync()
    }
  }
  
  func importFolder(from url: URL, currentFolder: Folder?) {
    beginSync(message: "Importing folder...")
    Task { @MainActor in
      do {
        try await librarySettings.withLibraryAccess {
          let importer = FolderImporter(modelContext: self.modelContext, librarySettings: self.librarySettings)
          let targetParent: Folder?
          if self.librarySettings.isInLibrary(url) {
            let folderRelativePath = self.calculateRelativePath(for: url)
            let parentRelativePath = self.parentRelativePath(for: folderRelativePath)
            targetParent = self.findOrCreateFolder(relativePath: parentRelativePath)
          } else {
            targetParent = currentFolder
          }
          _ = try await importer.syncFolder(
            at: url,
            parentFolder: targetParent,
            onProgressMessage: { [weak self] message in
              self?.updateSyncMessage(message)
            }
          )
        }
        finishSync()
      } catch {
        importErrorMessage = "Failed to import folder: \(error.localizedDescription)"
        finishSync()
      }
    }
  }
  
  func refreshFolder(_ folder: Folder) async {
    beginSync(message: "Refreshing \(folder.name)...")
    defer { finishSync() }

    do {
      try await librarySettings.withLibraryAccess {
        let folderURL = self.librarySettings.libraryDirectoryURL.appendingPathComponent(folder.relativePath)
        let importer = FolderImporter(modelContext: self.modelContext, librarySettings: self.librarySettings)

        _ = try await importer.syncFolder(
          at: folderURL,
          parentFolder: folder.parent,
          onProgressMessage: { [weak self] message in
            self?.updateSyncMessage(message)
          }
        )
      }
    } catch {
      Logger.data.error("[ImportService] refreshFolder failed for \(folder.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
      importErrorMessage = "Failed to refresh folder: \(error.localizedDescription)"
    }
  }

  func refreshLibraryRoot() async {
    beginSync(message: "Refreshing library...")
    defer { finishSync() }

    do {
      try await librarySettings.withLibraryAccess {
        try self.librarySettings.ensureLibraryDirectoryExists()

        let fileManager = FileManager.default
        let rootURL = self.librarySettings.libraryDirectoryURL
        let importer = FolderImporter(modelContext: self.modelContext, librarySettings: self.librarySettings)

        let contents = try fileManager.contentsOfDirectory(
          at: rootURL,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        )

        let directories = contents.filter {
          (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        for directoryURL in directories {
          _ = try await importer.syncFolder(
            at: directoryURL,
            parentFolder: nil,
            copyExternalIntoLibrary: false,
            onProgressMessage: { [weak self] message in
              self?.updateSyncMessage(message)
            }
          )
        }
      }
    } catch {
      Logger.data.error("[ImportService] refreshLibraryRoot failed: \(error.localizedDescription, privacy: .public)")
      importErrorMessage = "Failed to refresh library: \(error.localizedDescription)"
    }
  }
  
  private func handleFileImportResult(_ result: Result<[URL], Error>, currentFolder: Folder?) {
    switch result {
    case .failure(let error):
      importErrorMessage = error.localizedDescription
    case .success(let urls):
      guard let url = urls.first else { return }
      beginSync(message: "Importing media...")
      Task { @MainActor in
        self.addAudioFile(from: url, currentFolder: currentFolder)
      }
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
      destinationURL = .uniqueURL(for: destinationURL)
    }
    
    try fileManager.copyItem(at: url, to: destinationURL)
    return destinationURL
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

  private func beginSync(message: String) {
    onImportStarted?()
    onSyncStateChanged?(true, message)
  }

  private func finishSync() {
    onSyncStateChanged?(false, nil)
    onImportCompleted?()
  }

  private func updateSyncMessage(_ message: String) {
    onSyncStateChanged?(true, message)
  }

}

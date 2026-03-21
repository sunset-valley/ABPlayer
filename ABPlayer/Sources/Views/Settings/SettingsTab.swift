import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
  case media = "Media"
  case network = "Network"
  case update = "Update"
  case shortcuts = "Shortcuts"
  case transcription = "Transcription"
  case plugins = "Plugins"

  var id: Self { self }

  var icon: String {
    switch self {
    case .media: return "books.vertical"
    case .network: return "network"
    case .update: return "arrow.triangle.2.circlepath"
    case .shortcuts: return "keyboard"
    case .transcription: return "text.bubble"
    case .plugins: return "puzzlepiece.extension"
    }
  }
}

enum FFmpegStatus {
  case unchecked
  case valid
  case invalid
  case notFound
}

enum FileImportType {
  case ffmpegPath
  case modelDirectory
  case libraryDirectory
}

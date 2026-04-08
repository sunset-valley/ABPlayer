import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
  case media = "Media"
  case network = "Network"
  #if !APPSTORE
    case update = "Update"
  #endif
  case shortcuts = "Shortcuts"
  case transcription = "Transcription"

  var id: Self { self }

  var icon: String {
    switch self {
    case .media: return "books.vertical"
    case .network: return "network"
    #if !APPSTORE
      case .update: return "arrow.triangle.2.circlepath"
    #endif
    case .shortcuts: return "keyboard"
    case .transcription: return "text.bubble"
    }
  }
}

enum FileImportType {
  case modelDirectory
}

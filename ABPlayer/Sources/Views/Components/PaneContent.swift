import SwiftUI

enum PaneContent: String, CaseIterable, Identifiable {
  case none
  case transcription
  case pdf
  case segments

  var id: String { rawValue }

  var title: String {
    switch self {
    case .none: return "None"
    case .transcription: return "Transcription"
    case .pdf: return "PDF"
    case .segments: return "Segments"
    }
  }

  var systemImage: String {
    switch self {
    case .none: return "square.dashed"
    case .transcription: return "text.bubble"
    case .pdf: return "doc.text"
    case .segments: return "lines.measurement.horizontal"
    }
  }
}

extension PaneContent {
  static var allocatableCases: [PaneContent] { [.transcription, .pdf, .segments] }
  var isAllocatable: Bool { self != .none }
}

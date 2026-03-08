import Foundation

enum MenuItem: String, CaseIterable, Identifiable {
  case todaysPicks = "Today's Picks"
  case podcast = "Podcast"
  case continueListening = "Continue Listening"
  case downloads = "Downloads"
  case flashCard = "Flash Card"
  case notes = "Notes"
  case markedClips = "Marked Clips"
  case myUploads = "My Uploads"
  case myResources = "My Resources"
  case history = "History"
  case stats = "Stats"
  case streak = "Streak"
  case favorites = "Favorites"

  var id: String {
    rawValue
  }

  var icon: String {
    switch self {
    case .todaysPicks: return "sparkles"
    case .podcast: return "mic"
    case .continueListening: return "play.circle"
    case .downloads: return "arrow.down.circle"
    case .flashCard: return "lanyardcard"
    case .notes: return "note.text"
    case .markedClips: return "bookmark"
    case .myUploads: return "square.and.arrow.up"
    case .myResources: return "folder"
    case .history: return "clock.arrow.circlepath"
    case .stats: return "chart.bar"
    case .streak: return "flame"
    case .favorites: return "star"
    }
  }
}

struct MenuSection: Identifiable {
  let title: String
  let items: [MenuItem]

  var id: String {
    title
  }
}

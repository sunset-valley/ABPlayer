import Foundation

enum MenuItem: String, CaseIterable, Identifiable {
    case todaysPicks = "Today's Picks"
    case podcast = "Podcast"
    case downloads = "Downloads"
    case history = "History"
    case myUploads = "My Uploads"
    case myResources = "My Resources"
    case vocabulary = "Vocabulary"
    case favorites = "Favorites"
    case liked = "Liked"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .todaysPicks: return "sparkles"
        case .podcast: return "mic"
        case .downloads: return "arrow.down.circle"
        case .history: return "clock.arrow.circlepath"
        case .myUploads: return "square.and.arrow.up"
        case .myResources: return "folder"
        case .vocabulary: return "character.book.closed"
        case .favorites: return "star"
        case .liked: return "heart"
        }
    }
}

struct MenuSection: Identifiable {
    let title: String?
    let items: [MenuItem]

    var id: String {
        if let title {
            return title
        }

        return items.map(\.id).joined(separator: "-")
    }
}

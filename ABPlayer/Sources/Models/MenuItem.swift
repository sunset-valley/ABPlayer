import Foundation

enum MenuItem: String, CaseIterable, Identifiable {
    case library = "Library"
    case audio = "Audio"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .library: return "folder"
        case .audio: return "waveform"
        case .settings: return "gearshape"
        }
    }
}

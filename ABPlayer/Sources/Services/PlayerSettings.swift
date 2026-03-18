import Foundation
import SwiftUI

/// User configurable player settings
@MainActor
@Observable
final class PlayerSettings {
  /// Whether to prevent system sleep during playback
  var preventSleep: Bool = UserDefaults.standard.object(forKey: "player_prevent_sleep") as? Bool ?? true {
    didSet { UserDefaults.standard.set(preventSleep, forKey: "player_prevent_sleep") }
  }
}

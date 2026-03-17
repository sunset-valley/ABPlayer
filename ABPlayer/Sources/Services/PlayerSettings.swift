import Foundation
import SwiftUI

/// User configurable player settings
@MainActor
@Observable
final class PlayerSettings {
  /// Whether to prevent system sleep during playback
  @ObservationIgnored
  @AppStorage("player_prevent_sleep") var preventSleep: Bool = true
}

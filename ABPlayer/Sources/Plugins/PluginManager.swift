import SwiftUI
import Observation

@MainActor
@Observable
final class PluginManager {
  static let shared = PluginManager()
  
  private(set) var plugins: [any Plugin] = []
  
  private init() {
    plugins = [
      CounterPlugin.shared
    ]
  }
  
}

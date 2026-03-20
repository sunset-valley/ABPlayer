import SwiftUI

@MainActor
/// Internal-only plugin API for first-party extensions bundled with ABPlayer.
/// Not intended as a third-party extension surface.
protocol Plugin: Identifiable {
  var id: String { get }
  var name: String { get }
  var icon: String { get }
  
  func open()
}

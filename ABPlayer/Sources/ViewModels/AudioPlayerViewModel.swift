import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AudioPlayerViewModel: BasePlayerViewModel {
  var showVolumePopover: Bool = false
}

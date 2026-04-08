#if !APPSTORE
  import Sparkle
  import SwiftUI

  enum UpdateFeedSource: String, CaseIterable, Identifiable {
    case kcoding

    var id: Self { self }

    var appcastURL: String {
      switch self {
      case .kcoding:
        return "https://s3.kcoding.cn/d/ABPlayerRelease/appcast.xml"
      }
    }
  }

  @MainActor
  @Observable
  final class SparkleUpdater {
    @ObservationIgnored
    private let controller: SPUStandardUpdaterController

    @ObservationIgnored
    @AppStorage(UserDefaultsKey.updateFeedSource) private var _selectedFeedSourceRawValue: String =
      UpdateFeedSource.kcoding.rawValue

    var selectedFeedSource: UpdateFeedSource {
      get {
        access(keyPath: \.selectedFeedSource)
        return UpdateFeedSource(rawValue: _selectedFeedSourceRawValue) ?? .kcoding
      }
      set {
        withMutation(keyPath: \.selectedFeedSource) {
          _selectedFeedSourceRawValue = newValue.rawValue
          applyFeedURLOverride(for: newValue)
        }
      }
    }

    init() {
      controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
      )
      applyFeedURLOverride(for: selectedFeedSource)
    }

    func checkForUpdates() {
      applyFeedURLOverride(for: selectedFeedSource)
      controller.checkForUpdates(nil)
    }

    private func applyFeedURLOverride(for source: UpdateFeedSource) {
      UserDefaults.standard.set(source.appcastURL, forKey: UserDefaultsKey.sparkleFeedURL)
    }
  }
#endif

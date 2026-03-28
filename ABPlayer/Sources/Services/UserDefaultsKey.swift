import Foundation

enum UserDefaultsKey {
  static let subtitleFontSize = "subtitleFontSize"
  static let folderNavigationSortOrder = "folderNavigationSortOrder"
  static let playerPreventSleep = "player_prevent_sleep"

  static let proxyEnabled = "proxy_enabled"
  static let proxyHost = "proxy_host"
  static let proxyPort = "proxy_port"
  static let proxyType = "proxy_type"
  static let updateFeedSource = "update_feed_source"
  static let sparkleFeedURL = "SUFeedURL"
  static let legacyPersistentStoreResetCompleted = "legacy_persistent_store_reset_completed"

  enum MainSplitSuffix: String {
    case showContentPanel = "ShowContentPanel"
    case showBottomPanel = "ShowBottomPanel"
    case playerSectionWidth = "PlayerSectionWidth"
    case topPanelHeight = "TopPanelHeight"
    case leftTabs = "LeftTabs"
    case rightTabs = "RightTabs"
    case leftSelection = "LeftSelection"
    case rightSelection = "RightSelection"
  }

  static func mainSplit(mediaTypeRawValue: String, suffix: MainSplitSuffix) -> String {
    "mainSplit\(mediaTypeRawValue.capitalized)\(suffix.rawValue)"
  }
}

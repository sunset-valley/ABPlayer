import Foundation
import SwiftUI

/// User configurable proxy settings for network requests
@MainActor
@Observable
final class ProxySettings {
  @ObservationIgnored
  @AppStorage(UserDefaultsKey.proxyEnabled) private var _isEnabled: Bool = false
  var isEnabled: Bool {
    get { access(keyPath: \.isEnabled); return _isEnabled }
    set { withMutation(keyPath: \.isEnabled) { _isEnabled = newValue } }
  }

  @ObservationIgnored
  @AppStorage(UserDefaultsKey.proxyHost) private var _host: String = ""
  var host: String {
    get { access(keyPath: \.host); return _host }
    set { withMutation(keyPath: \.host) { _host = newValue } }
  }

  @ObservationIgnored
  @AppStorage(UserDefaultsKey.proxyPort) private var _port: Int = 8080
  var port: Int {
    get { access(keyPath: \.port); return _port }
    set { withMutation(keyPath: \.port) { _port = newValue } }
  }

  @ObservationIgnored
  @AppStorage(UserDefaultsKey.proxyType) private var _type: String = "http"
  var type: String {
    get { access(keyPath: \.type); return _type }
    set { withMutation(keyPath: \.type) { _type = newValue } }
  }

  // MARK: - Thread-Safe Access

  /// Build the connectionProxyDictionary for URLSessionConfiguration.
  /// Reads directly from UserDefaults so it can be called from any thread.
  nonisolated func currentProxyDictionary() -> [AnyHashable: Any]? {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: UserDefaultsKey.proxyEnabled) else { return nil }

    let host = (defaults.string(forKey: UserDefaultsKey.proxyHost) ?? "").trimmingCharacters(in: .whitespaces)
    let port = defaults.integer(forKey: UserDefaultsKey.proxyPort)
    let type = defaults.string(forKey: UserDefaultsKey.proxyType) ?? "http"

    guard !host.isEmpty, port > 0 else { return nil }

    if type == "socks5" {
      return [
        kCFStreamPropertySOCKSProxyHost as AnyHashable: host,
        kCFStreamPropertySOCKSProxyPort as AnyHashable: port,
      ]
    } else {
      // HTTP proxy — covers both HTTP and HTTPS traffic.
      // HTTP keys use public CFNetwork constants; HTTPS keys use the raw strings
      // from CFNetworkCopySystemProxySettings() since no public constants exist.
      return [
        kCFNetworkProxiesHTTPEnable as AnyHashable: true,
        kCFNetworkProxiesHTTPProxy as AnyHashable: host,
        kCFNetworkProxiesHTTPPort as AnyHashable: port,
        "HTTPSEnable" as AnyHashable: true,
        "HTTPSProxy" as AnyHashable: host,
        "HTTPSPort" as AnyHashable: port,
      ]
    }
  }

  /// Whether the proxy is enabled and has a valid host/port configured
  var isConfigured: Bool {
    isEnabled && !host.trimmingCharacters(in: .whitespaces).isEmpty && port > 0
  }
}

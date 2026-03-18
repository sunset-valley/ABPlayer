import Foundation
import SwiftUI

/// User configurable proxy settings for network requests
@MainActor
@Observable
final class ProxySettings {
  /// Whether to route requests through the proxy
  @ObservationIgnored
  @AppStorage("proxy_enabled") var isEnabled: Bool = false

  /// Proxy server hostname or IP address
  @ObservationIgnored
  @AppStorage("proxy_host") var host: String = ""

  /// Proxy server port
  @ObservationIgnored
  @AppStorage("proxy_port") var port: Int = 8080

  /// Proxy protocol type: "http" or "socks5"
  @ObservationIgnored
  @AppStorage("proxy_type") var type: String = "http"

  // MARK: - Thread-Safe Access

  /// Build the connectionProxyDictionary for URLSessionConfiguration.
  /// Reads directly from UserDefaults so it can be called from any thread.
  nonisolated func currentProxyDictionary() -> [AnyHashable: Any]? {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: "proxy_enabled") else { return nil }

    let host = (defaults.string(forKey: "proxy_host") ?? "").trimmingCharacters(in: .whitespaces)
    let port = defaults.integer(forKey: "proxy_port")
    let type = defaults.string(forKey: "proxy_type") ?? "http"

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

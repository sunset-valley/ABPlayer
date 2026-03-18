import Foundation
import ObjectiveC

/// Installs a global URLSession proxy by swizzling URLSessionConfiguration.default
/// and URLSession.shared so that all internal sessions created by WhisperKit and
/// swift-transformers route through the configured proxy when enabled.
///
/// Call `install(settings:)` once at app startup before any network activity.
enum URLSessionProxyInjector {

  /// Reference to ProxySettings. Written once at startup; read-only thereafter.
  nonisolated(unsafe) static var proxySettings: ProxySettings?

  /// Swizzles URLSessionConfiguration.default and URLSession.shared.
  /// Must be called on the main thread during app initialization.
  @MainActor
  static func install(settings: ProxySettings) {
    proxySettings = settings
    swizzleDefaultConfiguration()
    swizzleSharedSession()
  }

  // MARK: - Private

  private static func swizzleDefaultConfiguration() {
    guard
      let original = class_getClassMethod(
        URLSessionConfiguration.self,
        #selector(getter: URLSessionConfiguration.default)
      ),
      let swizzled = class_getClassMethod(
        URLSessionConfiguration.self,
        #selector(URLSessionConfiguration.abp_defaultConfiguration)
      )
    else { return }
    method_exchangeImplementations(original, swizzled)
  }

  private static func swizzleSharedSession() {
    guard
      let original = class_getClassMethod(
        URLSession.self,
        #selector(getter: URLSession.shared)
      ),
      let swizzled = class_getClassMethod(
        URLSession.self,
        #selector(URLSession.abp_sharedSession)
      )
    else { return }
    method_exchangeImplementations(original, swizzled)
  }
}

// MARK: - URLSessionConfiguration swizzle

extension URLSessionConfiguration {

  /// After swizzling, calling this invokes the original `.default` implementation.
  @objc dynamic class func abp_defaultConfiguration() -> URLSessionConfiguration {
    // Post-swizzle: this call resolves to the original implementation.
    let config = self.abp_defaultConfiguration()
    if let proxyDict = URLSessionProxyInjector.proxySettings?.currentProxyDictionary() {
      config.connectionProxyDictionary = proxyDict
    }
    return config
  }
}

// MARK: - URLSession.shared swizzle

extension URLSession {

  /// Cached proxied session returned in place of URLSession.shared when proxy is active.
  nonisolated(unsafe) private static var _proxiedSharedSession: URLSession?
  /// The proxy dictionary that was used to create _proxiedSharedSession.
  nonisolated(unsafe) private static var _proxiedSharedDict: [AnyHashable: Any]?

  /// After swizzling, calling this invokes the original `.shared` implementation.
  @objc dynamic class func abp_sharedSession() -> URLSession {
    guard let proxyDict = URLSessionProxyInjector.proxySettings?.currentProxyDictionary() else {
      // No proxy configured — return original shared session.
      return self.abp_sharedSession()
    }

    // Reuse cached session if proxy config hasn't changed.
    if let cached = _proxiedSharedSession,
      let cachedDict = _proxiedSharedDict,
      NSDictionary(dictionary: cachedDict).isEqual(to: NSDictionary(dictionary: proxyDict))
    {
      return cached
    }

    // Create a new default config (goes through our swizzled default, injecting proxy).
    let session = URLSession(configuration: URLSessionConfiguration.default)
    _proxiedSharedSession = session
    _proxiedSharedDict = proxyDict
    return session
  }
}

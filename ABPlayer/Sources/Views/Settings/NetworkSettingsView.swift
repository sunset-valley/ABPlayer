import SwiftUI

struct NetworkSettingsView: View {
  @Environment(ProxySettings.self) private var proxySettings

  enum ProxyTestStatus: Equatable {
    case idle
    case testing
    case success(latency: Int)
    case failure(String)
  }

  @State private var proxyTestStatus: ProxyTestStatus = .idle

  var body: some View {
    Form {
      Section {
        Toggle(
          "Enable Proxy",
          isOn: Binding(
            get: { proxySettings.isEnabled },
            set: { newValue in
              proxySettings.isEnabled = newValue
              proxyTestStatus = .idle
            }
          )
        )

        Picker(
          "Protocol",
          selection: Binding(
            get: { proxySettings.type },
            set: { newValue in
              proxySettings.type = newValue
            }
          )
        ) {
          Text("HTTP").tag("http")
          Text("SOCKS5").tag("socks5")
        }
        .disabled(!proxySettings.isEnabled)

        TextField(
          "Host",
          text: Binding(
            get: { proxySettings.host },
            set: { proxySettings.host = $0 }
          )
        )
        .disabled(!proxySettings.isEnabled)

        TextField(
          "Port",
          value: Binding(
            get: { proxySettings.port },
            set: { proxySettings.port = $0 }
          ),
          format: .number.grouping(.never)
        )
        .disabled(!proxySettings.isEnabled)

        HStack(spacing: 12) {
          Button("Test Connection") {
            Task { await testProxy() }
          }
          .disabled(!proxySettings.isEnabled || !proxySettings.isConfigured || proxyTestStatus == .testing)

          switch proxyTestStatus {
          case .idle:
            EmptyView()
          case .testing:
            HStack(spacing: 6) {
              ProgressView()
                .controlSize(.small)
              Text("Testing...")
            }
            .foregroundStyle(.secondary)
            .font(.callout)
          case .success(let ms):
            Label("Connected (\(ms) ms)", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .font(.callout)
          case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
              .foregroundStyle(.red)
              .font(.callout)
              .lineLimit(2)
          }
        }
      } header: {
        Label("Proxy", systemImage: "lock.shield")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          Text(
            "When enabled, model downloads and API requests are routed through the specified proxy server."
          )
          if proxySettings.isEnabled && !proxySettings.isConfigured {
            Text("Enter a host and port to activate the proxy.")
              .foregroundStyle(.orange)
          }
        }
        .captionStyle()
      }
    }
    .formStyle(.grouped)
  }

  private func testProxy() async {
    proxyTestStatus = .testing

    let host = proxySettings.host.trimmingCharacters(in: .whitespaces)
    let port = proxySettings.port
    let type = proxySettings.type

    let proxyDict: [AnyHashable: Any]
    if type == "socks5" {
      proxyDict = [
        kCFStreamPropertySOCKSProxyHost as AnyHashable: host,
        kCFStreamPropertySOCKSProxyPort as AnyHashable: port,
      ]
    } else {
      proxyDict = [
        kCFNetworkProxiesHTTPEnable as AnyHashable: true,
        kCFNetworkProxiesHTTPProxy as AnyHashable: host,
        kCFNetworkProxiesHTTPPort as AnyHashable: port,
        "HTTPSEnable" as AnyHashable: true,
        "HTTPSProxy" as AnyHashable: host,
        "HTTPSPort" as AnyHashable: port,
      ]
    }

    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = proxyDict
    config.timeoutIntervalForRequest = 10
    let session = URLSession(configuration: config)

    let testURL = URL(string: "https://baidu.com")!
    let start = Date()

    do {
      var request = URLRequest(url: testURL)
      request.httpMethod = "HEAD"
      let (_, response) = try await session.data(for: request)
      let ms = Int(Date().timeIntervalSince(start) * 1000)
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      if statusCode < 500 {
        proxyTestStatus = .success(latency: ms)
      } else {
        proxyTestStatus = .failure("Server returned \(statusCode)")
      }
    } catch {
      proxyTestStatus = .failure(error.localizedDescription)
    }
  }
}

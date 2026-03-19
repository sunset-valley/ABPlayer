import SwiftUI

/// Settings view for configuring application options
struct SettingsView: View {
  @State private var selectedTab: SettingsTab? = .media

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedTab) {
        ForEach(SettingsTab.allCases) { tab in
          NavigationLink(value: tab) {
            Label(tab.rawValue, systemImage: tab.icon)
          }
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .navigationSplitViewColumnWidth(min: 200, ideal: 200)
    } detail: {
      Group {
        if let selectedTab {
          switch selectedTab {
          case .media:
            MediaSettingsView()
          case .network:
            NetworkSettingsView()
          case .shortcuts:
            ShortcutsSettingsView()
          case .transcription:
            TranscriptionSettingsView()
          case .plugins:
            PluginsSettingsView()
          }
        } else {
          ContentUnavailableView("Select a setting", systemImage: "gear")
        }
      }
      .navigationTitle("Settings")
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 400, idealWidth: 600)
    .frame(minHeight: 400, idealHeight: 600)
  }
}

// MARK: - Preview

#Preview {
  SettingsView()
    .environment(TranscriptionSettings())
    .environment(LibrarySettings())
    .environment(PlayerSettings())
    .environment(ProxySettings())
    .environment(TranscriptionManager())
    .frame(width: 800, height: 600)
}

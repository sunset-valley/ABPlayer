#if !APPSTORE
  import SwiftUI

  struct UpdateSettingsView: View {
    @Environment(SparkleUpdater.self) private var updater

    var body: some View {
      Form {
        updateSection
        sourceSection
      }
      .formStyle(.grouped)
    }

    private var updateSection: some View {
      Section {
        LabeledContent("Current Version") {
          Text(currentVersionText)
            .monospacedDigit()
            .textSelection(.enabled)
        }

        Button("Check for Updates...") {
          updater.checkForUpdates()
        }
      } header: {
        Label("Update", systemImage: "arrow.triangle.2.circlepath")
      }
    }

    private var sourceSection: some View {
      Section {
        Picker(
          "Source",
          selection: Binding(
            get: { updater.selectedFeedSource },
            set: { updater.selectedFeedSource = $0 }
          )
        ) {
          ForEach(UpdateFeedSource.allCases) { source in
            Text(source.rawValue).tag(source)
          }
        }
      } header: {
        Label("Update Source", systemImage: "link")
      } footer: {
        Text("The selected source is used for all Sparkle update checks.")
          .captionStyle()
      }
    }

    private var currentVersionText: String {
      let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
      let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
      return "\(shortVersion) (\(buildVersion))"
    }
  }
#endif

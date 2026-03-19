import KeyboardShortcuts
import SwiftUI

struct PluginsSettingsView: View {
  var body: some View {
    Form {
      Section("Counter") {
        Toggle(
          "Always on Top",
          isOn: Binding(
            get: { CounterPlugin.shared.settings.alwaysOnTop },
            set: { newValue in
              CounterPlugin.shared.settings.alwaysOnTop = newValue
              CounterPlugin.shared.updateWindowLevel()
            }
          ))

        KeyboardShortcuts.Recorder("Increment (+):", name: .counterIncrement)
        KeyboardShortcuts.Recorder("Decrement (-):", name: .counterDecrement)
        KeyboardShortcuts.Recorder("Reset:", name: .counterReset)
      }
    }
    .formStyle(.grouped)
  }
}

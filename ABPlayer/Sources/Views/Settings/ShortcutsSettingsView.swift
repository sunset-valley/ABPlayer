import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
  @State private var showResetConfirmation = false

  var body: some View {
    Form {
      Section("Playback") {
        shortcutRow(title: "Play/Pause:", name: .playPause)
        shortcutRow(title: "Rewind 5s:", name: .rewind5s)
        shortcutRow(title: "Forward 10s:", name: .forward10s)
      }

      Section("Loop Controls") {
        shortcutRow(title: "Set Point A:", name: .setPointA)
        shortcutRow(title: "Set Point B:", name: .setPointB)
        shortcutRow(title: "Clear Loop:", name: .clearLoop)
        shortcutRow(title: "Save Segment:", name: .saveSegment)
      }

      Section("Navigation") {
        shortcutRow(title: "Previous Segment:", name: .previousSegment)
        shortcutRow(title: "Next Segment:", name: .nextSegment)
      }

      Section {
        HStack {
          Spacer()
          Button("Reset to Defaults") {
            showResetConfirmation = true
          }
          .buttonStyle(.borderedProminent)
          Spacer()
        }
      } footer: {
        Text("Reset all keyboard shortcuts to their default values")
          .captionStyle()
      }
    }
    .formStyle(.grouped)
    .confirmationDialog(
      "Reset Keyboard Shortcuts",
      isPresented: $showResetConfirmation
    ) {
      Button("Reset to Defaults", role: .destructive) {
        resetAllShortcuts()
      }
      Button("Cancel", role: .cancel) {
        showResetConfirmation = false
      }
    } message: {
      Text("Are you sure you want to reset all keyboard shortcuts to their default values?")
    }
  }

  private func shortcutRow(title: String, name: KeyboardShortcuts.Name) -> some View {
    KeyboardShortcuts.Recorder(title, name: name)
  }

  private func resetAllShortcuts() {
    KeyboardShortcuts.reset(.playPause)
    KeyboardShortcuts.reset(.rewind5s)
    KeyboardShortcuts.reset(.forward10s)
    KeyboardShortcuts.reset(.setPointA)
    KeyboardShortcuts.reset(.setPointB)
    KeyboardShortcuts.reset(.clearLoop)
    KeyboardShortcuts.reset(.saveSegment)
    KeyboardShortcuts.reset(.previousSegment)
    KeyboardShortcuts.reset(.nextSegment)
  }
}

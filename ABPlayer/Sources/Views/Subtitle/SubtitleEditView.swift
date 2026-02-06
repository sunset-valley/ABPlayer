import SwiftUI

struct SubtitleEditView: View {
  @Environment(\.dismiss) private var dismiss

  private let originalSubtitle: String
  private let onConfirm: (String) -> Void

  @State private var editableSubtitle: String

  init(subtitle: String, onConfirm: @escaping (String) -> Void) {
    self.originalSubtitle = subtitle
    self.onConfirm = onConfirm
    _editableSubtitle = State(initialValue: subtitle)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Edit Subtitle")
        .font(.headline)

      TextEditor(text: $editableSubtitle)
        .font(.body)
        .frame(minHeight: 140)
        .padding(6)
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )

      HStack {
        Spacer()

        Button("Cancel") {
          editableSubtitle = originalSubtitle
          dismiss()
        }

        Button("Confirm") {
          onConfirm(editableSubtitle)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(editableSubtitle == originalSubtitle)
      }
    }
    .padding(16)
    .frame(minWidth: 420, minHeight: 240)
  }
}

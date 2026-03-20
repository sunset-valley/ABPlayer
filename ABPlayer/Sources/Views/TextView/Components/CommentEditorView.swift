import SwiftUI

/// Inline editor for annotation comments
struct CommentEditorView: View {
  @State private var comment: String
  let onSave: (String?) -> Void
  let onCancel: () -> Void

  init(existingComment: String?, onSave: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
    self._comment = State(initialValue: existingComment ?? "")
    self.onSave = onSave
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Comment")
        .font(.caption)
        .foregroundStyle(.secondary)

      TextEditor(text: $comment)
        .font(.body)
        .frame(minHeight: 60, maxHeight: 120)
        .scrollContentBackground(.hidden)
        .padding(4)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.primary.opacity(0.05))
        )

      HStack {
        Button("Cancel") {
          onCancel()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        Spacer()

        if !comment.isEmpty {
          Button("Clear") {
            onSave(nil)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        Button("Save") {
          onSave(comment.isEmpty ? nil : comment)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    }
    .padding(12)
    .frame(width: 260)
  }
}

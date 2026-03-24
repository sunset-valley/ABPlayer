import SwiftUI

struct NotesBrowserNoteEditorView: View {
  @Environment(\.dismiss) private var dismiss

  private let entryTitle: String
  private let initialNote: String
  private let onSave: (String?) -> Void

  @State private var editableNote: String

  init(entryTitle: String, existingNote: String?, onSave: @escaping (String?) -> Void) {
    self.entryTitle = entryTitle
    self.initialNote = existingNote ?? ""
    self.onSave = onSave
    _editableNote = State(initialValue: existingNote ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(initialNote.isEmpty ? "Add Note" : "Edit Note")
        .font(.headline)

      Text(entryTitle)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      TextEditor(text: $editableNote)
        .font(.body)
        .frame(minHeight: 160)
        .padding(6)
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .accessibilityIdentifier("notes-browser-note-editor-text-editor")

      HStack {
        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .accessibilityIdentifier("notes-browser-note-editor-cancel")

        Button("Save") {
          onSave(editableNote)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(editableNote == initialNote)
        .accessibilityIdentifier("notes-browser-note-editor-save")
      }
    }
    .padding(16)
    .frame(minWidth: 460, minHeight: 280)
  }
}

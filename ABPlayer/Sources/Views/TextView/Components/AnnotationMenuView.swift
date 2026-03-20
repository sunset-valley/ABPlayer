import SwiftUI

/// Menu shown when user selects text or taps an existing annotation
struct AnnotationMenuView: View {
  let selectedText: String
  let existingAnnotation: AnnotationDisplayData?
  let onAnnotate: (AnnotationType) -> Void
  let onEditComment: () -> Void
  let onChangeType: (AnnotationType) -> Void
  let onDelete: () -> Void
  let onLookup: () -> Void
  let onCopy: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let annotation = existingAnnotation {
        existingAnnotationMenu(annotation)
      } else {
        newSelectionMenu
      }
    }
    .padding(8)
    .frame(minWidth: 160)
  }

  // MARK: - New Selection Menu

  private var newSelectionMenu: some View {
    VStack(alignment: .leading, spacing: 2) {
      menuButton("Copy", systemImage: "doc.on.doc") {
        onCopy()
        onDismiss()
      }

      menuButton("Look Up", systemImage: "book") {
        onLookup()
      }

      Divider()
        .padding(.vertical, 4)

      Text("Mark as...")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)

      annotationTypeButton(.vocabulary, label: "Vocabulary", systemImage: "textformat.abc")
      annotationTypeButton(.collocation, label: "Collocation", systemImage: "link")
      annotationTypeButton(.goodSentence, label: "Good Sentence", systemImage: "star")
    }
  }

  // MARK: - Existing Annotation Menu

  private func existingAnnotationMenu(_ annotation: AnnotationDisplayData) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Circle()
          .fill(Color(nsColor: AnnotationColorConfig.default.color(for: annotation.type)))
          .frame(width: 8, height: 8)
        Text(annotation.type.displayName)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.bottom, 4)

      menuButton("Copy", systemImage: "doc.on.doc") {
        onCopy()
        onDismiss()
      }

      menuButton("Look Up", systemImage: "book") {
        onLookup()
      }

      menuButton(
        annotation.comment != nil ? "Edit Comment" : "Add Comment",
        systemImage: "text.bubble"
      ) {
        onEditComment()
      }

      Divider()
        .padding(.vertical, 4)

      Text("Change type...")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)

      ForEach(AnnotationType.allCases.filter { $0 != annotation.type }, id: \.self) { type in
        annotationTypeButton(type, label: type.displayName, systemImage: type.systemImage) {
          onChangeType(type)
          onDismiss()
        }
      }

      Divider()
        .padding(.vertical, 4)

      menuButton("Remove", systemImage: "trash", role: .destructive) {
        onDelete()
        onDismiss()
      }
    }
  }

  // MARK: - Helpers

  private func menuButton(
    _ title: String,
    systemImage: String,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: role, action: action) {
      Label(title, systemImage: systemImage)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }

  private func annotationTypeButton(
    _ type: AnnotationType,
    label: String,
    systemImage: String,
    action: (() -> Void)? = nil
  ) -> some View {
    Button {
      if let action {
        action()
      } else {
        onAnnotate(type)
        onDismiss()
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .foregroundStyle(Color(nsColor: AnnotationColorConfig.default.color(for: type)))
        Text(label)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }
}

// MARK: - AnnotationType Display Helpers

extension AnnotationType {
  var displayName: String {
    switch self {
    case .vocabulary: return "Vocabulary"
    case .collocation: return "Collocation"
    case .goodSentence: return "Good Sentence"
    }
  }

  var systemImage: String {
    switch self {
    case .vocabulary: return "textformat.abc"
    case .collocation: return "link"
    case .goodSentence: return "star"
    }
  }
}

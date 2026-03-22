import AppKit
import SwiftUI

/// Menu shown when user selects text or taps an existing annotation.
struct AnnotationMenuView: View {
  @Environment(\.openWindow) private var openWindow

  let selectedText: String
  let existingAnnotation: AnnotationRenderData?
  let styles: [AnnotationStyleDisplayData]
  let onAnnotate: (UUID) -> Void
  let onEditComment: () -> Void
  let onChangeStyle: (UUID) -> Void
  let onDelete: () -> Void
  let onLookup: () -> Void
  let onCopy: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let annotation = existingAnnotation {
        existingAnnotationMenu(annotation)
      } else {
        newSelectionMenu
      }
    }
    .padding(12)
    .frame(minWidth: 280, maxWidth: 340, alignment: .leading)
  }

  // MARK: - Menus

  private var newSelectionMenu: some View {
    VStack(alignment: .leading, spacing: 12) {
      actionSection

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          sectionTitle("MARK AS")
          Spacer(minLength: 8)
          manageStylesButton
        }

        styleCards
      }
    }
  }

  private func existingAnnotationMenu(_ annotation: AnnotationRenderData) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Circle()
          .fill(Color(nsColor: annotation.styleDisplay.underlineColor))
          .frame(width: 8, height: 8)
        Text(annotation.styleName)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      actionSection

      menuButton(
        annotation.comment != nil ? "Edit Comment" : "Add Comment",
        systemImage: "text.bubble"
      ) {
        onEditComment()
      }
      .accessibilityIdentifier("annotation-edit-comment")

      VStack(alignment: .leading, spacing: 8) {
        sectionTitle("Switch Style")
        styleRows(isChangingExisting: true, selectedStyleID: annotation.stylePresetID)
      }

      menuButton("Remove Annotation", systemImage: "trash", role: .destructive) {
        onDelete()
        onDismiss()
      }
      .accessibilityIdentifier("annotation-remove")
    }
  }

  private var actionSection: some View {
    HStack(spacing: 4) {
      menuButton("Copy", systemImage: "doc.on.doc") {
        onCopy()
        onDismiss()
      }
      .accessibilityIdentifier("menu-copy")

      menuButton("Look Up", systemImage: "book") {
        onLookup()
      }
      .accessibilityIdentifier("menu-lookup")
    }
  }

  // MARK: - Style selection

  private var styleCards: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(Array(styles.enumerated()), id: \.element.id) { index, style in
          styleCard(style, index: index)
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func styleCard(_ style: AnnotationStyleDisplayData, index: Int) -> some View {
    Button {
      applyStyle(style.id, isChangingExisting: false)
    } label: {
      VStack(spacing: 8) {
        styleTokenPreview(style)
          .frame(width: 56, height: 18)

        Text(style.name)
          .font(.caption)
          .fontWeight(.semibold)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 10)
      .frame(width: 98)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
      )
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("style-row-action-\(index)")
  }

  private func styleRows(isChangingExisting: Bool, selectedStyleID: UUID?) -> some View {
    ForEach(Array(styles.enumerated()), id: \.element.id) { index, style in
      Button {
        applyStyle(style.id, isChangingExisting: isChangingExisting)
      } label: {
        HStack(spacing: 8) {
          Image(systemName: selectedStyleID == style.id ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selectedStyleID == style.id ? Color.accentColor : Color.secondary)
          Text(style.name)
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 0)
          stylePreview(style)
            .frame(maxWidth: 80)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("style-list-action-\(index)")
    }
  }

  // MARK: - Style management

  private var manageStylesButton: some View {
    Button {
      openWindow(id: "annotation-style-manager")
      onDismiss()
    } label: {
      Label("Manage", systemImage: "slider.horizontal.3")
        .font(.caption)
        .fontWeight(.semibold)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(
      Capsule(style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    )
    .accessibilityIdentifier("style-manage-toggle")
  }

  private func styleTokenPreview(_ style: AnnotationStyleDisplayData) -> some View {
    Group {
      switch style.kind {
      case .underline:
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(Color(nsColor: style.underlineColor))
          .frame(height: 2)
      case .background:
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(Color(nsColor: style.backgroundColor).opacity(0.45))
          .frame(height: 10)
      case .underlineAndBackground:
        VStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(nsColor: style.backgroundColor).opacity(0.45))
            .frame(height: 8)
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color(nsColor: style.underlineColor))
            .frame(height: 2)
        }
      }
    }
  }

  private func stylePreview(_ style: AnnotationStyleDisplayData) -> some View {
    let text = Text("Preview")
      .font(.caption)

    return Group {
      switch style.kind {
      case .underline:
        text
          .underline(true, color: Color(nsColor: style.underlineColor))
      case .background:
        text
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .fill(Color(nsColor: style.backgroundColor).opacity(0.3))
          )
      case .underlineAndBackground:
        text
          .underline(true, color: Color(nsColor: style.underlineColor))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .fill(Color(nsColor: style.backgroundColor).opacity(0.3))
          )
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
  }

  // MARK: - Small helpers

  private func applyStyle(_ styleID: UUID, isChangingExisting: Bool) {
    if isChangingExisting {
      onChangeStyle(styleID)
    } else {
      onAnnotate(styleID)
    }
    onDismiss()
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.caption)
      .foregroundStyle(.secondary)
  }

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
    .padding(.vertical, 5)
    .contentShape(Rectangle())
  }
}

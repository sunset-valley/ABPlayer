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
    .frame(minWidth: 320, maxWidth: 420, alignment: .leading)
  }

  // MARK: - Menus

  private var newSelectionMenu: some View {
    menuContent(
      isChangingExisting: false,
      selectedStyleID: nil,
      includeExistingActions: false
    )
  }

  private func existingAnnotationMenu(_ annotation: AnnotationRenderData) -> some View {
    menuContent(
      isChangingExisting: true,
      selectedStyleID: annotation.stylePresetID,
      includeExistingActions: true
    )
  }

  private func menuContent(
    isChangingExisting: Bool,
    selectedStyleID: UUID?,
    includeExistingActions: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      actionSection(includeExistingActions: includeExistingActions, annotation: existingAnnotation)

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          sectionTitle("MARK AS")
          Spacer(minLength: 8)
          manageStylesButton
        }

        styleCards(
          isChangingExisting: isChangingExisting,
          selectedStyleID: selectedStyleID
        )
      }
    }
  }

  private func actionSection(
    includeExistingActions: Bool,
    annotation: AnnotationRenderData?
  ) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        actionPill("Copy", systemImage: "doc.on.doc") {
          onCopy()
          onDismiss()
        }
        .accessibilityIdentifier("menu-copy")

        actionPill("Look Up", systemImage: "book") {
          onLookup()
        }
        .accessibilityIdentifier("menu-lookup")

        if includeExistingActions, let annotation {
          actionPill(
            annotation.comment != nil ? "Edit Comment" : "Add Comment",
            systemImage: "text.bubble"
          ) {
            onEditComment()
          }
          .accessibilityIdentifier("annotation-edit-comment")

          actionPill("", systemImage: "trash", role: .destructive) {
            onDelete()
            onDismiss()
          }
          .accessibilityIdentifier("annotation-remove")
        }
      }
      .padding(.vertical, 1)
    }
    .scrollIndicators(.hidden)
  }

  // MARK: - Style selection

  private func styleCards(
    isChangingExisting: Bool,
    selectedStyleID: UUID?
  ) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(Array(styles.enumerated()), id: \.element.id) { index, style in
          styleCard(
            style,
            index: index,
            isChangingExisting: isChangingExisting,
            isSelected: selectedStyleID == style.id
          )
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func styleCard(
    _ style: AnnotationStyleDisplayData,
    index: Int,
    isChangingExisting: Bool,
    isSelected: Bool
  ) -> some View {
    Button {
      applyStyle(style.id, isChangingExisting: isChangingExisting)
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
          .fill(
            isSelected && isChangingExisting
              ? Color.accentColor.opacity(0.16)
              : Color(nsColor: .controlBackgroundColor).opacity(0.72)
          )
      )
      .overlay {
        if isSelected && isChangingExisting {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("style-row-action-\(index)")
    .accessibilityValue(
      Text(isChangingExisting && isSelected ? "selected" : "unselected")
    )
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

  private func actionPill(
    _ title: String,
    systemImage: String,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: role, action: action) {
      if title.isEmpty {
        Image(systemName: systemImage)
      } else {
        Label(title, systemImage: systemImage)
      }
    }
    .font(.caption)
    .fontWeight(.semibold)
    .lineLimit(1)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .foregroundStyle(role == .destructive ? Color.red : Color.primary)
    .background(
      Capsule(style: .continuous)
        .fill(
          role == .destructive
          ? Color.red.opacity(0.13)
          : Color(nsColor: .controlBackgroundColor).opacity(0.82)
        )
    )
    .buttonStyle(.plain)
    .contentShape(Capsule(style: .continuous))
  }
}

import AppKit
import SwiftUI

/// Menu shown when user selects text or taps an existing annotation.
struct AnnotationMenuView: View {
  let selectedText: String
  let existingAnnotation: AnnotationRenderData?
  let styles: [AnnotationStyleDisplayData]
  let styleUsageCount: (UUID) -> Int
  let onAnnotate: (UUID) -> Void
  let onEditComment: () -> Void
  let onChangeStyle: (UUID) -> Void
  let onAddStyle: () -> Void
  let onUpdateStyleName: (UUID, String) -> Void
  let onUpdateStyleKind: (UUID, AnnotationStyleKind) -> Void
  let onUpdateUnderlineColor: (UUID, NSColor) -> Void
  let onUpdateBackgroundColor: (UUID, NSColor) -> Void
  let onDeleteStyle: (UUID) -> Bool
  let onDelete: () -> Void
  let onLookup: () -> Void
  let onCopy: () -> Void
  let onDismiss: () -> Void

  @State private var styleDeleteAlertMessage: String?
  @State private var draftStyleNames: [UUID: String] = [:]

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
    .alert(
      "Cannot Delete Style",
      isPresented: Binding(
        get: { styleDeleteAlertMessage != nil },
        set: { newValue in
          if !newValue {
            styleDeleteAlertMessage = nil
          }
        }
      )
    ) {
      Button("OK", role: .cancel) { styleDeleteAlertMessage = nil }
    } message: {
      Text(styleDeleteAlertMessage ?? "")
    }
  }

  // MARK: - Menus

  private var newSelectionMenu: some View {
    VStack(alignment: .leading, spacing: 12) {
      actionSection

      VStack(alignment: .leading, spacing: 8) {
        sectionTitle("Styles")
        styleRows(isChangingExisting: false, selectedStyleID: nil)
        addStyleButton
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

      VStack(alignment: .leading, spacing: 8) {
        sectionTitle("Switch Style")
        styleRows(isChangingExisting: true, selectedStyleID: annotation.stylePresetID)
      }

      menuButton("Remove Annotation", systemImage: "trash", role: .destructive) {
        onDelete()
        onDismiss()
      }
    }
  }

  private var actionSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      menuButton("Copy", systemImage: "doc.on.doc") {
        onCopy()
        onDismiss()
      }

      menuButton("Look Up", systemImage: "book") {
        onLookup()
      }
    }
  }

  // MARK: - Style rows

  @ViewBuilder
  private func styleRows(isChangingExisting: Bool, selectedStyleID: UUID?) -> some View {
    ForEach(styles) { style in
      styleRow(style, isChangingExisting: isChangingExisting, selectedStyleID: selectedStyleID)
    }
  }

  private func styleRow(
    _ style: AnnotationStyleDisplayData,
    isChangingExisting: Bool,
    selectedStyleID: UUID?
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Button {
          if isChangingExisting {
            onChangeStyle(style.id)
          } else {
            onAnnotate(style.id)
          }
          onDismiss()
        } label: {
          HStack(spacing: 8) {
            Image(systemName: selectedStyleID == style.id ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(selectedStyleID == style.id ? Color.accentColor : Color.secondary)
            Text(style.name)
              .font(.subheadline)
              .lineLimit(1)
              .truncationMode(.tail)
            Spacer(minLength: 0)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Button {
          let usage = styleUsageCount(style.id)
          guard usage == 0 else {
            styleDeleteAlertMessage =
              "This style is still in use. Switch affected annotations to another style before deleting it."
            return
          }
          let deleted = onDeleteStyle(style.id)
          if !deleted {
            styleDeleteAlertMessage =
              "Unable to delete this style right now. Please try again after switching affected annotations."
          }
        } label: {
          Image(systemName: "trash")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Delete style")
      }

      HStack(spacing: 8) {
        TextField(
          "Style name",
          text: Binding(
            get: { draftStyleNames[style.id] ?? style.name },
            set: { draftStyleNames[style.id] = $0 }
          )
        )
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          onUpdateStyleName(style.id, draftStyleNames[style.id] ?? style.name)
        }
        .onAppear {
          if draftStyleNames[style.id] == nil {
            draftStyleNames[style.id] = style.name
          }
        }

        Picker(
          "Kind",
          selection: Binding(
            get: { style.kind },
            set: { onUpdateStyleKind(style.id, $0) }
          )
        ) {
          Text("Underline").tag(AnnotationStyleKind.underline)
          Text("Background").tag(AnnotationStyleKind.background)
          Text("Underline + BG").tag(AnnotationStyleKind.underlineAndBackground)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 130)
      }

      HStack(spacing: 8) {
        colorPicker(
          title: "Underline",
          color: style.underlineColor,
          onChange: { onUpdateUnderlineColor(style.id, $0) }
        )

        colorPicker(
          title: "Background",
          color: style.backgroundColor,
          onChange: { onUpdateBackgroundColor(style.id, $0) }
        )

        stylePreview(style)
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
    )
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

  private func colorPicker(
    title: String,
    color: NSColor,
    onChange: @escaping (NSColor) -> Void
  ) -> some View {
    ColorPicker(
      title,
      selection: Binding(
        get: { Color(nsColor: color) },
        set: { onChange(NSColor($0)) }
      ),
      supportsOpacity: false
    )
    .labelsHidden()
    .frame(width: 28)
    .help(title)
  }

  private var addStyleButton: some View {
    Button {
      onAddStyle()
    } label: {
      Label("Add Style", systemImage: "plus")
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }

  // MARK: - Small helpers

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

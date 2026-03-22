import AppKit
import SwiftUI

@MainActor
struct AnnotationStyleManagerView: View {
  @Environment(AnnotationStyleService.self) private var annotationStyleService
  @Environment(AnnotationService.self) private var annotationService

  @State private var styleDeleteAlertMessage: String?
  @State private var draftStyleNames: [UUID: String] = [:]

  var body: some View {
    let _ = annotationStyleService.version
    let styles = annotationStyleService.allStyles()

    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("STYLE MANAGEMENT")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer(minLength: 8)
          Text("\(styles.count)")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        ForEach(Array(styles.enumerated()), id: \.element.id) { index, style in
          styleRow(style, index: index)
        }

        addStyleButton
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
      )
      .padding(14)
    }
    .accessibilityIdentifier("style-manage-panel")
    .frame(minWidth: 560, minHeight: 360, alignment: .topLeading)
    .background(Color(nsColor: .underPageBackgroundColor).opacity(0.42))
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

  private func styleRow(_ style: AnnotationStyleDisplayData, index: Int) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        styleTokenPreview(style)
          .frame(width: 22, height: 16)

        TextField(
          "Style name",
          text: Binding(
            get: { draftStyleNames[style.id] ?? style.name },
            set: { draftStyleNames[style.id] = $0 }
          )
        )
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          annotationStyleService.updateStyleName(
            styleID: style.id,
            name: draftStyleNames[style.id] ?? style.name
          )
        }
        .onAppear {
          if draftStyleNames[style.id] == nil {
            draftStyleNames[style.id] = style.name
          }
        }
        .accessibilityIdentifier("style-name-\(index)")

        Button {
          deleteStyle(style.id)
        } label: {
          Image(systemName: "trash")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Delete style")
        .accessibilityIdentifier("style-delete-\(index)")
      }

      HStack(spacing: 8) {
        Picker(
          "Kind",
          selection: Binding(
            get: { style.kind },
            set: { annotationStyleService.updateStyleKind(styleID: style.id, kind: $0) }
          )
        ) {
          Text("Underline").tag(AnnotationStyleKind.underline)
          Text("Background").tag(AnnotationStyleKind.background)
          Text("Underline + BG").tag(AnnotationStyleKind.underlineAndBackground)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 122)
        .accessibilityIdentifier("style-kind-\(index)")

        colorPicker(
          title: "Underline",
          color: style.underlineColor,
          onChange: { annotationStyleService.updateUnderlineColor(styleID: style.id, color: $0) }
        )

        colorPicker(
          title: "Background",
          color: style.backgroundColor,
          onChange: { annotationStyleService.updateBackgroundColor(styleID: style.id, color: $0) }
        )

        Spacer(minLength: 0)
        stylePreview(style)
          .frame(maxWidth: 78)
      }
    }
    .padding(9)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    )
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
      _ = annotationStyleService.addStyle(
        name: "Style",
        kind: .underlineAndBackground,
        underlineColor: .systemBlue,
        backgroundColor: .systemBlue
      )
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
    .accessibilityIdentifier("style-add")
  }

  private func deleteStyle(_ styleID: UUID) {
    let usage = annotationService.styleUsageCount(stylePresetID: styleID)
    guard usage == 0 else {
      styleDeleteAlertMessage =
        "This style is still in use. Switch affected annotations to another style before deleting it."
      return
    }

    let deleted = annotationStyleService.deleteStyle(styleID: styleID, usageCount: usage)
    if !deleted {
      styleDeleteAlertMessage =
        "Unable to delete this style right now. Please try again after switching affected annotations."
    }
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
}

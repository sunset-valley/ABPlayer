import SwiftUI

struct DynamicPaneView<PaneBody: View>: View {
  let title: String
  let tabs: [PaneContent]
  @Binding var selection: PaneContent?

  let addOptions: [PaneContent]
  let onAdd: (PaneContent) -> Void
  let onRemove: (PaneContent) -> Void

  @State private var hoveredTab: PaneContent?

  @ViewBuilder let bodyContent: (PaneContent) -> PaneBody

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
    }
    .onChange(of: tabs, initial: true) { _, newTabs in
      guard !newTabs.isEmpty else {
        selection = nil
        return
      }
      if let selection, newTabs.contains(selection) {
        return
      }
      selection = newTabs.first
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Text(title)
        .font(.headline)

      tabBar

      Spacer()

      Menu {
        if addOptions.isEmpty {
          Text("All views are already in this pane.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(addOptions) { content in
            Button {
              onAdd(content)
            } label: {
              Label(content.title, systemImage: content.systemImage)
            }
          }
        }
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 13, weight: .semibold))
          .frame(width: 24, height: 24)
      }
      .menuStyle(.borderlessButton)
      .help("Add (move) a view into this pane")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private var tabBar: some View {
    if tabs.isEmpty {
      EmptyView()
    } else {
      HStack(spacing: 6) {
        ForEach(tabs) { tab in
          HStack(spacing: 6) {
            Text(tab.title)
              .font(.subheadline.weight(.medium))
              .lineLimit(1)

            Button {
              onRemove(tab)
            } label: {
              Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .opacity(hoveredTab == tab || selection == tab ? 1 : 0)
            .help("Remove \(tab.title) from this pane")
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(selection == tab ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
          .overlay(
            Capsule()
              .strokeBorder(.quaternary, lineWidth: 1)
          )
          .contentShape(Capsule())
          .onTapGesture {
            selection = tab
          }
#if os(macOS)
          .onHover { isHovering in
            if isHovering {
              hoveredTab = tab
            } else if hoveredTab == tab {
              hoveredTab = nil
            }
          }
#endif
          .contextMenu {
            Button(role: .destructive) {
              onRemove(tab)
            } label: {
              Label("Remove", systemImage: "xmark")
            }
          }
        }
      }
    }
  }

  private var content: some View {
    VStack {
      if let selection {
        bodyContent(selection)
      } else {
        ContentUnavailableView(
          "No Views",
          systemImage: "rectangle.3.group",
          description: Text("Use + to add Transcription, PDF, or Segments.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
}

import SwiftUI

struct DynamicPaneView<PaneBody: View>: View {
  let title: String
  let tabs: [PaneContent]
  @Binding var selection: PaneContent?

  let addOptions: [PaneContent]
  let onAdd: (PaneContent) -> Void

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
          Button {
            selection = tab
          } label: {
            Text(tab.title)
              .font(.subheadline.weight(.medium))
              .lineLimit(1)
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(selection == tab ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
          .overlay(
            Capsule()
              .strokeBorder(.quaternary, lineWidth: 1)
          )
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

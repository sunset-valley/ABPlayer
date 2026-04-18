import SwiftUI

struct ContinueWatchingCardView: View {
  let item: FolderNavigationViewModel.ContinueWatchingItem
  let onPlay: () -> Void

  var body: some View {
    Button(action: onPlay) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Label("Continue Watching", systemImage: "clock.arrow.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)

          Spacer()

          if item.isCurrentFile {
            Text("Now Playing")
              .font(.caption2)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.regularMaterial, in: Capsule())
          }
        }

        Text(item.file.displayName)
          .lineLimit(1)
          .bodyStyle()

        HStack(spacing: 6) {
          Text(item.playbackPositionText)
          Text("•")
          Text(item.relativeTimeText)
        }
        .lineLimit(1)
        .captionStyle()

        if let progress = item.progress {
          ProgressView(value: progress)
            .controlSize(.small)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .padding(.horizontal, 12)
      .padding(.bottom, 8)
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
    .help("Play from last watched position")
  }

}

struct ContinueWatchingToolbarMenuView: View {
  let items: [FolderNavigationViewModel.ContinueWatchingItem]
  let isLoading: Bool
  let onLoadItems: @MainActor () async -> Void
  let onPlayItem: @MainActor (ABFile) async -> Void

  @State private var isPopoverPresented = false

  var body: some View {
    Button {
      isPopoverPresented.toggle()
    } label: {
      Label("Continue Watching", systemImage: "clock.arrow.circlepath")
    }
    .help("Continue Watching")
    .onChange(of: isPopoverPresented) { _, isPresented in
      guard isPresented else { return }
      Task { @MainActor in
        await onLoadItems()
      }
    }
    .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
      ContinueWatchingPopoverView(items: items, isLoading: isLoading) { file in
        Task { @MainActor in
          await onPlayItem(file)
          isPopoverPresented = false
        }
      }
      .frame(width: 340)
    }
  }
}

private struct ContinueWatchingPopoverView: View {
  let items: [FolderNavigationViewModel.ContinueWatchingItem]
  let isLoading: Bool
  let onPlayItem: (ABFile) -> Void

  var body: some View {
    Group {
      if items.isEmpty, isLoading {
        VStack(spacing: 12) {
          ProgressView()
          Text("Loading Continue Watching")
            .captionStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
      } else if items.isEmpty {
        ContentUnavailableView(
          "No Continue Watching",
          systemImage: "clock.arrow.circlepath",
          description: Text("Start watching a file to see it here")
        )
        .padding(.vertical, 24)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("Continue Watching")
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.top, 12)

          ScrollView {
            LazyVStack(spacing: 6) {
              ForEach(items) { item in
                ContinueWatchingRowView(item: item) {
                  onPlayItem(item.file)
                }
              }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
          }
        }
      }
    }
  }
}

private struct ContinueWatchingRowView: View {
  let item: FolderNavigationViewModel.ContinueWatchingItem
  let onPlay: () -> Void

  var body: some View {
    Button(action: onPlay) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Text(item.file.displayName)
            .lineLimit(1)
            .bodyStyle()

          Spacer(minLength: 0)

          if item.isCurrentFile {
            Text("Now Playing")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

        Text(item.folderPathSummary)
          .lineLimit(1)
          .captionStyle()

        HStack(spacing: 6) {
          Text(item.playbackPositionText)
          Text("•")
          Text(item.relativeTimeText)
        }
        .lineLimit(1)
        .captionStyle()

        if let progress = item.progress {
          ProgressView(value: progress)
            .controlSize(.small)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.primary.opacity(0.04))
      )
      .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .help("Play from last watched position")
  }

}

private extension FolderNavigationViewModel.ContinueWatchingItem {
  var playbackPositionText: String {
    if let duration, duration > 0 {
      return "\(MediaTimeFormatting.clock(from: position)) / \(MediaTimeFormatting.clock(from: duration))"
    }

    return MediaTimeFormatting.clock(from: position)
  }

  @MainActor
  var relativeTimeText: String {
    RelativeTimeFormatting.short(from: lastPlayedAt)
  }
}

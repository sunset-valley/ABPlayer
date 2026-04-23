import SwiftUI

struct RecentlyPlayedCardView: View {
  let item: FolderNavigationViewModel.RecentlyPlayedItem
  let onPlay: () -> Void

  var body: some View {
    Button(action: onPlay) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Label("Recently Played", systemImage: "clock.arrow.circlepath")
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
    .help("Play from saved position")
  }

}

struct RecentlyPlayedToolbarMenuView: View {
  let items: [FolderNavigationViewModel.RecentlyPlayedItem]
  let isLoading: Bool
  let onLoadItems: @MainActor () async -> Void
  let onPlayItem: @MainActor (ABFile) async -> Void

  @State private var isPopoverPresented = false

  var body: some View {
    Button {
      isPopoverPresented.toggle()
    } label: {
      Label("Recently Played", systemImage: "clock.arrow.circlepath")
    }
    .help("Recently Played")
    .onChange(of: isPopoverPresented) { _, isPresented in
      guard isPresented else { return }
      Task { @MainActor in
        await onLoadItems()
      }
    }
    .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
      RecentlyPlayedPopoverView(items: items, isLoading: isLoading) { file in
        Task { @MainActor in
          await onPlayItem(file)
          isPopoverPresented = false
        }
      }
      .frame(width: 340)
    }
  }
}

private struct RecentlyPlayedPopoverView: View {
  let items: [FolderNavigationViewModel.RecentlyPlayedItem]
  let isLoading: Bool
  let onPlayItem: (ABFile) -> Void

  var body: some View {
    Group {
      if items.isEmpty, isLoading {
        VStack(spacing: 12) {
          ProgressView()
          Text("Loading Recently Played")
            .captionStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
      } else if items.isEmpty {
        ContentUnavailableView(
          "No Recently Played",
          systemImage: "clock.arrow.circlepath",
          description: Text("Play a file to see it here")
        )
        .padding(.vertical, 24)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("Recently Played")
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.top, 12)

          ScrollView {
            LazyVStack(spacing: 6) {
              ForEach(items) { item in
                RecentlyPlayedRowView(item: item) {
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

private struct RecentlyPlayedRowView: View {
  let item: FolderNavigationViewModel.RecentlyPlayedItem
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
    .help("Play from saved position")
  }

}

private extension FolderNavigationViewModel.RecentlyPlayedItem {
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

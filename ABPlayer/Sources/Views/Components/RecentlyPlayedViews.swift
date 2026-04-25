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

          if item.isNowPlaying {
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
          .accessibilityIdentifier("recently-played-card-file-name")

        if item.isNowPlaying {
          Text("Now Playing")
            .lineLimit(1)
            .captionStyle()
            .accessibilityIdentifier("recently-played-card-bottom-now-playing")
        } else {
          HStack(spacing: 6) {
            Text(item.playbackPositionText)
            Text("•")
            Text(item.relativeTimeText)
          }
          .lineLimit(1)
          .captionStyle()
          .accessibilityIdentifier("recently-played-card-bottom-history")

          if let progress = item.progress {
            ProgressView(value: progress)
              .controlSize(.small)
              .accessibilityIdentifier("recently-played-card-progress")
          }
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
  let onPlayItem: @MainActor (ABFile) async -> Void

  var body: some View {
    RecentlyPlayedPopoverView(items: items, isLoading: isLoading) { file in
      Task { @MainActor in
        await onPlayItem(file)
      }
    }
    .frame(width: 340)
  }
}

private struct RecentlyPlayedPopoverView: View {
  let items: [FolderNavigationViewModel.RecentlyPlayedItem]
  let isLoading: Bool
  let onPlayItem: (ABFile) -> Void

  private let visibleRowLimit = 5
  private let rowMinHeight: CGFloat = 82
  private let rowSpacing: CGFloat = 6
  private let horizontalPadding: CGFloat = 8
  private let bottomPadding: CGFloat = 12

  var body: some View {
    Group {
      if items.isEmpty, isLoading {
        loadingContent
      } else if items.isEmpty {
        ContentUnavailableView(
          "No Recently Played",
          systemImage: "clock.arrow.circlepath",
          description: Text("Play a file to see it here")
        )
        .padding(.vertical, 24)
      } else {
        loadedContent
      }
    }
  }

  private var loadingContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      popoverTitle

      LazyVStack(spacing: rowSpacing) {
        ForEach(0 ..< visibleRowLimit, id: \.self) { index in
          RecentlyPlayedSkeletonRowView(index: index, rowMinHeight: rowMinHeight)
        }
      }
      .padding(.horizontal, horizontalPadding)
      .padding(.bottom, bottomPadding)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Loading recently played list")
    .accessibilityIdentifier("recently-played-skeleton-container")
  }

  private var loadedContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      popoverTitle

      if items.count > visibleRowLimit {
        ScrollView {
          rowsContent
        }
        .frame(maxHeight: maxListHeight(for: visibleRowLimit))
      } else {
        rowsContent
      }
    }
  }

  private var popoverTitle: some View {
    Text("Recently Played")
      .font(.headline)
      .accessibilityIdentifier("recently-played-popover-title")
      .padding(.horizontal, 12)
      .padding(.top, 12)
  }

  private var rowsContent: some View {
    LazyVStack(spacing: rowSpacing) {
      ForEach(items) { item in
        RecentlyPlayedRowView(item: item, rowMinHeight: rowMinHeight) {
          onPlayItem(item.file)
        }
      }
    }
    .padding(.horizontal, horizontalPadding)
    .padding(.bottom, bottomPadding)
  }

  private func maxListHeight(for count: Int) -> CGFloat {
    let visibleCount = max(0, count)
    let rowsHeight = CGFloat(visibleCount) * rowMinHeight
    let spacingHeight = CGFloat(max(0, visibleCount - 1)) * rowSpacing
    return rowsHeight + spacingHeight + bottomPadding
  }
}

private struct RecentlyPlayedSkeletonRowView: View {
  let index: Int
  let rowMinHeight: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color.primary.opacity(0.14))
        .frame(width: 170, height: 12)

      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color.primary.opacity(0.09))
        .frame(maxWidth: .infinity)
        .frame(height: 10)

      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color.primary.opacity(0.12))
        .frame(width: 130, height: 9)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: rowMinHeight, alignment: .topLeading)
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading recently played row \(index + 1)")
    .accessibilityIdentifier("recently-played-skeleton-row-\(index)")
  }
}

private struct RecentlyPlayedRowView: View {
  let item: FolderNavigationViewModel.RecentlyPlayedItem
  let rowMinHeight: CGFloat
  let onPlay: () -> Void

  private var fileIdentifierSuffix: String {
    item.file.displayName.replacingOccurrences(of: " ", with: "_")
  }

  var body: some View {
    Button(action: onPlay) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Text(item.file.displayName)
            .lineLimit(1)
            .bodyStyle()
            .accessibilityIdentifier("recently-played-row-file-\(fileIdentifierSuffix)")

          Spacer(minLength: 0)

          if item.isNowPlaying {
            Text("Now Playing")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

        Text(item.folderPathSummary)
          .lineLimit(1)
          .captionStyle()

        if item.isNowPlaying {
          Text("Now Playing")
            .lineLimit(1)
            .captionStyle()
            .accessibilityIdentifier("recently-played-row-bottom-\(fileIdentifierSuffix)")
        } else {
          HStack(spacing: 6) {
            Text(item.playbackPositionText)
            Text("•")
            Text(item.relativeTimeText)
          }
          .lineLimit(1)
          .captionStyle()
          .accessibilityIdentifier("recently-played-row-bottom-history-\(fileIdentifierSuffix)")

          if let progress = item.progress {
            ProgressView(value: progress)
              .controlSize(.small)
              .accessibilityIdentifier("recently-played-row-progress-\(fileIdentifierSuffix)")
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: rowMinHeight, alignment: .topLeading)
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

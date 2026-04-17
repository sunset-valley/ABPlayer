import Observation
import SwiftUI

struct MainSplitSidebarView: View {
  @Environment(\.openURL) private var openURL

  @Bindable var viewModel: FolderNavigationViewModel
  let isClearingData: Bool
  let onSelectFile: @MainActor (ABFile) async -> Void
  let onImportFile: () -> Void
  let onImportFolder: () -> Void
  let onRefresh: () async -> Void
  let onPlayContinueWatching: @MainActor (ABFile) async -> Void
  let onClearAllData: () async -> Void

  var body: some View {
    Group {
      if isClearingData {
        ProgressView("Clearing...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(spacing: 0) {
          FolderNavigationView(
            viewModel: viewModel,
            onSelectFile: onSelectFile,
            onPlayContinueWatching: onPlayContinueWatching
          )
          Divider()
          versionFooter
        }
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        if viewModel.syncStatus.isRunning {
          ProgressView()
            .controlSize(.small)
        } else {
          Menu {
            Button(action: onImportFile) {
              Label("Import Media File", systemImage: "tray.and.arrow.down")
            }

            Button(action: onImportFolder) {
              Label("Import Folder", systemImage: "folder.badge.plus")
            }

            Button {
              Task { await onRefresh() }
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }

            Divider()

            Button(role: .destructive) {
              Task { await onClearAllData() }
            } label: {
              Label("Clear All Data", systemImage: "trash")
            }
          } label: {
            Label("Add", systemImage: "plus")
          }
        }
      }
    }
  }

  private var versionFooter: some View {
    HStack {
      Text("v\(bundleShortVersion)(\(bundleVersion))")

      Spacer()

      Button("Feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right") {
        guard let url = URL(string: "https://github.com/sunset-valley/ABPlayer/issues/new") else {
          return
        }
        openURL(url)
      }
      .buttonStyle(.plain)
    }
    .captionStyle()
    .padding(.horizontal, 16)
    .padding(.vertical)
  }

  private var bundleShortVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
  }

  private var bundleVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
  }
}

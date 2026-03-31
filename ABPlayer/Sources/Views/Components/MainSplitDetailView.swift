import Observation
import SwiftUI

struct MainSplitDetailView: View {
  let selectedFile: ABFile
  @Bindable var viewModel: MainSplitViewModel
  @Bindable var sessionTracker: SessionTracker

  var body: some View {
    ThreePanelLayout(
      isRightVisible: $viewModel.showContentPanel,
      horizontalPersistenceKey: viewModel.horizontalPersistenceKey,
      defaultLeftColumnWidth: viewModel.defaultPlayerSectionWidth,
      minLeftColumnWidth: viewModel.minWidthOfPlayerSection,
      minRightWidth: viewModel.minWidthOfContentPanel,
      isBottomLeftVisible: $viewModel.showBottomPanel,
      verticalPersistenceKey: viewModel.verticalPersistenceKey,
      defaultTopLeftHeight: viewModel.defaultTopPanelHeight,
      minTopLeftHeight: viewModel.minHeightOfTopPanel,
      minBottomLeftHeight: viewModel.minHeightOfBottomPanel,
      dividerThickness: viewModel.dividerWidth
    ) {
      if selectedFile.isVideo {
        VideoPlayerView(audioFile: selectedFile)
      } else {
        AudioPlayerView(audioFile: selectedFile)
      }
    } bottomLeft: {
      DynamicPaneView(
        title: "Bottom Pane",
        tabs: viewModel.leftTabs,
        selection: $viewModel.leftSelection,
        addOptions: viewModel.availableContents(for: .bottomLeft),
        onAdd: { content in
          viewModel.move(content: content, to: .bottomLeft)
        },
        onRemove: { content in
          viewModel.remove(content: content, from: .bottomLeft)
        },
        bodyContent: { content in
          MainSplitPaneContentView(content: content, audioFile: selectedFile)
        }
      )
    } right: {
      DynamicPaneView(
        title: "Right Pane",
        tabs: viewModel.rightTabs,
        selection: $viewModel.rightSelection,
        addOptions: viewModel.availableContents(for: .right),
        onAdd: { content in
          viewModel.move(content: content, to: .right)
        },
        onRemove: { content in
          viewModel.remove(content: content, from: .right)
        },
        bodyContent: { content in
          MainSplitPaneContentView(content: content, audioFile: selectedFile)
        }
      )
    }
    .toolbar {
#if DEBUG
      ToolbarItem(placement: .automatic) {
        FPSOverlay()
      }
      ToolbarSpacer(.fixed)
#endif
      ToolbarItem(placement: .automatic) {
        SessionTimeDisplayView(sessionTracker: sessionTracker)
      }
      ToolbarSpacer(.fixed)
      ToolbarItem(placement: .primaryAction) {
        Button {
          viewModel.showContentPanel.toggle()
        } label: {
          Label(
            viewModel.showContentPanel ? "Hide Panel" : "Show Panel",
            systemImage: "sidebar.trailing"
          )
        }
        .help(viewModel.showContentPanel ? "Hide content panel" : "Show content panel")
      }
    }
  }
}

private struct SessionTimeDisplayView: View {
  @Bindable var sessionTracker: SessionTracker

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "timer")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
      Text(timeString(from: Double(sessionTracker.displaySeconds)))
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundStyle(.primary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .help("Session practice time")
  }

  private func timeString(from value: Double) -> String {
    guard value.isFinite, value >= 0 else {
      return "0:00"
    }

    let totalSeconds = Int(value.rounded())
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

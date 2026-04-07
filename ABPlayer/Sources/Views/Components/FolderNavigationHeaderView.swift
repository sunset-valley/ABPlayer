import SwiftUI

// MARK: - Folder Navigation Header

struct FolderNavigationHeaderView: View {
  let currentFolder: Folder?
  let canNavigateBack: Bool
  let sortOrder: SortOrder
  let syncMessage: String?
  let isSyncRunning: Bool
  
  let onNavigateBack: () -> Void
  let onSortChange: (SortOrder) -> Void
  
  var body: some View {
    VStack(spacing: 2) {
      HStack {
        if canNavigateBack {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              onNavigateBack()
            }
          } label: {
            Image(systemName: "chevron.left")
              .font(.title2)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }

        Spacer()

        Text(currentFolder?.name ?? "Library")
          .lineLimit(1)

        Spacer()

        Menu {
          ForEach(SortOrder.allCases, id: \.self) { order in
            Button {
              onSortChange(order)
            } label: {
              HStack {
                Text(order.rawValue)
                if sortOrder == order {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        } label: {
          Label("Sort", systemImage: "arrow.up.arrow.down")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
      }

      if isSyncRunning, let syncMessage {
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)
          Text(syncMessage)
            .lineLimit(1)
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
        }
      }
    }
    .font(.title3)
    .frame(minHeight: 44)
    .padding(.horizontal, 16)
  }
}

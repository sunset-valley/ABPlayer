import SwiftUI

// MARK: - Folder Navigation Header

struct FolderNavigationHeaderView: View {
  let currentFolder: Folder?
  let canNavigateBack: Bool
  let sortOrder: SortOrder
  
  let onNavigateBack: () -> Void
  let onSortChange: (SortOrder) -> Void
  
  var body: some View {
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

      Text(currentFolder?.name ?? "Liberary")
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
    .font(.title3)
    .frame(height: 44)
    .padding(.horizontal, 16)
  }
}

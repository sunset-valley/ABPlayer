import SwiftUI

struct UpNextSectionView: View {
  private enum Layout {
    static let itemWidth: CGFloat = 108
    static let itemHeight: CGFloat = 144
    static let itemSpacing: CGFloat = 6
    static let horizontalPadding: CGFloat = 18
    static let controlsHorizontalPadding: CGFloat = 6
  }

  @State private var isHovering = false
  @State private var currentItem = 0
  @State private var targetItem: Int?
  @State private var itemsPerPage = 1

  private let itemCount = 20

  private var lastItemIndex: Int {
    itemCount - 1
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: Layout.itemSpacing) {
            ForEach(0 ..< itemCount, id: \.self) { index in
              UpNextItemCardView(
                index: index,
                itemWidth: Layout.itemWidth,
                itemHeight: Layout.itemHeight
              )
              .id(index)
            }
          }
          .padding(.horizontal, Layout.horizontalPadding)
          .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.never)
        .scrollPosition(id: $targetItem, anchor: .leading)

        HStack {
          PagingArrowButton(
            title: "Previous Page",
            systemImage: "chevron.left",
            isEnabled: currentItem > 0
          ) {
            scrollTo(itemIndex: previousPageTargetIndex)
          }

          Spacer()

          PagingArrowButton(
            title: "Next Page",
            systemImage: "chevron.right",
            isEnabled: currentItem < lastItemIndex
          ) {
            scrollTo(itemIndex: nextPageTargetIndex)
          }
        }
        .padding(.horizontal, Layout.controlsHorizontalPadding)
        .opacity(isHovering ? 1 : 0)
        .allowsHitTesting(isHovering)
        .animation(.easeInOut(duration: 0.16), value: isHovering)
      }
      .onHover { isHovering = $0 }
      .onChange(of: geometry.size.width) { _, newWidth in
        updateItemsPerPage(containerWidth: newWidth)
      }
      .onChange(of: targetItem) { _, newTarget in
        guard let newTarget else {
          return
        }

        currentItem = clampedItemIndex(for: newTarget)
      }
    }
    .frame(height: Layout.itemHeight)
  }

  private var previousPageTargetIndex: Int {
    max(0, currentItem - itemsPerPage)
  }

  private var nextPageTargetIndex: Int {
    min(itemsPerPage + currentItem, lastItemIndex)
  }

  private func clampedItemIndex(for index: Int) -> Int {
    min(max(index, 0), lastItemIndex)
  }

  private func scrollTo(itemIndex: Int) {
    let clampedIndex = clampedItemIndex(for: itemIndex)

    withAnimation(.easeInOut(duration: 0.24)) {
      targetItem = clampedIndex
    }
  }

  private func updateItemsPerPage(containerWidth: CGFloat) {
    let availableWidth = max(0, containerWidth - (Layout.horizontalPadding * 2))
    let itemSpan = Layout.itemWidth + Layout.itemSpacing
    let nextItemsPerPage = max(1, Int((availableWidth + Layout.itemSpacing) / itemSpan))

    guard nextItemsPerPage != itemsPerPage else {
      return
    }

    itemsPerPage = nextItemsPerPage
  }
}

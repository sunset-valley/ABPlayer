import SwiftUI

struct ThreePanelLayout<TopLeft: View, BottomLeft: View, Right: View>: View {
  @Binding var isRightVisible: Bool
  let horizontalPersistenceKey: String
  let defaultLeftColumnWidth: Double
  let minLeftColumnWidth: CGFloat
  let minRightWidth: CGFloat
  
  @Binding var isBottomLeftVisible: Bool
  let verticalPersistenceKey: String
  let defaultTopLeftHeight: Double
  let minTopLeftHeight: CGFloat
  let minBottomLeftHeight: CGFloat
  
  let dividerThickness: CGFloat
  let animation: Animation
  let onDragging: (_ direction: SplitAxis, _ isDragging: Bool) -> Void
  
  @ViewBuilder let topLeft: () -> TopLeft
  @ViewBuilder let bottomLeft: () -> BottomLeft
  @ViewBuilder let right: () -> Right
  
  init(
    isRightVisible: Binding<Bool>,
    horizontalPersistenceKey: String,
    defaultLeftColumnWidth: Double,
    minLeftColumnWidth: CGFloat,
    minRightWidth: CGFloat,
    isBottomLeftVisible: Binding<Bool>,
    verticalPersistenceKey: String,
    defaultTopLeftHeight: Double,
    minTopLeftHeight: CGFloat,
    minBottomLeftHeight: CGFloat,
    dividerThickness: CGFloat = 8,
    animation: Animation = .easeInOut(duration: 0.25),
    onDragging: @escaping (_ direction: SplitAxis, _ isDragging: Bool) -> Void = { _, _ in },
    @ViewBuilder topLeft: @escaping () -> TopLeft,
    @ViewBuilder bottomLeft: @escaping () -> BottomLeft,
    @ViewBuilder right: @escaping () -> Right
  ) {
    self._isRightVisible = isRightVisible
    self.horizontalPersistenceKey = horizontalPersistenceKey
    self.defaultLeftColumnWidth = defaultLeftColumnWidth
    self.minLeftColumnWidth = minLeftColumnWidth
    self.minRightWidth = minRightWidth
    
    self._isBottomLeftVisible = isBottomLeftVisible
    self.verticalPersistenceKey = verticalPersistenceKey
    self.defaultTopLeftHeight = defaultTopLeftHeight
    self.minTopLeftHeight = minTopLeftHeight
    self.minBottomLeftHeight = minBottomLeftHeight
    
    self.dividerThickness = dividerThickness
    self.animation = animation
    self.onDragging = onDragging
    
    self.topLeft = topLeft
    self.bottomLeft = bottomLeft
    self.right = right
  }
  
  var body: some View {
    ResizableSplitPanel(
      axis: .horizontal,
      isSecondaryVisible: $isRightVisible,
      persistenceKey: horizontalPersistenceKey,
      defaultPrimarySize: defaultLeftColumnWidth,
      minPrimary: minLeftColumnWidth,
      minSecondary: minRightWidth,
      dividerThickness: dividerThickness,
      animation: animation,
      onDragging: { isDragging in
        onDragging(.horizontal, isDragging)
      }
    ) {
      ResizableSplitPanel(
        axis: .vertical,
        isSecondaryVisible: $isBottomLeftVisible,
        persistenceKey: verticalPersistenceKey,
        defaultPrimarySize: defaultTopLeftHeight,
        minPrimary: minTopLeftHeight,
        minSecondary: minBottomLeftHeight,
        dividerThickness: dividerThickness,
        animation: animation,
        onDragging: { isDragging in
          onDragging(.vertical, isDragging)
        }
      ) {
        topLeft()
      } secondary: {
        bottomLeft()
      }
    } secondary: {
      right()
    }
  }
}

import SwiftUI

// MARK: - Split Axis

enum SplitAxis {
  case horizontal  // left/right
  case vertical    // top/bottom
}

// MARK: - Resizable Split Panel

struct ResizableSplitPanel<Primary: View, Secondary: View>: View {
  let axis: SplitAxis
  let onDragging: (_ isDragging: Bool) -> Void
  
  // "secondary exists" toggle (maps to showContentPanel)
  @Binding var isSecondaryVisible: Bool
  
  // persistence
  let persistenceKey: String
  let defaultPrimarySize: Double
  
  // internal primary size – fully owned by this component
  @State private var primarySize: Double
  
  // transient drag size – kept local to avoid @Observable cascade
  @State private var draggingPrimarySize: Double?
  
  // sizing rules
  let minPrimary: CGFloat
  let minSecondary: CGFloat
  let dividerThickness: CGFloat
  
  // visual behavior
  let animation: Animation
  let secondaryTransition: AnyTransition
  
  // content
  @ViewBuilder let primary: () -> Primary
  @ViewBuilder let secondary: () -> Secondary

  @State private var isDragging = false
  @State private var isHoveringDivider = false
  
  // MARK: - Initializer
  
  init(
    axis: SplitAxis,
    isSecondaryVisible: Binding<Bool>,
    persistenceKey: String,
    defaultPrimarySize: Double,
    minPrimary: CGFloat,
    minSecondary: CGFloat,
    dividerThickness: CGFloat = 8,
    animation: Animation = .easeInOut(duration: 0.25),
    onDragging: @escaping (_ isDragging: Bool) -> Void = { _ in },
    secondaryTransition: AnyTransition? = nil,
    @ViewBuilder primary: @escaping () -> Primary,
    @ViewBuilder secondary: @escaping () -> Secondary
  ) {
    self.axis = axis
    self._isSecondaryVisible = isSecondaryVisible
    self.persistenceKey = persistenceKey
    self.defaultPrimarySize = defaultPrimarySize
    self.minPrimary = minPrimary
    self.minSecondary = minSecondary
    self.dividerThickness = dividerThickness
    self.animation = animation
    self.onDragging = onDragging
    
    if let transition = secondaryTransition {
      self.secondaryTransition = transition
    } else {
      self.secondaryTransition = axis == .horizontal
        ? .move(edge: .trailing).combined(with: .opacity)
        : .move(edge: .bottom).combined(with: .opacity)
    }
    
    let stored = UserDefaults.standard.double(forKey: persistenceKey)
    self._primarySize = State(initialValue: stored > 0 ? stored : defaultPrimarySize)
    
    self.primary = primary
    self.secondary = secondary
  }
  
  // MARK: - Body
  
  var body: some View {
    let _ = Self._printChanges()
    
    GeometryReader { geometry in
      let availablePrimaryAxis = axis == .horizontal ? geometry.size.width : geometry.size.height
      let effectiveSize = effectivePrimarySize(available: availablePrimaryAxis)
      
      Group {
        switch axis {
        case .horizontal:
          HStack(spacing: 0) {
            primary()
              .frame(minWidth: minPrimary)
              .frame(width: isSecondaryVisible ? effectiveSize : nil)
            
            if isSecondaryVisible {
              divider(availablePrimaryAxis: availablePrimaryAxis)
              
              secondary()
                .frame(minWidth: minSecondary, maxWidth: .infinity)
                .transition(secondaryTransition)
            }
          }
          
        case .vertical:
          VStack(spacing: 0) {
            primary()
              .frame(minHeight: minPrimary)
              .frame(height: isSecondaryVisible ? effectiveSize : nil)
            
            if isSecondaryVisible {
              divider(availablePrimaryAxis: availablePrimaryAxis)
              
              secondary()
                .frame(minHeight: minSecondary, maxHeight: .infinity)
                .transition(secondaryTransition)
            }
          }
        }
      }
      .animation(animation, value: isSecondaryVisible)
      .onChange(of: isSecondaryVisible) { _, isShowing in
        if !isShowing {
          setDragging(false)
        }
        if isShowing {
          commitPrimarySize(clampPrimarySize(primarySize, available: availablePrimaryAxis))
        }
      }
      .onChange(of: persistenceKey) { _, newKey in
        let stored = UserDefaults.standard.double(forKey: newKey)
        primarySize = stored > 0 ? stored : defaultPrimarySize
      }
    }
  }
  
  // MARK: - Private Methods
  
  private func clampPrimarySize(_ proposed: Double, available: CGFloat) -> Double {
    let maxSize = available - dividerThickness - minSecondary
    return min(max(proposed, minPrimary), max(maxSize, minPrimary))
  }
  
  private func effectivePrimarySize(available: CGFloat) -> Double {
    clampPrimarySize(draggingPrimarySize ?? primarySize, available: available)
  }
  
  private func commitPrimarySize(_ size: Double) {
    primarySize = size
    UserDefaults.standard.set(size, forKey: persistenceKey)
  }
  
  private func translationDelta(_ value: DragGesture.Value) -> Double {
    axis == .horizontal ? value.translation.width : value.translation.height
  }

  private var resizeCursor: NSCursor {
    axis == .horizontal ? .resizeLeftRight : .resizeUpDown
  }
  
  private func divider(availablePrimaryAxis: CGFloat) -> some View {
    ZStack {
      Rectangle()
        .fill(
          isHoveringDivider || isDragging
            ? Color.accentColor.opacity(0.10)
            : Color.gray.opacity(0.01)
        )

      Rectangle()
        .fill(Color(nsColor: .separatorColor))
        .frame(
          width: axis == .horizontal ? 1 : nil,
          height: axis == .vertical ? 1 : nil
        )

      Capsule()
        .fill(Color.secondary.opacity(isHoveringDivider || isDragging ? 0.8 : 0.35))
        .frame(
          width: axis == .horizontal ? 4 : 28,
          height: axis == .horizontal ? 28 : 4
        )

      Image(systemName: axis == .horizontal ? "arrow.left.and.right" : "arrow.up.and.down")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.secondary)
        .opacity(isHoveringDivider || isDragging ? 1 : 0)
    }
      .frame(
        width: axis == .horizontal ? dividerThickness : nil,
        height: axis == .vertical ? dividerThickness : nil
      )
      .contentShape(Rectangle())
      .onContinuousHover { phase in
        switch phase {
        case .active:
          isHoveringDivider = true
          resizeCursor.set()
        case .ended:
          isHoveringDivider = false
          if !isDragging {
            NSCursor.arrow.set()
          }
        }
      }
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .onChanged { value in
            setDragging(true)
            resizeCursor.set()
            let delta = translationDelta(value)
            let newSize = primarySize + delta
            draggingPrimarySize = clampPrimarySize(newSize, available: availablePrimaryAxis)
          }
          .onEnded { _ in
            if let finalSize = draggingPrimarySize {
              commitPrimarySize(finalSize)
            }
            draggingPrimarySize = nil
            setDragging(false)
            if !isHoveringDivider {
              NSCursor.arrow.set()
            }
          }
      )
  }

  private func setDragging(_ newValue: Bool) {
    guard isDragging != newValue else { return }
    isDragging = newValue
    onDragging(newValue)
  }
}

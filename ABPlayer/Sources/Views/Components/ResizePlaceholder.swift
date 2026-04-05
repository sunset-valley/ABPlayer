import SwiftUI

private struct ResizePlaceholderModifier<Placeholder: View>: ViewModifier {
  let debounce: Duration
  @ViewBuilder let placeholder: () -> Placeholder

  @State private var isResizing = false
  @State private var debounceTask: Task<Void, Never>?
  @State private var lastSize: CGSize?

  func body(content: Content) -> some View {
    Group {
      if isResizing {
        placeholder()
      } else {
        content
      }
    }
    .onGeometryChange(for: CGSize.self) { proxy in
      proxy.size
    } action: { newSize in
      // Skip initial layout — nothing is "resizing" yet.
      guard newSize.width > 20, newSize.height > 20 else {
        return
      }
      guard let previousSize = lastSize, previousSize != newSize else {
        lastSize = newSize
        return
      }
      lastSize = newSize

      isResizing = true
      debounceTask?.cancel()
      debounceTask = Task {
        try? await Task.sleep(for: debounce)
        guard !Task.isCancelled else { return }
        isResizing = false
      }
    }
  }
}

extension View {
  func resizePlaceholder<P: View>(
    debounce: Duration = .milliseconds(150),
    @ViewBuilder placeholder: @escaping () -> P
  ) -> some View {
    modifier(ResizePlaceholderModifier(debounce: debounce, placeholder: placeholder))
  }
}

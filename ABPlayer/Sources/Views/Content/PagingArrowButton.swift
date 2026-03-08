import SwiftUI

struct PagingArrowButton: View {
  private static let cornerRadius: CGFloat = 18

  let title: String
  let systemImage: String
  let isEnabled: Bool
  let action: () -> Void

  private var buttonShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
  }

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .labelStyle(.iconOnly)
        .font(.title3.weight(.semibold))
        .frame(width: 36, height: 56)
        .contentShape(buttonShape)
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .foregroundStyle(isEnabled ? .white : .gray)
    .background(.black.opacity(0.34), in: buttonShape)
    .overlay {
      buttonShape
        .strokeBorder(.white.opacity(isEnabled ? 0.14 : 0.06))
    }
    .accessibilityLabel(title)
  }
}

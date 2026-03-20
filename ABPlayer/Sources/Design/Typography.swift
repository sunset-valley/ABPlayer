import SwiftUI

extension Font {
  static let sm = Font.system(size: 14, design: .default)
}

// MARK: - Text Styles (Semantic)

extension View {
  func bodyStyle() -> some View {
    self.font(.sm)
      .foregroundStyle(Color.asset.textPrimary)
  }

  func captionStyle() -> some View {
    self.font(.callout)
      .foregroundStyle(Color.asset.textTertiary)
  }
}

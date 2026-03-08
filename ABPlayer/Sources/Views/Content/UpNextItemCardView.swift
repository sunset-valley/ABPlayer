import SwiftUI

struct UpNextItemCardView: View {
  let index: Int
  let itemWidth: CGFloat
  let itemHeight: CGFloat

  private var fillOpacity: Double {
    index.isMultiple(of: 2) ? 0.82 : 0.68
  }

  var body: some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
      .fill(Color.red.opacity(fillOpacity))
      .overlay {
        Text("\(index)")
      }
      .frame(width: itemWidth, height: itemHeight)
  }
}

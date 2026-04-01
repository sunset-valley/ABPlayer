import SwiftUI

struct VideoSubtitleOverlay: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 20, weight: .semibold, design: .rounded))
      .foregroundStyle(.white)
      .multilineTextAlignment(.center)
      .lineLimit(3)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: 720)
      .background(.black.opacity(0.72))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
      .accessibilityIdentifier("video-subtitle-overlay")
  }
}

import SwiftUI

struct CountdownRingView: View {
  let countdown: Int
  let total: Int

  private var progress: Double {
    guard total > 0 else { return 0 }
    return Double(countdown) / Double(total)
  }

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color.secondary.opacity(0.2), lineWidth: 3)

      Circle()
        .trim(from: 0, to: progress)
        .stroke(
          Color.accentColor,
          style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .animation(.linear(duration: 1), value: progress)

      Text("\(countdown)")
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.primary)
    }
    .frame(width: 32, height: 32)
    .padding(6)
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.ultraThinMaterial)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
  }
}

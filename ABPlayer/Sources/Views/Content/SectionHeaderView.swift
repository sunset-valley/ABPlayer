import SwiftUI

struct SectionHeaderView: View {
  let title: String

  var body: some View {
    HStack {
      Text(title)
        .font(.title2)
      Spacer()
    }
    .padding(.horizontal, 18)
  }
}

import SwiftUI

struct ContentTitleHeaderView: View {
  let title: String

  var body: some View {
    HStack {
      Text(title)
        .font(.largeTitle)
      Spacer()
    }
    .padding(.horizontal, 18)
  }
}

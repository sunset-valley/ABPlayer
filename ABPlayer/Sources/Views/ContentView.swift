import SwiftUI

struct ContentView: View {
  let selectedMenu: MenuItem

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ContentTitleHeaderView(title: selectedMenu.rawValue)

        SectionHeaderView(title: "Up Next")
          .padding(.top, 14)
          .padding(.bottom, 8)

        UpNextSectionView()

        Spacer()
      }
    }
  }
}

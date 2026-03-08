import SwiftUI

struct ContentView: View {
  let selectedMenu: MenuItem

  var body: some View {
    Text(selectedMenu.rawValue)
      .font(.largeTitle)
  }
}

#Preview {
  ContentView(selectedMenu: .todaysPicks)
}

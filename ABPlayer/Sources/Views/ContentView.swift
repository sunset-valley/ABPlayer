import SwiftUI

struct ContentView: View {
  let selectedMenu: MenuItem

  var body: some View {
    ZStack {
      ScrollView {
        VStack(spacing: 0) {
          HStack {
            Text(selectedMenu.rawValue)
              .font(.largeTitle)
            Spacer()
          }
          .padding(.horizontal, 18)
          
          HStack {
            Text("Up Next")
              .font(.title2)
            Spacer()
          }
          .padding(.horizontal, 18)
          .padding(.top, 14)
          .padding(.bottom, 8)
          
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              Color.red.frame(width: 108, height: 144)
              Color.red.frame(width: 108, height: 144)
              Color.red.frame(width: 108, height: 144)
              Color.red.frame(width: 108, height: 144)
              Color.red.frame(width: 108, height: 144)
              Color.red.frame(width: 108, height: 144)
              Color.red.frame(width: 108, height: 144)
            }
            .padding(.horizontal, 18)
          }

          Spacer()
        }
      }
    }
  }
}

#Preview {
  ContentView(selectedMenu: .todaysPicks)
}

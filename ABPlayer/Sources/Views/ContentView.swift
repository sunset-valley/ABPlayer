import SwiftUI

struct ContentView: View {
    let selectedMenu: MenuItem
    
    var body: some View {
        switch selectedMenu {
            case .library:
                Text("Library")
                    .font(.largeTitle)
            case .audio:
                Text("Audio")
                    .font(.largeTitle)
            case .settings:
                Text("Settings")
                    .font(.largeTitle)
        }
    }
}

#Preview {
    ContentView(selectedMenu: .audio)
}

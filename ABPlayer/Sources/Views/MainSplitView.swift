import SwiftUI

struct MainSplitView: View {
    @State private var selectedMenu: MenuItem = .audio
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedMenu: $selectedMenu)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } detail: {
            ContentView(selectedMenu: selectedMenu)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(selectedMenu.id)
    }
}

#Preview {
    MainSplitView()
}

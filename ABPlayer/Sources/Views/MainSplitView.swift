import SwiftUI

struct MainSplitView: View {
    @State private var selectedMenu: MenuItem = .todaysPicks

    private let menuSections: [MenuSection] = [
        MenuSection(title: "Discover", items: [.todaysPicks, .podcast]),
        MenuSection(title: "My Listening", items: [.downloads, .history, .myUploads, .myResources, .vocabulary]),
        MenuSection(title: "Favorites", items: [.favorites]),
        MenuSection(title: "Playlists", items: [.liked])
    ]
    
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            SidebarView(selectedMenu: $selectedMenu, menuSections: menuSections)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    Text("")
                }
        } detail: {
            ContentView(selectedMenu: selectedMenu)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(selectedMenu.id)
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

#Preview {
    MainSplitView()
}

import AppKit
import SwiftUI
import SwiftUIIntrospect

struct MainSplitView: View {
    @State private var selectedMenu: MenuItem = .todaysPicks

    private let menuSections: [MenuSection] = [
        MenuSection(title: "Discover", items: [.todaysPicks, .podcast]),
        MenuSection(title: "My Listening", items: [.downloads, .history, .myUploads, .myResources, .vocabulary]),
        MenuSection(title: "Favorites", items: [.favorites]),
        MenuSection(title: "Playlists", items: [.liked]),
    ]

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            SidebarView(selectedMenu: $selectedMenu, menuSections: menuSections)
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    Text("")
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ContentView(selectedMenu: selectedMenu)
        }
        .introspect(.navigationSplitView, on: .macOS(.v26), customize: { nsSplitView in
            guard let controller = nsSplitView.delegate as? NSSplitViewController else {
                return
            }
            controller.splitViewItems.first?.canCollapse = false
        })
        .frame(minWidth: 960, minHeight: 640)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(selectedMenu.id)
    }
}

#Preview {
    MainSplitView()
}

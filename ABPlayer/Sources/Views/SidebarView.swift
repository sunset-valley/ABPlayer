import SwiftUI

struct SidebarView: View {
    @Binding var selectedMenu: MenuItem
    let menuSections: [MenuSection]
    
    var body: some View {
        List(selection: $selectedMenu) {
            ForEach(menuSections) { section in
                if let title = section.title {
                    Section(title) {
                        ForEach(section.items) { item in
                            Label(item.rawValue, systemImage: item.icon)
                                .tag(item)
                        }
                    }
                } else {
                    ForEach(section.items) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ABPlayer")
    }
}

#Preview {
    SidebarView(
        selectedMenu: .constant(.todaysPicks),
        menuSections: [
            MenuSection(title: "Discover", items: [.todaysPicks, .podcast]),
            MenuSection(title: "My Listening", items: [.downloads, .history, .myUploads, .myResources, .vocabulary]),
            MenuSection(title: "Favorites", items: [.favorites]),
            MenuSection(title: "Playlists", items: [.liked])
        ]
    )
}

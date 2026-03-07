import SwiftUI

struct SidebarView: View {
    @Binding var selectedMenu: MenuItem
    let menuSections: [MenuSection]

    var body: some View {
        List {
            ForEach(menuSections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        HStack {
                            Label(item.rawValue, systemImage: item.icon)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .listItemTint(
                            selectedMenu == item
                                ? Color.accentColor
                                : Color(.primary)
                        )
                        .background(
                            selectedMenu == item
                                ? Color(.listRowBackground)
                                : Color.clear
                        )
                        .foregroundStyle(
                            selectedMenu == item ? Color.accentColor : Color(.primary)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedMenu = item
                        }
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
            MenuSection(title: "Playlists", items: [.liked]),
        ]
    )
}

import SwiftUI

struct SidebarView: View {
    @Binding var selectedMenu: MenuItem
    
    var body: some View {
        List(MenuItem.allCases, selection: $selectedMenu) { item in
            Label("Test", systemImage: "circle.fill")
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("ABPlayer")
    }
}

#Preview {
    SidebarView(selectedMenu: .constant(.audio))
}

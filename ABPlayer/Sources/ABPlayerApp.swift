import SwiftUI

@main
struct ABPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            MainSplitView()
        }
        .windowToolbarStyle(.unified(showsTitle: true))
#if DEBUG
        .commands {
            CommandMenu("Debug") {
                Button("Print View Hierarchy") {
                    ViewHierarchyDebug.printMainWindowHierarchy()
                }
                .keyboardShortcut("h", modifiers: [.command, .option, .shift])
            }
        }
#endif
    }
}

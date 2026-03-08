import SwiftUI

@main
struct ABPlayerApp: App {
  var body: some Scene {
    WindowGroup {
      MainSplitView()
    }
    .defaultSize(width: 1200, height: 800)
    .windowToolbarStyle(.unified(showsTitle: false))
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

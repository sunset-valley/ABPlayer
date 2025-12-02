import SwiftUI
import SwiftData

@main
struct ABPlayerApp: App {
    @State private var playerManager = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(playerManager)
        }
        .modelContainer(for: [
            AudioFile.self,
            LoopSegment.self
        ])
    }
}


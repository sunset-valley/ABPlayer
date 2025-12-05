import SwiftUI
import SwiftData

@main
struct ABPlayerApp: App {
    private let modelContainer: ModelContainer
    private let playerManager = AudioPlayerManager()
    private let sessionTracker = SessionTracker()

    init() {
        do {
            modelContainer = try ModelContainer(
                for: AudioFile.self,
                LoopSegment.self,
                ListeningSession.self
            )
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(playerManager)
                .environment(sessionTracker)
        }
        .modelContainer(modelContainer)
    }
}


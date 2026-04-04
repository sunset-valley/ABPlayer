import SwiftUI

@MainActor
struct TranscriptionDemoView: View {
  private enum DemoScenario: String {
    case loadingCache = "loading-cache"
    case empty
    case downloading
    case loadingModel = "loading-model"
    case extractingAudio = "extracting-audio"
    case transcribing
    case failed
    case content
    case queued
    case queueDownloading = "queue-downloading"
    case queueLoading = "queue-loading"
    case queueExtractingAudio = "queue-extracting-audio"
    case queueTranscribing = "queue-transcribing"
    case queueFailed = "queue-failed"

    var viewScenario: TranscriptionView.UITestScenario {
      switch self {
      case .loadingCache:
        return .loadingCache
      case .empty:
        return .empty
      case .downloading:
        return .downloading
      case .loadingModel:
        return .loadingModel
      case .extractingAudio:
        return .extractingAudio
      case .transcribing:
        return .transcribing
      case .failed:
        return .failed
      case .content:
        return .content
      case .queued:
        return .queued
      case .queueDownloading:
        return .queueDownloading
      case .queueLoading:
        return .queueLoading
      case .queueExtractingAudio:
        return .queueExtractingAudio
      case .queueTranscribing:
        return .queueTranscribing
      case .queueFailed:
        return .queueFailed
      }
    }
  }

  @State private var scenario: DemoScenario = .empty

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Transcription Demo")
        .font(.title2)
        .accessibilityIdentifier("transcription-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-transcription")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("Scenario: \(scenario.rawValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("transcription-demo-state-label")

      TranscriptionView(
        audioFile: Self.demoAudioFile,
        uiTestScenario: scenario.viewScenario,
        uiTestCues: Self.demoCues
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(16)
    .frame(minWidth: 980, minHeight: 620)
    .task {
      scenario = resolveScenario()
    }
  }

  private func resolveScenario() -> DemoScenario {
    let args = ProcessInfo.processInfo.arguments
    let env = ProcessInfo.processInfo.environment

    let argumentValue = scenarioValue(from: args)
    let envValue = env["ABP_UI_TESTING_TRANSCRIPTION_STATE"]
    let raw = (argumentValue ?? envValue ?? DemoScenario.empty.rawValue).trimmingCharacters(in: .whitespacesAndNewlines)

    return DemoScenario(rawValue: raw) ?? .empty
  }

  private func scenarioValue(from args: [String]) -> String? {
    if let index = args.firstIndex(of: "--ui-testing-transcription-state") {
      let nextIndex = args.index(after: index)
      if nextIndex < args.endIndex {
        return args[nextIndex]
      }
    }

    return args.first { $0.hasPrefix("--ui-testing-transcription-state=") }?
      .replacingOccurrences(of: "--ui-testing-transcription-state=", with: "")
  }
}

extension TranscriptionDemoView {
  private static let demoAudioFile = ABFile(
    displayName: "UI Test Audio.mp3",
    fileType: .audio,
    bookmarkData: Data([0x00]),
    createdAt: Date()
  )

  private static let demoCues: [SubtitleCue] = [
    SubtitleCue(startTime: 0, endTime: 2.8, text: "Hello and welcome to ABPlayer."),
    SubtitleCue(startTime: 3.0, endTime: 5.8, text: "This is a transcription UI test cue."),
    SubtitleCue(startTime: 6.0, endTime: 9.0, text: "Font size controls and editing stay available.")
  ]
}

import SwiftUI

@MainActor
struct TranscriptionSettingsStatusDemoView: View {
  @State private var settings = TranscriptionSettings()
  @State private var manager = TranscriptionManager()
  @State private var scenario: DemoScenario = .modelReady

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Transcription Settings Status Demo")
        .font(.title2)
        .accessibilityIdentifier("transcription-settings-demo-title")

      Text("Used by UI tests. Launch with --ui-testing --ui-testing-transcription-settings-status")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("Scenario: \(scenario.rawValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("transcription-settings-demo-scenario")

      SettingsView()
        .environment(settings)
        .environment(LibrarySettings())
        .environment(PlayerSettings())
        .environment(ProxySettings())
        .environment(manager)
        #if !APPSTORE
          .environment(SparkleUpdater())
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(16)
    .frame(minWidth: 980, minHeight: 700)
    .task {
      scenario = resolveScenario()
      configureScenario()
    }
  }

  private func resolveScenario() -> DemoScenario {
    let args = ProcessInfo.processInfo.arguments
    let env = ProcessInfo.processInfo.environment
    let argumentValue = scenarioValue(from: args)
    let envValue = env["ABP_UI_TESTING_TRANSCRIPTION_SETTINGS_STATUS_SCENARIO"]
    let raw = (argumentValue ?? envValue ?? DemoScenario.modelReady.rawValue)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return DemoScenario(rawValue: raw) ?? .modelReady
  }

  private func scenarioValue(from args: [String]) -> String? {
    if let index = args.firstIndex(of: "--ui-testing-transcription-settings-status-scenario") {
      let nextIndex = args.index(after: index)
      if nextIndex < args.endIndex {
        return args[nextIndex]
      }
    }

    return args.first { $0.hasPrefix("--ui-testing-transcription-settings-status-scenario=") }?
      .replacingOccurrences(of: "--ui-testing-transcription-settings-status-scenario=", with: "")
  }

  private func configureScenario() {
    let baseDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("abplayer-ui-settings-status-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

    settings.modelName = "tiny"
    settings.modelDirectory = baseDirectory.path

    if scenario == .modelReady {
      createModelDirectory(baseDirectory: baseDirectory, modelName: settings.modelName)
    }
  }

  private func createModelDirectory(baseDirectory: URL, modelName: String) {
    let modelFolder = baseDirectory
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent("argmaxinc", isDirectory: true)
      .appendingPathComponent("whisperkit-coreml", isDirectory: true)
      .appendingPathComponent("openai_whisper-\(modelName)", isDirectory: true)

    try? FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

    let requiredFiles = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "config.json"]
    for fileName in requiredFiles {
      let fileURL = modelFolder.appendingPathComponent(fileName)
      FileManager.default.createFile(atPath: fileURL.path, contents: Data())
    }
  }
}

private extension TranscriptionSettingsStatusDemoView {
  enum DemoScenario: String {
    case modelReady = "model-ready"
    case modelMissing = "model-missing"
  }
}

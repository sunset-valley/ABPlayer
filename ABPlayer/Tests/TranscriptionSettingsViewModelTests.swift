import Foundation
import Testing

@testable import ABPlayerDev

@Suite("TranscriptionSettingsViewModel mirror behavior", .serialized)
@MainActor
struct TranscriptionSettingsViewModelTests {

  private actor EndpointTesterSpy {
    private(set) var urls: [String] = []
    private let result: TranscriptionSettingsViewModel.EndpointTestStatus

    init(result: TranscriptionSettingsViewModel.EndpointTestStatus = .success(latency: 1)) {
      self.result = result
    }

    func test(_ url: String) async -> TranscriptionSettingsViewModel.EndpointTestStatus {
      urls.append(url)
      return result
    }

    func count() -> Int {
      urls.count
    }

    func lastURL() -> String? {
      urls.last
    }
  }

  private let endpointKey = "transcription_download_endpoint"
  private let lastCustomEndpointKey = "transcription_last_custom_download_endpoint"

  private func resetMirrorDefaults() {
    UserDefaults.standard.removeObject(forKey: endpointKey)
    UserDefaults.standard.removeObject(forKey: lastCustomEndpointKey)
  }

  private func waitForAsyncStateUpdate() async {
    try? await Task.sleep(nanoseconds: 80_000_000)
  }

  private func makeSystemUnderTest(
    endpoint: String = "",
    lastCustom: String = "",
    testerSpy: EndpointTesterSpy
  ) -> (viewModel: TranscriptionSettingsViewModel, settings: TranscriptionSettings) {
    resetMirrorDefaults()

    let settings = TranscriptionSettings()
    settings.downloadEndpoint = endpoint
    settings.lastCustomDownloadEndpoint = lastCustom

    let manager = TranscriptionManager()
    let viewModel = TranscriptionSettingsViewModel(endpointTester: { url in
      await testerSpy.test(url)
    })
    viewModel.configureIfNeeded(settings: settings, transcriptionManager: manager)
    return (viewModel, settings)
  }

  @Test("Selecting Custom keeps picker selection and tests remembered custom endpoint")
  func selectingCustomUsesRememberedEndpoint() async {
    let spy = EndpointTesterSpy()
    let (viewModel, settings) = makeSystemUnderTest(
      endpoint: "",
      lastCustom: "https://saved.custom",
      testerSpy: spy
    )

    _ = viewModel.transform(input: .init(event: .mirrorSelectionChanged(TranscriptionSettingsViewModel.customMirrorSentinel)))
    await waitForAsyncStateUpdate()

    #expect(viewModel.output.mirrorSelection == TranscriptionSettingsViewModel.customMirrorSentinel)
    #expect(settings.downloadEndpoint == "https://saved.custom")
    #expect(await spy.lastURL() == "https://saved.custom")
  }

  @Test("Switching to Official mirror retests official endpoint")
  func switchingToOfficialRetestsOfficialEndpoint() async {
    let spy = EndpointTesterSpy()
    let (viewModel, settings) = makeSystemUnderTest(
      endpoint: "https://old.custom",
      lastCustom: "https://old.custom",
      testerSpy: spy
    )

    _ = viewModel.transform(input: .init(event: .mirrorSelectionChanged("")))
    await waitForAsyncStateUpdate()

    #expect(settings.downloadEndpoint.isEmpty)
    #expect(await spy.lastURL() == "https://huggingface.co")
  }

  @Test("Editing custom draft does not apply endpoint until Apply")
  func editingCustomDraftRequiresApply() async {
    let spy = EndpointTesterSpy()
    let (viewModel, settings) = makeSystemUnderTest(
      endpoint: "https://old.custom",
      lastCustom: "https://old.custom",
      testerSpy: spy
    )

    _ = viewModel.transform(input: .init(event: .mirrorSelectionChanged(TranscriptionSettingsViewModel.customMirrorSentinel)))
    await waitForAsyncStateUpdate()
    let initialCalls = await spy.count()

    _ = viewModel.transform(input: .init(event: .customEndpointDraftChanged("https://new.custom")))
    await waitForAsyncStateUpdate()

    #expect(viewModel.output.canApplyCustomEndpoint)
    #expect(settings.downloadEndpoint == "https://old.custom")
    #expect(await spy.count() == initialCalls)
  }

  @Test("Apply custom endpoint updates settings and triggers endpoint test")
  func applyCustomEndpointUpdatesAndTests() async {
    let spy = EndpointTesterSpy()
    let (viewModel, settings) = makeSystemUnderTest(
      endpoint: "https://old.custom",
      lastCustom: "https://old.custom",
      testerSpy: spy
    )

    _ = viewModel.transform(input: .init(event: .mirrorSelectionChanged(TranscriptionSettingsViewModel.customMirrorSentinel)))
    await waitForAsyncStateUpdate()

    _ = viewModel.transform(input: .init(event: .customEndpointDraftChanged("https://new.custom")))
    _ = viewModel.transform(input: .init(event: .applyCustomEndpoint))
    await waitForAsyncStateUpdate()

    #expect(settings.downloadEndpoint == "https://new.custom")
    #expect(settings.lastCustomDownloadEndpoint == "https://new.custom")
    #expect(await spy.lastURL() == "https://new.custom")
    #expect(viewModel.output.canApplyCustomEndpoint == false)
  }
}

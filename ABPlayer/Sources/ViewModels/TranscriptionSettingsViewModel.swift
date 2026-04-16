import Foundation
import Observation

@Observable
@MainActor
final class TranscriptionSettingsViewModel {

  typealias EndpointTester = @Sendable (String) async -> EndpointTestStatus

  // MARK: - Nested Types

  enum ModelDownloadStatus: Equatable {
    case unknown, checking, downloaded, notDownloaded
  }

  enum EndpointTestStatus: Equatable {
    case idle
    case testing
    case success(latency: Int)
    case failure(String)
  }

  static let hfMirror = "https://hf-mirror.com"
  static let hfCDNMirror = "https://hf-cdn.sufy.com"
  static let customMirrorSentinel = "__custom__"

  struct Input {
    enum Event {
      case onAppear
      case modelNameChanged
      case mirrorSelectionChanged(String)
      case customEndpointDraftChanged(String)
      case applyCustomEndpoint
      case downloadModel
      case cancelModelDownload
      case requestDeleteModel(String)
      case confirmDeleteModel
      case cancelDeleteModel
      case directorySelected(URL)
      case dismissMigrationError
    }

    let event: Event
  }

  struct Output {
    let downloadedModels: [(name: String, size: Int64)]
    let modelToDelete: String?
    let showDeleteConfirmation: Bool
    let isMigrating: Bool
    let migrationError: String?
    let mirrorSelection: String
    let customEndpointDraft: String
    let canApplyCustomEndpoint: Bool
    let modelEndpointTestStatus: EndpointTestStatus
    let modelDownloadStatus: ModelDownloadStatus
    let displayDirectory: String
  }

  // MARK: - Dependencies

  @ObservationIgnored private var settings: TranscriptionSettings?
  @ObservationIgnored private var transcriptionManager: TranscriptionManager?

  // MARK: - Private State

  private var downloadedModels: [(name: String, size: Int64)] = []
  private var modelToDelete: String?
  private var showDeleteConfirmation = false
  private var isMigrating = false
  private var migrationError: String?
  private var mirrorSelection = ""
  private var customEndpointDraft = ""
  private var modelEndpointTestStatus: EndpointTestStatus = .idle
  private var modelDownloadStatus: ModelDownloadStatus = .unknown

  @ObservationIgnored private var modelEndpointTestTask: Task<Void, Never>?
  @ObservationIgnored private let endpointTester: EndpointTester?
  @ObservationIgnored private let endpointTestSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    return URLSession(configuration: config)
  }()

  // MARK: - Output

  private(set) var output: Output

  // MARK: - Init

  init(endpointTester: EndpointTester? = nil) {
    self.endpointTester = endpointTester
    output = Output(
      downloadedModels: [],
      modelToDelete: nil,
      showDeleteConfirmation: false,
      isMigrating: false,
      migrationError: nil,
      mirrorSelection: "",
      customEndpointDraft: "",
      canApplyCustomEndpoint: false,
      modelEndpointTestStatus: .idle,
      modelDownloadStatus: .unknown,
      displayDirectory: ""
    )
  }

  // MARK: - Configuration

  func configureIfNeeded(settings: TranscriptionSettings, transcriptionManager: TranscriptionManager) {
    guard self.settings == nil else { return }
    self.settings = settings
    self.transcriptionManager = transcriptionManager
  }

  // MARK: - Transform

  @discardableResult
  func transform(input: Input) -> Output {
    switch input.event {
    case .onAppear:
      checkAndRefreshModels()
      syncMirrorSelection()
      if shouldTestCurrentEndpoint() {
        scheduleEndpointTest()
      } else {
        modelEndpointTestStatus = .idle
      }
    case .modelNameChanged:
      transcriptionManager?.invalidateLoadedModel()
      checkAndRefreshModels()
    case .mirrorSelectionChanged(let mirror):
      handleMirrorChange(mirror)
    case .customEndpointDraftChanged(let draft):
      handleCustomEndpointDraftChange(draft)
    case .applyCustomEndpoint:
      applyCustomEndpoint()
    case .downloadModel:
      Task { await self.downloadCurrentModel() }
    case .cancelModelDownload:
      cancelModelDownload()
    case .requestDeleteModel(let name):
      modelToDelete = name
      showDeleteConfirmation = true
    case .confirmDeleteModel:
      if let name = modelToDelete {
        deleteModel(named: name)
      }
    case .cancelDeleteModel:
      modelToDelete = nil
      showDeleteConfirmation = false
    case .directorySelected(let url):
      handleDirectorySelected(url)
    case .dismissMigrationError:
      migrationError = nil
    }
    updateOutput()
    return output
  }

  // MARK: - Private Methods

  private func checkAndRefreshModels() {
    guard let settings else { return }
    let currentModel = settings.modelName
    modelDownloadStatus = .checking
    Task {
      async let modelExistsTask = settings.isModelDownloadedAsync(modelName: currentModel)
      async let modelsTask = settings.listDownloadedModelsAsync()
      let (modelExists, models) = await (modelExistsTask, modelsTask)
      guard self.settings?.modelName == currentModel else { return }
      self.modelDownloadStatus = modelExists ? .downloaded : .notDownloaded
      self.downloadedModels = models
      self.updateOutput()
    }
  }

  private func refreshModels() {
    guard let settings else { return }
    Task {
      let models = await settings.listDownloadedModelsAsync()
      self.downloadedModels = models
      self.updateOutput()
    }
  }

  private func downloadCurrentModel() async {
    guard let settings, let transcriptionManager else { return }
    guard modelDownloadStatus != .downloaded else { return }

    do {
      let modelName = settings.modelName
      let downloadBase = settings.modelDirectoryURL
      let endpoint = settings.effectiveDownloadEndpoint
      try await settings.withModelDirectoryAccess {
        try await transcriptionManager.downloadModel(
          modelName: modelName,
          downloadBase: downloadBase,
          endpoint: endpoint
        )
      }
      checkAndRefreshModels()
    } catch is CancellationError {
      checkAndRefreshModels()
    } catch {
      checkAndRefreshModels()
      migrationError = "Failed to download model: \(error.localizedDescription)"
      updateOutput()
    }
  }

  private func cancelModelDownload() {
    guard let settings, let transcriptionManager else { return }
    guard case .downloading(_, let modelName) = transcriptionManager.state else { return }
    transcriptionManager.cancelDownload()
    settings.deleteDownloadCache(modelName: modelName)
    checkAndRefreshModels()
  }

  private func deleteModel(named name: String) {
    guard let settings else { return }
    do {
      try settings.deleteModel(named: name)
      checkAndRefreshModels()
    } catch {
      migrationError = "Failed to delete model: \(error.localizedDescription)"
    }
    modelToDelete = nil
    showDeleteConfirmation = false
  }

  private func handleDirectorySelected(_ url: URL) {
    guard let settings else { return }

    let newPath = url.path
    let oldPath = settings.modelDirectory.isEmpty
      ? TranscriptionSettings.defaultModelDirectory.path
      : settings.modelDirectory
    let oldBookmarkData = settings.modelDirectoryBookmarkData

    do {
      try settings.setModelDirectory(url)
    } catch {
      migrationError = "Failed to access selected folder: \(error.localizedDescription)"
      return
    }

    if !downloadedModels.isEmpty, oldPath != newPath {
      migrateModels(from: oldPath, oldBookmarkData: oldBookmarkData, to: newPath)
    }
    transcriptionManager?.invalidateLoadedModel()
    checkAndRefreshModels()
  }

  private func migrateModels(from oldPath: String, oldBookmarkData: Data?, to newPath: String) {
    guard let settings else { return }
    isMigrating = true
    updateOutput()

    Task {
      let result = settings.migrateModelsBestEffort(
        from: URL(fileURLWithPath: oldPath),
        oldDirectoryBookmarkData: oldBookmarkData,
        to: URL(fileURLWithPath: newPath)
      )

      if case .failed(let error) = result {
        self.migrationError = "Failed to migrate models: \(error.localizedDescription)"
      }
      self.isMigrating = false
      self.checkAndRefreshModels()
      self.updateOutput()
    }
  }

  private func syncMirrorSelection() {
    guard let settings else { return }
    let endpoint = settings.downloadEndpoint
    if endpoint.isEmpty || endpoint == Self.hfMirror || endpoint == Self.hfCDNMirror {
      mirrorSelection = endpoint
      customEndpointDraft = settings.lastCustomDownloadEndpoint
    } else {
      mirrorSelection = Self.customMirrorSentinel
      settings.lastCustomDownloadEndpoint = endpoint
      customEndpointDraft = endpoint
    }
  }

  private func handleMirrorChange(_ mirror: String) {
    guard let settings else { return }
    mirrorSelection = mirror

    if mirror == Self.customMirrorSentinel {
      let lastCustom = normalizeEndpoint(settings.lastCustomDownloadEndpoint)
      customEndpointDraft = lastCustom
      if lastCustom.isEmpty {
        settings.downloadEndpoint = ""
        modelEndpointTestTask?.cancel()
        modelEndpointTestStatus = .idle
      } else {
        settings.downloadEndpoint = lastCustom
        scheduleEndpointTest()
      }
      return
    }

    if mirror != Self.customMirrorSentinel {
      settings.downloadEndpoint = mirror
    }
    scheduleEndpointTest()
  }

  private func handleCustomEndpointDraftChange(_ draft: String) {
    guard let settings else { return }
    customEndpointDraft = draft
    guard mirrorSelection == Self.customMirrorSentinel else { return }

    let normalizedDraft = normalizeEndpoint(draft)
    let normalizedApplied = normalizeEndpoint(settings.lastCustomDownloadEndpoint)
    if normalizedDraft == normalizedApplied, !normalizedApplied.isEmpty {
      if settings.downloadEndpoint != settings.lastCustomDownloadEndpoint {
        settings.downloadEndpoint = settings.lastCustomDownloadEndpoint
      }
      scheduleEndpointTest()
    }
  }

  private func applyCustomEndpoint() {
    guard let settings else { return }
    guard mirrorSelection == Self.customMirrorSentinel else { return }

    let normalizedDraft = normalizeEndpoint(customEndpointDraft)
    guard !normalizedDraft.isEmpty else { return }
    guard normalizedDraft != normalizeEndpoint(settings.lastCustomDownloadEndpoint) else { return }

    settings.lastCustomDownloadEndpoint = normalizedDraft
    settings.downloadEndpoint = normalizedDraft
    customEndpointDraft = normalizedDraft
    scheduleEndpointTest()
  }

  private func shouldTestCurrentEndpoint() -> Bool {
    guard let settings else { return false }
    if mirrorSelection == Self.customMirrorSentinel {
      return !normalizeEndpoint(settings.downloadEndpoint).isEmpty
    }
    return true
  }

  private func normalizeEndpoint(_ endpoint: String) -> String {
    endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func canApplyCustomEndpoint() -> Bool {
    guard let settings else { return false }
    guard mirrorSelection == Self.customMirrorSentinel else { return false }
    let normalizedDraft = normalizeEndpoint(customEndpointDraft)
    guard !normalizedDraft.isEmpty else { return false }
    return normalizedDraft != normalizeEndpoint(settings.lastCustomDownloadEndpoint)
  }

  private func scheduleEndpointTest() {
    modelEndpointTestTask?.cancel()
    modelEndpointTestTask = Task { await self.testModelEndpoint() }
  }

  private func testModelEndpoint() async {
    guard let settings else { return }
    modelEndpointTestStatus = .testing
    updateOutput()
    if let endpointTester {
      modelEndpointTestStatus = await endpointTester(settings.effectiveDownloadEndpoint)
    } else {
      modelEndpointTestStatus = await performEndpointTest(urlString: settings.effectiveDownloadEndpoint)
    }
    updateOutput()
  }

  private func performEndpointTest(urlString: String) async -> EndpointTestStatus {
    guard let url = URL(string: urlString) else {
      return .failure("Invalid URL")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    let start = Date()
    do {
      let (_, response) = try await endpointTestSession.data(for: request)
      let ms = Int(Date().timeIntervalSince(start) * 1000)
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      if statusCode < 500 {
        return .success(latency: ms)
      } else {
        return .failure("Server returned \(statusCode)")
      }
    } catch is CancellationError {
      return .idle
    } catch let error as URLError where error.code == .cancelled {
      return .idle
    } catch {
      return .failure(error.localizedDescription)
    }
  }

  private func updateOutput() {
    output = Output(
      downloadedModels: downloadedModels,
      modelToDelete: modelToDelete,
      showDeleteConfirmation: showDeleteConfirmation,
      isMigrating: isMigrating,
      migrationError: migrationError,
      mirrorSelection: mirrorSelection,
      customEndpointDraft: customEndpointDraft,
      canApplyCustomEndpoint: canApplyCustomEndpoint(),
      modelEndpointTestStatus: modelEndpointTestStatus,
      modelDownloadStatus: modelDownloadStatus,
      displayDirectory: computeDisplayDirectory()
    )
  }

  private func computeDisplayDirectory() -> String {
    guard let settings else { return "" }
    if settings.modelDirectory.isEmpty {
      return "Default"
    }
    return (settings.modelDirectory as NSString).lastPathComponent
  }
}

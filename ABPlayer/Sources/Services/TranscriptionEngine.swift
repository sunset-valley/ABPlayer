import Foundation
@preconcurrency import WhisperKit

enum TranscriptionEngineError: Error {
  case modelsUnavailable
  case modelNotLoaded
  case underlying(Error)
}

extension TranscriptionEngineError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .modelsUnavailable:
      return "Models are unavailable"
    case .modelNotLoaded:
      return "Transcription model is not loaded"
    case let .underlying(error):
      return error.localizedDescription
    }
  }
}

struct TranscriptionSegmentData: Sendable {
  let start: Double
  let end: Double
  let text: String
}

@MainActor
protocol TranscriptionEngineProtocol: AnyObject {
  func isModelLoaded(_ modelName: String) -> Bool
  func download(
    modelName: String,
    downloadBase: URL,
    endpoint: String,
    progressCallback: (@Sendable (Double) -> Void)?
  ) async throws
  func loadModel(modelName: String, downloadBase: URL) async throws
  func transcribe(audioPath: String, language: String?) async throws -> [TranscriptionSegmentData]
}

@MainActor
final class WhisperKitTranscriptionEngine: TranscriptionEngineProtocol {
  private var whisperKit: WhisperKit?
  private var loadedModelName: String?

  func isModelLoaded(_ modelName: String) -> Bool {
    whisperKit != nil && loadedModelName == modelName
  }

  func download(
    modelName: String,
    downloadBase: URL,
    endpoint: String,
    progressCallback: (@Sendable (Double) -> Void)?
  ) async throws {
    do {
      _ = try await WhisperKit.download(
        variant: modelName,
        downloadBase: downloadBase,
        endpoint: endpoint,
        progressCallback: { @Sendable progress in
          progressCallback?(progress.fractionCompleted)
        }
      )
    } catch {
      throw TranscriptionEngineError.underlying(error)
    }
  }

  func loadModel(modelName: String, downloadBase: URL) async throws {
    do {
      let localFolder = Self.localModelFolder(modelName: modelName, downloadBase: downloadBase)
      let config = WhisperKitConfig(
        model: modelName,
        downloadBase: downloadBase,
        modelFolder: localFolder
      )
      whisperKit = try await WhisperKit(config)
      loadedModelName = modelName
    } catch let whisperError as WhisperError {
      if case .modelsUnavailable = whisperError {
        throw TranscriptionEngineError.modelsUnavailable
      }
      throw TranscriptionEngineError.underlying(whisperError)
    } catch {
      throw TranscriptionEngineError.underlying(error)
    }
  }

  func transcribe(audioPath: String, language: String?) async throws -> [TranscriptionSegmentData] {
    guard let whisperKit else {
      throw TranscriptionEngineError.modelNotLoaded
    }

    let options = DecodingOptions(language: language)

    do {
      let results = try await whisperKit.transcribe(audioPath: audioPath, decodeOptions: options)
      return results.flatMap { result in
        result.segments.map { segment in
          TranscriptionSegmentData(
            start: Double(segment.start),
            end: Double(segment.end),
            text: segment.text
          )
        }
      }
    } catch {
      throw TranscriptionEngineError.underlying(error)
    }
  }

  private static func localModelFolder(modelName: String, downloadBase: URL) -> String? {
    let whisperKitDir = downloadBase
      .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
    guard let contents = try? FileManager.default.contentsOfDirectory(
      at: whisperKitDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return nil }

    let knownModels = TranscriptionSettings.availableModels.map(\.id)
      .sorted { $0.count > $1.count }

    return contents.first { url in
      let folderName = url.lastPathComponent
      guard let bestMatch = knownModels.first(where: { folderName.contains($0) }) else {
        return false
      }
      return bestMatch == modelName
    }?.path
  }
}

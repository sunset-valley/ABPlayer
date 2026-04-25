import Foundation
import SwiftData

/// Represents a subtitle cue with timing information
struct SubtitleCue: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  let startTime: Double
  let endTime: Double
  let text: String

  init(id: UUID = UUID(), startTime: Double, endTime: Double, text: String) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.text = text
  }

  static func generateDeterministicID(
    audioFileID: UUID,
    cueIndex: Int,
    startTime: Double,
    endTime: Double
  ) -> UUID {
    let startMilliseconds = normalizedMilliseconds(startTime)
    let endMilliseconds = normalizedMilliseconds(endTime)
    let key = "\(audioFileID.uuidString)|\(cueIndex)|\(startMilliseconds)|\(endMilliseconds)"
    return DeterministicID.generate(from: key)
  }

  private static func normalizedMilliseconds(_ seconds: Double) -> Int64 {
    guard seconds.isFinite else { return 0 }
    return Int64((seconds * 1000).rounded())
  }
}

extension [SubtitleCue] {
  /// Binary search for the active cue at `time`. Assumes the array is sorted by `startTime`.
  func findActiveCue(at time: Double, epsilon: Double = 0.001) -> SubtitleCue? {
    guard time.isFinite, time >= 0, !isEmpty else { return nil }

    var low = 0
    var high = count - 1
    var resultIndex: Int?

    while low <= high {
      let mid = (low + high) / 2
      if self[mid].startTime <= time + epsilon {
        resultIndex = mid
        low = mid + 1
      } else {
        high = mid - 1
      }
    }

    guard let resultIndex else { return nil }

    let cue = self[resultIndex]
    if time >= cue.startTime - epsilon, time < cue.endTime {
      return cue
    }

    return nil
  }

  /// Binary search for the latest cue that has started at or before `time`.
  /// Assumes the array is sorted by `startTime`.
  func latestStartedCue(at time: Double, epsilon: Double = 0.001) -> SubtitleCue? {
    guard time.isFinite, time >= 0, !isEmpty else { return nil }

    var low = 0
    var high = count - 1
    var candidate: Int?

    while low <= high {
      let mid = (low + high) / 2
      if self[mid].startTime <= time + epsilon {
        candidate = mid
        low = mid + 1
      } else {
        high = mid - 1
      }
    }

    guard let candidate else { return nil }
    return self[candidate]
  }

  func activeCueIndex(at time: Double, epsilon: Double = 0.001) -> Int? {
    guard time.isFinite, time >= 0, !isEmpty else { return nil }

    var low = 0
    var high = count - 1
    var candidate: Int?

    while low <= high {
      let mid = (low + high) / 2
      if self[mid].startTime <= time + epsilon {
        candidate = mid
        low = mid + 1
      } else {
        high = mid - 1
      }
    }

    guard let candidate else { return nil }
    let cue = self[candidate]
    if time >= cue.startTime - epsilon, time < cue.endTime {
      return candidate
    }

    return nil
  }

  func previousSentenceStart(at time: Double, epsilon: Double = 0.001) -> Double? {
    guard !isEmpty else { return nil }
    guard time.isFinite else { return first?.startTime }

    if let activeIndex = activeCueIndex(at: Swift.max(time, 0), epsilon: epsilon) {
      let previousIndex = Swift.max(activeIndex - 1, 0)
      return self[previousIndex].startTime
    }

    let insertionIndex = firstIndex(after: Swift.max(time, 0), epsilon: epsilon)
    if insertionIndex <= 0 {
      return self[0].startTime
    }

    return self[insertionIndex - 1].startTime
  }

  func nextSentenceStart(at time: Double, epsilon: Double = 0.001) -> Double? {
    guard !isEmpty else { return nil }
    guard time.isFinite else { return first?.startTime }

    if let activeIndex = activeCueIndex(at: Swift.max(time, 0), epsilon: epsilon) {
      let nextIndex = Swift.min(activeIndex + 1, count - 1)
      return self[nextIndex].startTime
    }

    let insertionIndex = firstIndex(after: Swift.max(time, 0), epsilon: epsilon)
    if insertionIndex >= count {
      return self[count - 1].startTime
    }

    return self[insertionIndex].startTime
  }

  private func firstIndex(after time: Double, epsilon: Double) -> Int {
    var low = 0
    var high = count

    while low < high {
      let mid = (low + high) / 2
      if self[mid].startTime <= time + epsilon {
        low = mid + 1
      } else {
        high = mid
      }
    }

    return low
  }
}

@Model
final class SubtitleFile {
  var id: UUID
  var displayName: String

  @Attribute(.externalStorage)
  /// Legacy field kept for store compatibility.
  /// Managed-library mode derives subtitle path from media sibling .srt file.
  var bookmarkData: Data

  var createdAt: Date
  var audioFile: ABFile?

  init(
    id: UUID = UUID(),
    displayName: String,
    bookmarkData: Data,
    createdAt: Date = Date(),
    audioFile: ABFile? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.bookmarkData = bookmarkData
    self.createdAt = createdAt
    self.audioFile = audioFile
  }
}

// MARK: - Subtitle Parser

enum SubtitleFormat {
  case srt
  case vtt
  case unknown
}

struct SubtitleParser {
  static func detectFormat(from url: URL) -> SubtitleFormat {
    switch url.pathExtension.lowercased() {
    case "srt":
      return .srt
    case "vtt":
      return .vtt
    default:
      return .unknown
    }
  }

  static func parse(from url: URL, audioFileID: UUID) throws -> [SubtitleCue] {
    let content = try String(contentsOf: url, encoding: .utf8)
    let format = detectFormat(from: url)

    switch format {
    case .srt:
      return parseSRT(content, audioFileID: audioFileID)
    case .vtt:
      return parseVTT(content, audioFileID: audioFileID)
    case .unknown:
      return []
    }
  }

  // MARK: - SRT Writer

  static func writeSRT(cues: [SubtitleCue], to url: URL) throws {
    var content = ""
    for (index, cue) in cues.enumerated() {
      content += "\(index + 1)\n"
      content += "\(formatSRTTime(cue.startTime)) --> \(formatSRTTime(cue.endTime))\n"
      content += "\(cue.text)\n\n"
    }
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  private static func formatSRTTime(_ seconds: Double) -> String {
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    let secs = Int(seconds) % 60
    let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
  }

  // MARK: - SRT Parser

  private static func parseSRT(_ content: String, audioFileID: UUID) -> [SubtitleCue] {
    var cues: [SubtitleCue] = []
    let blocks = content.components(separatedBy: "\n\n")

    for block in blocks {
      let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
      guard lines.count >= 3 else { continue }

      // Line 0: index number (ignored)
      // Line 1: timestamp "00:00:00,000 --> 00:00:00,000"
      // Line 2+: text

      let timeLine = lines[1]
      guard let (start, end) = parseTimestampLine(timeLine, separator: ",") else {
        continue
      }

      let text = lines.dropFirst(2).joined(separator: "\n")
      let cueIndex = cues.count
      let cueID = SubtitleCue.generateDeterministicID(
        audioFileID: audioFileID,
        cueIndex: cueIndex,
        startTime: start,
        endTime: end
      )
      cues.append(SubtitleCue(id: cueID, startTime: start, endTime: end, text: text))
    }

    return cues
  }

  // MARK: - VTT Parser

  private static func parseVTT(_ content: String, audioFileID: UUID) -> [SubtitleCue] {
    var cues: [SubtitleCue] = []
    var lines = content.components(separatedBy: "\n")

    // Skip WEBVTT header
    if let firstNonEmpty = lines.first(where: { !$0.isEmpty }),
      firstNonEmpty.hasPrefix("WEBVTT")
    {
      lines.removeFirst()
    }

    // Join back and split by double newlines
    let blocks = lines.joined(separator: "\n").components(separatedBy: "\n\n")

    for block in blocks {
      let blockLines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
      guard !blockLines.isEmpty else { continue }

      // Find timestamp line
      var timestampIndex = 0
      for (index, line) in blockLines.enumerated() {
        if line.contains("-->") {
          timestampIndex = index
          break
        }
      }

      guard timestampIndex < blockLines.count else { continue }

      let timeLine = blockLines[timestampIndex]
      guard let (start, end) = parseTimestampLine(timeLine, separator: ".") else {
        continue
      }

      let text = blockLines.dropFirst(timestampIndex + 1).joined(separator: "\n")
      guard !text.isEmpty else { continue }

      let cueIndex = cues.count
      let cueID = SubtitleCue.generateDeterministicID(
        audioFileID: audioFileID,
        cueIndex: cueIndex,
        startTime: start,
        endTime: end
      )
      cues.append(SubtitleCue(id: cueID, startTime: start, endTime: end, text: text))
    }

    return cues
  }

  // MARK: - Timestamp Parsing

  private static func parseTimestampLine(_ line: String, separator: String) -> (Double, Double)? {
    let parts = line.components(separatedBy: " --> ")
    guard parts.count == 2 else { return nil }

    let startStr = parts[0].trimmingCharacters(in: .whitespaces)
    let endStr = parts[1].components(separatedBy: " ").first ?? parts[1]

    guard let start = parseTimestamp(startStr, separator: separator),
      let end = parseTimestamp(endStr.trimmingCharacters(in: .whitespaces), separator: separator)
    else {
      return nil
    }

    return (start, end)
  }

  private static func parseTimestamp(_ timestamp: String, separator: String) -> Double? {
    // Format: HH:MM:SS,mmm or HH:MM:SS.mmm or MM:SS,mmm
    let normalized = timestamp.replacingOccurrences(of: separator, with: ".")
    let components = normalized.components(separatedBy: ":")

    guard components.count >= 2 else { return nil }

    var hours: Double = 0
    var minutes: Double = 0
    var seconds: Double = 0

    if components.count == 3 {
      hours = Double(components[0]) ?? 0
      minutes = Double(components[1]) ?? 0
      seconds = Double(components[2]) ?? 0
    } else if components.count == 2 {
      minutes = Double(components[0]) ?? 0
      seconds = Double(components[1]) ?? 0
    }

    return hours * 3600 + minutes * 60 + seconds
  }
}

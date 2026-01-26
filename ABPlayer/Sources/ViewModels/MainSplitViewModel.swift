import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class MainSplitViewModel {
  // MARK: - Media Type

  enum MediaType: String {
    case audio
    case video
  }

  enum Panel {
    case bottomLeft
    case right
  }

  // MARK: - Layout State

  var draggingWidth: Double?
  var draggingHeight: Double?

  private var currentMediaType: MediaType = .audio

  var playerSectionWidth: Double {
    didSet {
      UserDefaults.standard.set(playerSectionWidth, forKey: userDefaultsKey(for: "PlayerSectionWidth"))
    }
  }

  var showContentPanel: Bool {
    didSet {
      UserDefaults.standard.set(showContentPanel, forKey: userDefaultsKey(for: "ShowContentPanel"))
    }
  }

  var topPanelHeight: Double {
    didSet {
      UserDefaults.standard.set(topPanelHeight, forKey: userDefaultsKey(for: "TopPanelHeight"))
    }
  }

  var showBottomPanel: Bool {
    didSet {
      UserDefaults.standard.set(showBottomPanel, forKey: userDefaultsKey(for: "ShowBottomPanel"))
    }
  }

  // MARK: - Global Pane Allocation State (Persisted)

  var leftTabs: [PaneContent] {
    didSet {
      persistTabs(leftTabs, suffix: "LeftTabs")
    }
  }

  var rightTabs: [PaneContent] {
    didSet {
      persistTabs(rightTabs, suffix: "RightTabs")
    }
  }

  var leftSelection: PaneContent? {
    didSet {
      persistSelection(leftSelection, suffix: "LeftSelection")
    }
  }

  var rightSelection: PaneContent? {
    didSet {
      persistSelection(rightSelection, suffix: "RightSelection")
    }
  }

  // MARK: - Constants

  let minWidthOfPlayerSection: CGFloat = 480
  let minWidthOfContentPanel: CGFloat = 300
  let minHeightOfTopPanel: CGFloat = 200
  let minHeightOfBottomPanel: CGFloat = 150
  let dividerWidth: CGFloat = 8

  // MARK: - Initialization

  init() {
    self.playerSectionWidth = Self.loadWidth(for: .audio)
    self.showContentPanel = Self.loadShowContentPanel(for: .audio)
    self.topPanelHeight = Self.loadHeight(for: .audio)
    self.showBottomPanel = Self.loadShowBottomPanel(for: .audio)

    let loadedLeftTabs = Self.loadTabs(
      for: .audio,
      suffix: "LeftTabs",
      default: [.transcription]
    )
    let loadedRightTabs = Self.loadTabs(
      for: .audio,
      suffix: "RightTabs",
      default: [.segments]
    )

    self.leftTabs = loadedLeftTabs
    self.rightTabs = loadedRightTabs

    self.leftSelection = Self.loadSelection(
      for: .audio,
      suffix: "LeftSelection",
      tabs: loadedLeftTabs
    )
    self.rightSelection = Self.loadSelection(
      for: .audio,
      suffix: "RightSelection",
      tabs: loadedRightTabs
    )

    sanitizeAllocations()
    normalizeSelection(for: .bottomLeft)
    normalizeSelection(for: .right)
  }

  // MARK: - Public Allocation API

  func availableContents(for panel: Panel) -> [PaneContent] {
    let assigned = tabs(for: panel)
    return PaneContent.allocatableCases.filter { !assigned.contains($0) }
  }

  func move(content: PaneContent, to panel: Panel) {
    guard content.isAllocatable else { return }

    let isInLeft = leftTabs.contains(content)
    let isInRight = rightTabs.contains(content)

    // If already in destination panel, just select it.
    if panel == .bottomLeft, isInLeft {
      leftSelection = content
      normalizeSelection(for: .bottomLeft)
      return
    }
    if panel == .right, isInRight {
      rightSelection = content
      normalizeSelection(for: .right)
      return
    }

    if isInLeft {
      leftTabs.removeAll { $0 == content }
      if leftSelection == content {
        leftSelection = nil
      }
    }

    if isInRight {
      rightTabs.removeAll { $0 == content }
      if rightSelection == content {
        rightSelection = nil
      }
    }

    switch panel {
    case .bottomLeft:
      if !leftTabs.contains(content) {
        leftTabs.append(content)
      }
      leftSelection = content

    case .right:
      if !rightTabs.contains(content) {
        rightTabs.append(content)
      }
      rightSelection = content
    }

    normalizeSelection(for: .bottomLeft)
    normalizeSelection(for: .right)
  }

  // MARK: - Media Type Switching

  func switchMediaType(to mediaType: MediaType) {
    guard currentMediaType != mediaType else { return }

    currentMediaType = mediaType

    playerSectionWidth = Self.loadWidth(for: mediaType)
    showContentPanel = Self.loadShowContentPanel(for: mediaType)
    topPanelHeight = Self.loadHeight(for: mediaType)
    showBottomPanel = Self.loadShowBottomPanel(for: mediaType)

    let loadedLeftTabs = Self.loadTabs(
      for: mediaType,
      suffix: "LeftTabs",
      default: [.transcription]
    )
    let loadedRightTabs = Self.loadTabs(
      for: mediaType,
      suffix: "RightTabs",
      default: [.segments]
    )

    leftTabs = loadedLeftTabs
    rightTabs = loadedRightTabs

    leftSelection = Self.loadSelection(
      for: mediaType,
      suffix: "LeftSelection",
      tabs: loadedLeftTabs
    )
    rightSelection = Self.loadSelection(
      for: mediaType,
      suffix: "RightSelection",
      tabs: loadedRightTabs
    )

    sanitizeAllocations()
    normalizeSelection(for: .bottomLeft)
    normalizeSelection(for: .right)
  }

  // MARK: - Layout Logic

  func clampWidth(_ width: Double, availableWidth: CGFloat) -> Double {
    let maxWidth = Double(availableWidth) - dividerWidth - minWidthOfContentPanel
    return min(max(width, minWidthOfPlayerSection), max(maxWidth, minWidthOfPlayerSection))
  }

  func clampHeight(_ height: Double, availableHeight: CGFloat) -> Double {
    let maxHeight = Double(availableHeight) - dividerWidth - minHeightOfBottomPanel
    return min(max(height, minHeightOfTopPanel), max(maxHeight, minHeightOfTopPanel))
  }

  // MARK: - Private Helpers (Allocation)

  private func tabs(for panel: Panel) -> [PaneContent] {
    switch panel {
    case .bottomLeft: return leftTabs
    case .right: return rightTabs
    }
  }

  private func normalizeSelection(for panel: Panel) {
    switch panel {
    case .bottomLeft:
      guard !leftTabs.isEmpty else {
        leftSelection = nil
        return
      }
      if let leftSelection, leftTabs.contains(leftSelection) {
        return
      }
      leftSelection = leftTabs.first

    case .right:
      guard !rightTabs.isEmpty else {
        rightSelection = nil
        return
      }
      if let rightSelection, rightTabs.contains(rightSelection) {
        return
      }
      rightSelection = rightTabs.first
    }
  }

  private func sanitizeAllocations() {
    // Ensure no duplicates within a panel.
    leftTabs = Self.deduped(leftTabs)
    rightTabs = Self.deduped(rightTabs)

    // Enforce global uniqueness: if overlap exists, right loses.
    let overlap = Set(leftTabs).intersection(Set(rightTabs))
    if !overlap.isEmpty {
      rightTabs.removeAll { overlap.contains($0) }
      if let rightSelection, overlap.contains(rightSelection) {
        self.rightSelection = nil
      }
    }
  }

  // MARK: - Persistence

  private func userDefaultsKey(for suffix: String) -> String {
    "mainSplit\(currentMediaType.rawValue.capitalized)\(suffix)"
  }

  private static func userDefaultsKey(for suffix: String, mediaType: MediaType) -> String {
    "mainSplit\(mediaType.rawValue.capitalized)\(suffix)"
  }

  private func persistTabs(_ tabs: [PaneContent], suffix: String) {
    let values = tabs.filter(\.isAllocatable).map(\.rawValue)
    UserDefaults.standard.set(values, forKey: userDefaultsKey(for: suffix))
  }

  private func persistSelection(_ selection: PaneContent?, suffix: String) {
    let key = userDefaultsKey(for: suffix)
    if let selection, selection.isAllocatable {
      UserDefaults.standard.set(selection.rawValue, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private static func loadWidth(for mediaType: MediaType) -> Double {
    let key = userDefaultsKey(for: "PlayerSectionWidth", mediaType: mediaType)
    let storedWidth = UserDefaults.standard.double(forKey: key)
    return storedWidth > 0 ? storedWidth : 480
  }

  private static func loadShowContentPanel(for mediaType: MediaType) -> Bool {
    let key = userDefaultsKey(for: "ShowContentPanel", mediaType: mediaType)
    if UserDefaults.standard.object(forKey: key) == nil {
      return true
    }
    return UserDefaults.standard.bool(forKey: key)
  }

  private static func loadHeight(for mediaType: MediaType) -> Double {
    let key = userDefaultsKey(for: "TopPanelHeight", mediaType: mediaType)
    let storedHeight = UserDefaults.standard.double(forKey: key)
    return storedHeight > 0 ? storedHeight : 400
  }

  private static func loadShowBottomPanel(for mediaType: MediaType) -> Bool {
    let key = userDefaultsKey(for: "ShowBottomPanel", mediaType: mediaType)
    if UserDefaults.standard.object(forKey: key) == nil {
      return true
    }
    return UserDefaults.standard.bool(forKey: key)
  }

  private static func loadTabs(
    for mediaType: MediaType,
    suffix: String,
    default defaultValue: [PaneContent]
  ) -> [PaneContent] {
    let key = userDefaultsKey(for: suffix, mediaType: mediaType)
    let rawValues = UserDefaults.standard.stringArray(forKey: key) ?? defaultValue.map(\.rawValue)

    let mapped = rawValues.compactMap(PaneContent.init(rawValue:)).filter(\.isAllocatable)
    let dedupedTabs = deduped(mapped)

    // If persisted array is empty/invalid, fall back to default.
    if dedupedTabs.isEmpty {
      return deduped(defaultValue.filter(\.isAllocatable))
    }
    return dedupedTabs
  }

  private static func loadSelection(
    for mediaType: MediaType,
    suffix: String,
    tabs: [PaneContent]
  ) -> PaneContent? {
    guard !tabs.isEmpty else { return nil }

    let key = userDefaultsKey(for: suffix, mediaType: mediaType)
    guard
      let rawValue = UserDefaults.standard.string(forKey: key),
      let value = PaneContent(rawValue: rawValue),
      value.isAllocatable,
      tabs.contains(value)
    else {
      return tabs.first
    }

    return value
  }

  private static func deduped(_ values: [PaneContent]) -> [PaneContent] {
    var seen = Set<PaneContent>()
    var result: [PaneContent] = []
    for value in values where value.isAllocatable {
      if seen.insert(value).inserted {
        result.append(value)
      }
    }
    return result
  }
}

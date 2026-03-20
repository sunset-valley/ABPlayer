import Foundation
import Observation

@MainActor
@Observable
final class MainSplitPaneAllocationState {
  enum MediaType: String {
    case audio
    case video
  }

  enum Panel {
    case bottomLeft
    case right
  }

  var showContentPanel: Bool {
    didSet {
      UserDefaults.standard.set(
        showContentPanel,
        forKey: userDefaultsKey(for: .showContentPanel)
      )
    }
  }

  var showBottomPanel: Bool {
    didSet {
      UserDefaults.standard.set(
        showBottomPanel,
        forKey: userDefaultsKey(for: .showBottomPanel)
      )
    }
  }

  var leftTabs: [PaneContent] {
    didSet {
      persistTabs(leftTabs, suffix: .leftTabs)
    }
  }

  var rightTabs: [PaneContent] {
    didSet {
      persistTabs(rightTabs, suffix: .rightTabs)
    }
  }

  var leftSelection: PaneContent? {
    didSet {
      persistSelection(leftSelection, suffix: .leftSelection)
    }
  }

  var rightSelection: PaneContent? {
    didSet {
      persistSelection(rightSelection, suffix: .rightSelection)
    }
  }

  private(set) var currentMediaType: MediaType = .audio

  var horizontalPersistenceKey: String {
    userDefaultsKey(for: .playerSectionWidth)
  }

  var verticalPersistenceKey: String {
    userDefaultsKey(for: .topPanelHeight)
  }

  init() {
    let initialState = Self.resolvedPanelState(for: .audio)
    self.showContentPanel = initialState.showContentPanel
    self.showBottomPanel = initialState.showBottomPanel
    self.leftTabs = initialState.leftTabs
    self.rightTabs = initialState.rightTabs
    self.leftSelection = initialState.leftSelection
    self.rightSelection = initialState.rightSelection

    sanitizeAllocations()
    normalizeAllSelections()
  }

  func availableContents(for panel: Panel) -> [PaneContent] {
    let currentTabs = tabs(for: panel)
    return PaneContent.allocatableCases.filter { !currentTabs.contains($0) }
  }

  func move(content: PaneContent, to panel: Panel) {
    remove(content: content, from: panel == .bottomLeft ? .right : .bottomLeft)
    appendContentIfNeeded(content, to: panel)
    setSelection(content, for: panel)
  }

  func remove(content: PaneContent, from panel: Panel) {
    switch panel {
    case .bottomLeft:
      remove(content, from: &leftTabs, selection: &leftSelection)
    case .right:
      remove(content, from: &rightTabs, selection: &rightSelection)
    }

    normalizeSelection(for: panel)
  }

  func switchMediaType(to mediaType: MediaType) {
    guard currentMediaType != mediaType else { return }

    currentMediaType = mediaType
    applyPanelState(Self.resolvedPanelState(for: mediaType))
    sanitizeAllocations()
    normalizeAllSelections()
  }

  private func tabs(for panel: Panel) -> [PaneContent] {
    switch panel {
    case .bottomLeft: return leftTabs
    case .right: return rightTabs
    }
  }

  private func normalizeSelection(for panel: Panel) {
    switch panel {
    case .bottomLeft:
      leftSelection = Self.normalizedSelection(for: leftTabs, current: leftSelection)
    case .right:
      rightSelection = Self.normalizedSelection(for: rightTabs, current: rightSelection)
    }
  }

  private func normalizeAllSelections() {
    normalizeSelection(for: .bottomLeft)
    normalizeSelection(for: .right)
  }

  private func appendContentIfNeeded(_ content: PaneContent, to panel: Panel) {
    switch panel {
    case .bottomLeft:
      if !leftTabs.contains(content) {
        leftTabs.append(content)
      }
    case .right:
      if !rightTabs.contains(content) {
        rightTabs.append(content)
      }
    }
  }

  private func setSelection(_ content: PaneContent, for panel: Panel) {
    switch panel {
    case .bottomLeft:
      leftSelection = content
    case .right:
      rightSelection = content
    }
  }

  private func remove(
    _ content: PaneContent,
    from tabs: inout [PaneContent],
    selection: inout PaneContent?
  ) {
    tabs.removeAll { $0 == content }
    if selection == content {
      selection = nil
    }
  }

  private static func normalizedSelection(
    for tabs: [PaneContent],
    current: PaneContent?
  ) -> PaneContent? {
    guard !tabs.isEmpty else { return nil }
    if let current, tabs.contains(current) {
      return current
    }
    return tabs.first
  }

  private func sanitizeAllocations() {
    leftTabs = Self.deduped(leftTabs)
    rightTabs = Self.deduped(rightTabs)
    removeOverlapFromRightTabs()
  }

  private func removeOverlapFromRightTabs() {
    let overlap = Set(leftTabs).intersection(Set(rightTabs))
    guard !overlap.isEmpty else { return }

    rightTabs.removeAll { overlap.contains($0) }
    if let rightSelection, overlap.contains(rightSelection) {
      self.rightSelection = nil
    }
  }

  private func applyPanelState(_ panelState: PanelState) {
    showContentPanel = panelState.showContentPanel
    showBottomPanel = panelState.showBottomPanel
    leftTabs = panelState.leftTabs
    rightTabs = panelState.rightTabs
    leftSelection = panelState.leftSelection
    rightSelection = panelState.rightSelection
  }

  private func userDefaultsKey(for suffix: UserDefaultsKey.MainSplitSuffix) -> String {
    UserDefaultsKey.mainSplit(mediaTypeRawValue: currentMediaType.rawValue, suffix: suffix)
  }

  private static func userDefaultsKey(
    for suffix: UserDefaultsKey.MainSplitSuffix,
    mediaType: MediaType
  ) -> String {
    UserDefaultsKey.mainSplit(mediaTypeRawValue: mediaType.rawValue, suffix: suffix)
  }

  private func persistTabs(_ tabs: [PaneContent], suffix: UserDefaultsKey.MainSplitSuffix) {
    let values = tabs.filter(\.isAllocatable).map(\.rawValue)
    UserDefaults.standard.set(values, forKey: userDefaultsKey(for: suffix))
  }

  private func persistSelection(_ selection: PaneContent?, suffix: UserDefaultsKey.MainSplitSuffix) {
    let key = userDefaultsKey(for: suffix)
    if let selection, selection.isAllocatable {
      UserDefaults.standard.set(selection.rawValue, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private static func loadBoolFromUserDefaults(
    suffix: UserDefaultsKey.MainSplitSuffix,
    mediaType: MediaType,
    defaultValue: Bool
  ) -> Bool {
    let key = userDefaultsKey(for: suffix, mediaType: mediaType)
    if UserDefaults.standard.object(forKey: key) == nil {
      return defaultValue
    }
    return UserDefaults.standard.bool(forKey: key)
  }

  private static func loadTabs(
    for mediaType: MediaType,
    suffix: UserDefaultsKey.MainSplitSuffix,
    default defaultValue: [PaneContent]
  ) -> [PaneContent] {
    let key = userDefaultsKey(for: suffix, mediaType: mediaType)
    let rawValues = UserDefaults.standard.stringArray(forKey: key) ?? defaultValue.map(\.rawValue)

    let mapped = rawValues.compactMap(PaneContent.init(rawValue:)).filter(\.isAllocatable)
    let dedupedTabs = deduped(mapped)

    if dedupedTabs.isEmpty {
      return deduped(defaultValue.filter(\.isAllocatable))
    }
    return dedupedTabs
  }

  private static func loadSelection(
    for mediaType: MediaType,
    suffix: UserDefaultsKey.MainSplitSuffix,
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

  private struct PanelState {
    let showContentPanel: Bool
    let showBottomPanel: Bool
    let leftTabs: [PaneContent]
    let rightTabs: [PaneContent]
    let leftSelection: PaneContent?
    let rightSelection: PaneContent?
  }

  private static func resolvedPanelState(for mediaType: MediaType) -> PanelState {
    let leftTabs = loadTabs(
      for: mediaType,
      suffix: .leftTabs,
      default: [.transcription]
    )
    let rightTabs = loadTabs(
      for: mediaType,
      suffix: .rightTabs,
      default: [.segments]
    )

    return PanelState(
      showContentPanel: loadBoolFromUserDefaults(
        suffix: .showContentPanel,
        mediaType: mediaType,
        defaultValue: true
      ),
      showBottomPanel: loadBoolFromUserDefaults(
        suffix: .showBottomPanel,
        mediaType: mediaType,
        defaultValue: true
      ),
      leftTabs: leftTabs,
      rightTabs: rightTabs,
      leftSelection: loadSelection(for: mediaType, suffix: .leftSelection, tabs: leftTabs),
      rightSelection: loadSelection(for: mediaType, suffix: .rightSelection, tabs: rightTabs)
    )
  }
}

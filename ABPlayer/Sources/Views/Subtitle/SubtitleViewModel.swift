import Foundation
import SwiftUI

@Observable
class SubtitleViewModel {
  enum ScrollState: Equatable {
    case autoScrolling
    case userScrolling(countdown: Int)
    
    var isUserScrolling: Bool {
      if case .userScrolling = self { return true }
      return false
    }
    
    var countdown: Int? {
      if case .userScrolling(let value) = self { return value }
      return nil
    }
  }
  
  enum WordSelectionState: Equatable {
    case none
    case selected(cueID: UUID, wordIndex: Int)
    
    var selectedWord: (cueID: UUID, wordIndex: Int)? {
      if case .selected(let cueID, let wordIndex) = self {
        return (cueID, wordIndex)
      }
      return nil
    }
  }
  
  private(set) var currentCueID: UUID?
  private(set) var scrollState: ScrollState = .autoScrolling
  private(set) var wordSelection: WordSelectionState = .none
  private(set) var tappedCueID: UUID?
  
  private var wasPlayingBeforeSelection = false
  private var scrollResumeTask: Task<Void, Never>?
  private static let pauseDuration = 3
  
  @MainActor
  func handleUserScroll() {
    scrollResumeTask?.cancel()
    scrollState = .userScrolling(countdown: Self.pauseDuration)
    
    scrollResumeTask = Task { @MainActor in
      for remaining in (0..<Self.pauseDuration).reversed() {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        scrollState = remaining > 0 ? .userScrolling(countdown: remaining) : .autoScrolling
      }
      scrollState = .autoScrolling
    }
  }
  
  func cancelScrollResume() {
    scrollResumeTask?.cancel()
    scrollResumeTask = nil
    scrollState = .autoScrolling
  }
  
  func handleWordSelection(wordIndex: Int?, cueID: UUID, isPlaying: Bool, onPause: () -> Void) {
    if let wordIndex {
      if wordSelection == .none {
        wasPlayingBeforeSelection = isPlaying
        if isPlaying {
          onPause()
        }
      }
      wordSelection = .selected(cueID: cueID, wordIndex: wordIndex)
    } else {
      dismissWord(onPlay: onPause)
    }
  }
  
  func hidePopover() {
    wordSelection = .none
  }
  
  func dismissWord(onPlay: () -> Void) {
    guard wordSelection != .none else { return }
    wordSelection = .none
    if wasPlayingBeforeSelection {
      onPlay()
      wasPlayingBeforeSelection = false
    }
  }
  
  func handleCueTap(cueID: UUID, onSeek: (Double) -> Void, cueStartTime: Double) {
    tappedCueID = cueID
    onSeek(cueStartTime)
    cancelScrollResume()
  }
  
  func updateCurrentCue(time: Double, cues: [SubtitleCue]) {
    guard !scrollState.isUserScrolling else { return }
    let activeCue = findActiveCue(at: time, in: cues)
    if activeCue?.id != currentCueID {
      currentCueID = activeCue?.id
    }
  }
  
  func reset() {
    scrollResumeTask?.cancel()
    scrollResumeTask = nil
    scrollState = .autoScrolling
    currentCueID = nil
    wordSelection = .none
  }
  
  @MainActor
  func trackPlayback(timeProvider: @escaping @MainActor () -> Double, cues: [SubtitleCue]) async {
    let epsilon: Double = 0.001
    
    while !Task.isCancelled {
      if !scrollState.isUserScrolling {
        let currentTime = timeProvider()
        let activeCue = findActiveCue(at: currentTime, in: cues, epsilon: epsilon)
        
        if activeCue?.id != currentCueID {
          currentCueID = activeCue?.id
        }
      }
      
      try? await Task.sleep(for: .milliseconds(100))
    }
  }
  
  private func findActiveCue(at time: Double, in cues: [SubtitleCue], epsilon: Double = 0.001) -> SubtitleCue? {
    guard !cues.isEmpty else { return nil }
    
    var low = 0
    var high = cues.count - 1
    var result: Int? = nil
    
    while low <= high {
      let mid = (low + high) / 2
      if cues[mid].startTime <= time + epsilon {
        result = mid
        low = mid + 1
      } else {
        high = mid - 1
      }
    }
    
    if let index = result {
      let cue = cues[index]
      if time >= cue.startTime - epsilon && time < cue.endTime {
        return cue
      }
    }
    
    return nil
  }
}

import AppKit
import Foundation
import Testing

@testable import ABPlayerDev

// MARK: - Helpers

/// Build a single-cue `CrossCueTextSelection` for test convenience.
private func makeSelection(
  cueID: UUID = UUID(),
  location: Int = 0,
  length: Int = 5,
  text: String = "hello"
) -> CrossCueTextSelection {
  CrossCueTextSelection(
    segments: [
      .init(
        cueID: cueID,
        localRange: NSRange(location: location, length: length),
        text: text
      )
    ],
    fullText: text,
    globalRange: NSRange(location: location, length: length)
  )
}

/// Build a cross-cue `CrossCueTextSelection` spanning two cues.
private func makeCrossSelection(
  cue1ID: UUID = UUID(),
  cue2ID: UUID = UUID()
) -> CrossCueTextSelection {
  CrossCueTextSelection(
    segments: [
      .init(cueID: cue1ID, localRange: NSRange(location: 0, length: 5), text: "Hello"),
      .init(cueID: cue2ID, localRange: NSRange(location: 0, length: 3), text: " wo"),
    ],
    fullText: "Hello wo",
    globalRange: NSRange(location: 0, length: 8)
  )
}

// MARK: - Tests

struct SubtitleViewModelTests {

  @Test
  @MainActor
  func testInitialState() {
    let viewModel = SubtitleViewModel()

    #expect(viewModel.currentCueID == nil)
    #expect(viewModel.scrollState == .autoScrolling)
    #expect(viewModel.textSelection == .none)
  }

  @Test
  @MainActor
  func testHandleUserScroll() async {
    let viewModel = SubtitleViewModel()

    viewModel.handleUserScroll()

    #expect(viewModel.scrollState.isUserScrolling)
    #expect(viewModel.scrollState == .userScrolling)
  }

  @Test
  @MainActor
  func testCancelScrollResume() {
    let viewModel = SubtitleViewModel()

    viewModel.handleUserScroll()
    viewModel.cancelScrollResume()

    #expect(viewModel.scrollState == .autoScrolling)
  }

  @Test
  @MainActor
  func testHandleTextSelection() {
    let viewModel = SubtitleViewModel()
    let cueID = UUID()
    var pauseCalled = false

    let selection = makeSelection(cueID: cueID, location: 0, length: 5, text: "hello")

    viewModel.handleTextSelection(
      selection: selection,
      isPlaying: true,
      onPause: { pauseCalled = true },
      onPlay: {}
    )

    #expect(pauseCalled)
    if case let .selecting(sel) = viewModel.textSelection {
      #expect(sel.singleCueID == cueID)
      #expect(sel.singleLocalRange?.location == 0)
      #expect(sel.singleLocalRange?.length == 5)
      #expect(sel.fullText == "hello")
    } else {
      Issue.record("Expected selecting state")
    }
  }

  @Test
  @MainActor
  func testHandleTextSelectionDoesNotPauseWhenAlreadyPaused() {
    let viewModel = SubtitleViewModel()
    let cueID = UUID()
    var pauseCalled = false

    let selection = makeSelection(cueID: cueID)

    viewModel.handleTextSelection(
      selection: selection,
      isPlaying: false,
      onPause: { pauseCalled = true },
      onPlay: {}
    )

    #expect(!pauseCalled)
    #expect(viewModel.textSelection.isActive)
  }

  @Test
  @MainActor
  func testDismissSelection() {
    let viewModel = SubtitleViewModel()
    var playCalled = false

    viewModel.handleTextSelection(
      selection: makeSelection(),
      isPlaying: true,
      onPause: {},
      onPlay: {}
    )

    viewModel.dismissSelection(onPlay: { playCalled = true })

    #expect(playCalled)
    #expect(viewModel.textSelection == .none)
  }

  @Test
  @MainActor
  func testDismissSelectionNoPlayWhenWasNotPlaying() {
    let viewModel = SubtitleViewModel()
    var playCalled = false

    viewModel.handleTextSelection(
      selection: makeSelection(),
      isPlaying: false,
      onPause: {},
      onPlay: {}
    )

    viewModel.dismissSelection(onPlay: { playCalled = true })

    #expect(!playCalled)
    #expect(viewModel.textSelection == .none)
  }

  @Test
  @MainActor
  func testSelectAnnotation() {
    let viewModel = SubtitleViewModel()
    let groupID = UUID()
    let selection = makeCrossSelection()
    var pauseCalled = false

    viewModel.selectAnnotation(
      groupID: groupID,
      selection: selection,
      isPlaying: true,
      onPause: { pauseCalled = true }
    )

    #expect(pauseCalled)
    if case let .annotationSelected(selectedGroupID, selectedSelection) = viewModel.textSelection {
      #expect(selectedGroupID == groupID)
      #expect(selectedSelection == selection)
    } else {
      Issue.record("Expected annotationSelected state")
    }
  }

  @Test
  @MainActor
  func testTextSelectionStateEquality() {
    let cueID = UUID()
    let selection = makeSelection(cueID: cueID, location: 0, length: 5, text: "hello")
    let a = SubtitleViewModel.TextSelectionState.selecting(selection: selection)
    let b = SubtitleViewModel.TextSelectionState.selecting(selection: selection)
    #expect(a == b)

    let c = SubtitleViewModel.TextSelectionState.none
    #expect(a != c)
  }

  @Test
  @MainActor
  func testCrossCueSelectionState() {
    let cue1ID = UUID()
    let cue2ID = UUID()
    let selection = makeCrossSelection(cue1ID: cue1ID, cue2ID: cue2ID)
    let state = SubtitleViewModel.TextSelectionState.selecting(selection: selection)

    #expect(state.isActive)

    guard case let .selecting(sel) = state else {
      Issue.record("Expected selecting state"); return
    }
    #expect(sel.isCrossCue)
    #expect(sel.segments.count == 2)
    #expect(sel.singleCueID == nil)
  }

  @Test
  @MainActor
  func testFindActiveCueWithBinarySearch() {
    let viewModel = SubtitleViewModel()

    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 2.0, text: "First"),
      SubtitleCue(startTime: 2.0, endTime: 4.0, text: "Second"),
      SubtitleCue(startTime: 4.0, endTime: 6.0, text: "Third"),
      SubtitleCue(startTime: 6.0, endTime: 8.0, text: "Fourth"),
    ]

    viewModel.updateCurrentCue(time: 2.5, cues: cues)
    #expect(viewModel.currentCueID == cues[1].id)

    viewModel.updateCurrentCue(time: 5.0, cues: cues)
    #expect(viewModel.currentCueID == cues[2].id)
  }

  @Test
  @MainActor
  func testUpdateCurrentCueDoesNotUpdateDuringUserScroll() {
    let viewModel = SubtitleViewModel()

    let cues = [
      SubtitleCue(startTime: 0.0, endTime: 2.0, text: "First"),
      SubtitleCue(startTime: 2.0, endTime: 4.0, text: "Second"),
    ]

    viewModel.updateCurrentCue(time: 1.0, cues: cues)
    let firstCueID = viewModel.currentCueID

    viewModel.handleUserScroll()
    viewModel.updateCurrentCue(time: 3.0, cues: cues)

    #expect(viewModel.currentCueID == firstCueID)
  }

  @Test
  @MainActor
  func testReset() {
    let viewModel = SubtitleViewModel()

    viewModel.handleUserScroll()
    viewModel.handleTextSelection(
      selection: makeSelection(),
      isPlaying: false,
      onPause: {},
      onPlay: {}
    )

    viewModel.reset()

    #expect(viewModel.scrollState == .autoScrolling)
    #expect(viewModel.currentCueID == nil)
    #expect(viewModel.textSelection == .none)
  }

  @Test
  @MainActor
  func testHandleCueTap() async {
    let viewModel = SubtitleViewModel()
    let cueID = UUID()

    viewModel.handleUserScroll()

    await viewModel.handleCueTap(cueID: cueID, cueStartTime: 10.0)

    #expect(viewModel.scrollState == .autoScrolling)
  }

  @Test
  @MainActor
  func testTrackPlaybackWithInvalidTime() async {
    let viewModel = SubtitleViewModel()
    let cues = [SubtitleCue(startTime: 0.0, endTime: 2.0, text: "First")]

    await viewModel.trackPlayback(cues: cues)

    #expect(viewModel.currentCueID == nil)
  }

  @Test
  @MainActor
  func testTrackPlaybackWithEmptyCues() async {
    let viewModel = SubtitleViewModel()

    await viewModel.trackPlayback(cues: [])

    #expect(viewModel.currentCueID == nil)
  }

  @Test
  @MainActor
  func testOutputProperties() {
    let viewModel = SubtitleViewModel()
    let output = viewModel.output

    #expect(output.currentCueID == nil)
    #expect(output.scrollState == .autoScrolling)
    #expect(output.textSelection == .none)
  }

  @Test
  @MainActor
  func testHandleNilSelectionDismisses() {
    let viewModel = SubtitleViewModel()
    var playCalled = false

    viewModel.handleTextSelection(
      selection: makeSelection(),
      isPlaying: true,
      onPause: {},
      onPlay: {}
    )

    viewModel.handleTextSelection(
      selection: nil,
      isPlaying: false,
      onPause: {},
      onPlay: { playCalled = true }
    )

    #expect(playCalled)
    #expect(viewModel.textSelection == .none)
  }

  @Test
  @MainActor
  func testCrossTextSelectionIsCrossCue() {
    let single = makeSelection()
    let cross = makeCrossSelection()
    #expect(!single.isCrossCue)
    #expect(cross.isCrossCue)
  }
}

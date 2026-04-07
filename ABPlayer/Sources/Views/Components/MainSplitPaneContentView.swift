import SwiftUI

struct MainSplitPaneContentView: View {
  @Environment(LibrarySettings.self) private var librarySettings

  let content: PaneContent
  let audioFile: ABFile

  var body: some View {
    Group {
      switch content {
      case .none:
        ContentUnavailableView(
          "Nothing Selected",
          systemImage: "rectangle.2.swap",
          description: Text("Use + to add Transcription, PDF, or Segments.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      case .transcription:
        TranscriptionView(audioFile: audioFile)

      case .pdf:
        #if os(macOS)
          let pdfURL = librarySettings.pdfFileURL(for: audioFile)
          if FileManager.default.fileExists(atPath: pdfURL.path) {
            PDFContentView(pdfURL: pdfURL)
          } else {
            PDFEmptyView()
          }
        #else
          ContentUnavailableView(
            "PDF Not Available",
            systemImage: "doc.text",
            description: Text("PDF viewing is only available on macOS")
          )
        #endif

      case .segments:
        SegmentsSection(audioFile: audioFile)
      }
    }
  }

  private var transcriptionDragPlaceholder: some View {
    ContentUnavailableView(
      "Resizing Panel",
      systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
      description: Text("Release the divider to render subtitles.")
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

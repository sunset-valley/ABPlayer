import SwiftUI

struct MainSplitPaneContentView: View {
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
          if let pdfData = audioFile.pdfBookmarkData {
            PDFContentView(pdfBookmarkData: pdfData)
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

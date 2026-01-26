import SwiftUI

struct SwitchablePaneView: View {
  let title: String
  let audioFile: ABFile
  @Binding var selection: PaneContent

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.headline)

      Spacer()

      Menu {
        Picker("Pane Content", selection: $selection) {
          ForEach(PaneContent.allCases) { item in
            Label(item.title, systemImage: item.systemImage).tag(item)
          }
        }
      } label: {
        Label("Choose Content", systemImage: "rectangle.2.swap")
          .labelStyle(.iconOnly)
      }
      .menuStyle(.borderlessButton)
      .help("Choose what to show in this pane")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private var content: some View {
    switch selection {
    case .none:
      ContentUnavailableView(
        "Nothing Selected",
        systemImage: "rectangle.2.swap",
        description: Text("Use the button above to choose Transcription, PDF, or Segments.")
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

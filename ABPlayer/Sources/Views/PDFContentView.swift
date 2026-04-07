import SwiftUI

#if os(macOS)
  import PDFKit

  /// Displays a PDF file in a panel view
  struct PDFContentView: View {
    let pdfURL: URL

    @State private var pdfDocument: PDFDocument?
    @State private var loadError: String?

    var body: some View {
      Group {
        if let pdfDocument {
          PDFKitView(document: pdfDocument)
        } else if let loadError {
          ContentUnavailableView(
            "Failed to Load PDF",
            systemImage: "exclamationmark.triangle",
            description: Text(loadError)
          )
        } else {
          ProgressView("Loading PDF...")
        }
      }
      .task {
        await loadPDF()
      }
    }

    private func loadPDF() async {
      if let document = PDFDocument(url: pdfURL) {
        await MainActor.run {
          pdfDocument = document
        }
      } else {
        loadError = "Unable to read PDF document"
      }
    }
  }

  /// NSViewRepresentable wrapper for PDFView
  struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
      let pdfView = PDFView()
      pdfView.document = document
      pdfView.autoScales = true
      pdfView.displayMode = .singlePageContinuous
      pdfView.displayDirection = .vertical
      pdfView.backgroundColor = .clear
      return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
      if nsView.document !== document {
        nsView.document = document
      }
    }
  }

  /// Empty state when no PDF is associated
  struct PDFEmptyView: View {
    var body: some View {
      ContentUnavailableView(
        "No PDF",
        systemImage: "doc.text",
        description: Text("This audio file has no associated PDF document")
      )
    }
  }

#endif

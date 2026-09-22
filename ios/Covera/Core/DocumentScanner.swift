import UniformTypeIdentifiers
import PDFKit
import SwiftUI
import VisionKit

/// The system document camera, returning a single PDF.
///
/// Pages are combined into a PDF on the device because the upload endpoint
/// takes PDFs, and a paper policy photographed page by page is still one
/// document. The result has no text layer, so the server reads it by
/// transcription and reports its pages as transcribed — the weaker guarantee
/// the plan screen already tells the reader about.
struct DocumentScanner: UIViewControllerRepresentable {
    let onComplete: (URL) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    /// False on the simulator and on devices without a camera.
    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner

        init(parent: DocumentScanner) { self.parent = parent }

        @MainActor
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pdf = PDFDocument()
            for index in 0..<scan.pageCount {
                if let page = PDFPage(image: scan.imageOfPage(at: index)) {
                    pdf.insert(page, at: pdf.pageCount)
                }
            }

            guard pdf.pageCount > 0, let data = pdf.dataRepresentation() else {
                parent.onError(ScanError.empty)
                return
            }

            let name = String(localized: "Scanned policy \(Date().formatted(.coveraDate.day().month(.abbreviated).year())).pdf")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                // Complete protection: the scan is someone's medical cover, and
                // it sits in a temporary file until the upload finishes.
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                parent.onComplete(url)
            } catch {
                parent.onError(error)
            }
        }

        @MainActor
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        @MainActor
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError(error)
        }
    }
}

enum ScanError: LocalizedError {
    case empty

    var errorDescription: String? {
        String(localized: "The scan had no pages Covera could use. Try again in better light.")
    }
}

// MARK: - Adding a policy

enum PastedPDF {
    static func load() async throws -> URL {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pasted policy \(UUID().uuidString.prefix(6)).pdf")
        let board = UIPasteboard.general
        if let data = board.data(forPasteboardType: UTType.pdf.identifier) {
            return try save(data, to: target)
        }
        if let url = board.urls?.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
            let data = try await read(url)
            return try save(data, to: target)
        }
        for provider in board.itemProviders
        where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            let data = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, error in
                    if let data { cont.resume(returning: data) } else { cont.resume(throwing: error ?? PasteError.noPDF) }
                }
            }
            return try save(data, to: target)
        }
        throw PasteError.noPDF
    }

    private static func read(_ url: URL) async throws -> Data {
        if url.isFileURL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf: url)
        }
        return try await URLSession.shared.data(from: url).0
    }

    private static func save(_ data: Data, to url: URL) throws -> URL {
        // Only a real PDF is uploaded; anything else is refused here.
        guard data.starts(with: Array("%PDF".utf8)) else { throw PasteError.noPDF }
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum PasteError: LocalizedError {
    case noPDF
    var errorDescription: String? {
        String(localized: "There is no PDF on the clipboard. Copy the policy file first, then paste it here.")
    }
}

enum ImportMethod: Identifiable {
    case pdf, scan, paste
    var id: Self { self }
}

/// The two ways in — a PDF from Files, or the camera — wired to the shared
/// documents model. Applied wherever an "add policy" action appears, so every
/// entry point behaves identically.
private struct PolicyImportModifier: ViewModifier {
    @Binding var method: ImportMethod?
    let model: DocumentsModel
    let onFinished: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: method) { _, new in
                guard new == .paste else { return }
                method = nil
                // A copied PDF can arrive as raw data (Mail, Safari), as a file
                // (Files, Finder via Universal Clipboard) or as a URL to one.
                Task {
                    do {
                        let url = try await PastedPDF.load()
                        await model.upload(url: url, isTemporary: true)
                        onFinished()
                    } catch {
                        model.report(error)
                    }
                }
            }
            .fileImporter(
                isPresented: Binding(
                    get: { method == .pdf },
                    set: { if !$0 { method = nil } }
                ),
                allowedContentTypes: [.pdf]
            ) { result in
                guard case let .success(url) = result else { return }
                Task {
                    await model.upload(url: url, isTemporary: false)
                    onFinished()
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { method == .scan },
                    set: { if !$0 { method = nil } }
                )
            ) {
                DocumentScanner(
                    onComplete: { url in
                        method = nil
                        Task {
                            await model.upload(url: url, isTemporary: true)
                            onFinished()
                        }
                    },
                    onCancel: { method = nil },
                    onError: { error in
                        method = nil
                        model.report(error)
                    }
                )
                .ignoresSafeArea()
            }
    }
}

extension View {
    func policyImport(
        _ method: Binding<ImportMethod?>,
        model: DocumentsModel,
        onFinished: @escaping () -> Void = {}
    ) -> some View {
        modifier(PolicyImportModifier(method: method, model: model, onFinished: onFinished))
    }
}

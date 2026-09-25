import QuickLook
import SwiftUI

/// The policy library. Its job is to be boring and honest: what is stored, what
/// state it is in, and what changed at renewal.
struct DocumentsView: View {
    let model: DocumentsModel
    let callLog: CallLogStore
    let onStartGuidance: () -> Void

    @State private var importMethod: ImportMethod?
    @State private var selected: PolicyDocument?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                    ScreenHeader(
                        eyebrow: String(localized: "Library"),
                        title: String(localized: "Policies")
                    ) {
                        if !model.documents.isEmpty {
                            AddPolicyMenu(method: $importMethod)
                        }
                    }

                    if let error = model.errorMessage {
                        NoticeCard(
                            icon: "exclamationmark.triangle",
                            tint: Theme.Palette.caution,
                            title: String(localized: "Something went wrong"),
                            message: error
                        )
                    }

                    if let outcome = model.lastUpload {
                        UploadOutcomeCard(outcome: outcome)
                    }

                    if model.documents.isEmpty && !model.isLoading {
                        EmptyLibraryCard(method: $importMethod)
                            .padding(.top, Theme.Spacing.step)
                    } else if !model.documents.isEmpty {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Eyebrow(text: String(localized: "Stored")).fixedSize()
                                Spacer()
                                documentCount.fixedSize()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Eyebrow(text: String(localized: "Stored"))
                                documentCount
                            }
                        }
                        .padding(.top, Theme.Spacing.tight)

                        WalletStack(
                            documents: model.documents,
                            onOpen: { selected = $0 }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.section)
            }
            .coveraScreen()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.load() }
            .task { await model.load() }
            .policyImport($importMethod, model: model)
            .sheet(item: $selected) { document in
                DocumentDetailSheet(
                    document: document,
                    model: model,
                    callLog: callLog,
                    onStartGuidance: {
                        selected = nil
                        onStartGuidance()
                    },
                    onReplace: { method in
                        selected = nil
                        importMethod = method
                    }
                )
            }
        }
    }
}

extension DocumentsView {
    fileprivate var documentCount: some View {
        Text(model.documents.count == 1
             ? String(localized: "1 document")
             : String(localized: "\(model.documents.count) documents"))
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(Theme.Palette.tertiaryInk)
            .contentTransition(.numericText())
    }
}

// MARK: - The wallet

/// Policies sit like cards in a wallet: overlapped, newest on top, with only
/// the header of each one showing. A tap fans them out; a tap on a fanned card
/// opens it. With Reduce Motion on, they are simply listed.
private struct WalletStack: View {
    let documents: [PolicyDocument]
    let onOpen: (PolicyDocument) -> Void
    @State private var fanned = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Overlapped cards assume a card's height; at accessibility text sizes the
    /// cards grow, so they are simply listed, as with Reduce Motion.
    private var listed: Bool { reduceMotion || dynamicTypeSize.isAccessibilitySize }

    private let cardHeight: CGFloat = 168
    // How much of a card stays visible under the one above it.
    private let peek: CGFloat = 64

    private var spacing: CGFloat {
        listed || fanned ? Theme.Spacing.step : peek - cardHeight
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(documents.enumerated()), id: \.element.id) { position, document in
                Button {
                    if listed || fanned {
                        onOpen(document)
                    } else {
                        fanned = true
                    }
                } label: {
                    PolicyCard(document: document, height: cardHeight)
                        // Tucked-in cards sit slightly back, so the stack reads
                        // as depth rather than as a misaligned list.
                        .scaleEffect(scale(position), anchor: .top)
                        .brightness(fanned || listed ? 0 : -0.04 * Double(depth(position)))
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint(fanned || listed
                    ? String(localized: "Opens details and the original document")
                    : String(localized: "Opens the wallet"))
                .appearIn(position + 1)
                .zIndex(Double(documents.count - position))
            }
        }
        .animation(Theme.Motion.expand, value: fanned)
        .animation(Theme.Motion.appear, value: documents.count)
        .overlay(alignment: .bottom) {
            if !fanned && !listed && documents.count > 1 {
                Text(String(localized: "Tap to open the wallet"))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.tertiaryInk)
                    .offset(y: 26)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, !fanned && !listed && documents.count > 1 ? 34 : 0)
    }

    private func depth(_ position: Int) -> Int {
        min(position, 3)
    }

    private func scale(_ position: Int) -> CGFloat {
        fanned || listed ? 1 : 1 - 0.02 * CGFloat(depth(position))
    }
}

// MARK: - Adding

/// The "+" in the header: both ways in, one tap away.
struct AddPolicyMenu: View {
    @Binding var method: ImportMethod?

    var body: some View {
        Menu {
            Button {
                method = .pdf
            } label: {
                Label(String(localized: "Upload a PDF"), systemImage: "doc.badge.plus")
            }
            Button {
                method = .scan
            } label: {
                Label(String(localized: "Scan a paper policy"), systemImage: "doc.viewfinder")
            }
            .disabled(!DocumentScanner.isAvailable)
            Button {
                method = .paste
            } label: {
                Label(String(localized: "Paste a copied PDF"), systemImage: "doc.on.clipboard")
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 44, height: 44)
                .background(Theme.Palette.elevated, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
        }
        .accessibilityLabel(String(localized: "Add policy"))
    }
}

private struct EmptyLibraryCard: View {
    @Binding var method: ImportMethod?

    var body: some View {
        VStack(spacing: Theme.Spacing.block) {
            Image(systemName: "doc.text")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 76, height: 76)
                .background(Theme.Palette.elevated, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
                .modifier(Float())
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.tight) {
                Text(String(localized: "No policies yet"))
                    .font(Theme.Typeface.display(.title2))
                    .foregroundStyle(Theme.Palette.ink)
                Text(String(localized: "Add the full policy wording your insurer sent you, not the summary page. Covera reads it page by page and keeps the page number for every figure."))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Theme.Spacing.tight) {
                Button {
                    method = .pdf
                } label: {
                    Label(String(localized: "Upload a PDF"), systemImage: "doc.badge.plus")
                }
                .buttonStyle(PrimaryButtonStyle())

                if DocumentScanner.isAvailable {
                    Button {
                        method = .scan
                    } label: {
                        Label(String(localized: "Scan a paper policy"), systemImage: "doc.viewfinder")
                    }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                }
                Button {
                    method = .paste
                } label: {
                    Label(String(localized: "Paste a copied PDF"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
        }
        .padding(Theme.Spacing.block + 4)
        .frame(maxWidth: .infinity)
        .coveraLuxury()
    }
}

// MARK: - Policy card

/// A stored policy as an object you hold: dark metal, lit edge, the name set in
/// serif. It carries no coverage figure — only facts about the file.
struct PolicyCard: View {
    let document: PolicyDocument
    var height: CGFloat = 168
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var statusTint: Color {
        switch document.status {
        case "failed": Theme.Palette.caution
        case "extracting", "uploaded": Theme.Palette.unstated
        // Blue, not green: "read and stored" is a fact about the file, not a
        // verdict on the cover.
        default: Theme.Palette.cited
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    Wordmark(size: .subheadline)
                    Spacer()
                    status.fixedSize()
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Wordmark(size: .subheadline)
                    status
                }
            }

            Spacer(minLength: Theme.Spacing.step)

            Text(document.displayName)
                .font(Theme.Typeface.display(.title3))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let pages = document.pageCount {
                    Text(pages == 1 ? String(localized: "1 page") : String(localized: "\(pages) pages"))
                }
                Spacer()
                Text(document.uploadedAt.formatted(.coveraDate.day().month(.abbreviated).year()))
            }
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(Theme.Palette.tertiaryInk)
            .padding(.top, Theme.Spacing.tight)
        }
        .padding(Theme.Spacing.block)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .coveraLuxury()
        .accessibilityElement(children: .combine)
    }

    private var status: some View {
        HStack(spacing: 6) {
            StatusDot(tint: statusTint, pulsing: document.status == "extracting" || document.status == "uploaded")
            Text(document.statusDescription)
                .foregroundStyle(statusTint)
        }
        .font(.caption.weight(.semibold))
    }
}

// MARK: - Detail

private struct DocumentDetailSheet: View {
    let document: PolicyDocument
    let model: DocumentsModel
    let callLog: CallLogStore
    let onStartGuidance: () -> Void
    let onReplace: (ImportMethod) -> Void

    @State private var previewURL: URL?
    @State private var isOpening = false
    @State private var openError: String?
    @State private var showingCallLog = false


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                PolicyCard(document: document, height: 190)
                    .padding(.top, Theme.Spacing.step)

                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let openError {
                    Text(openError)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Theme.Spacing.tight) {
                    if document.isReady {
                        Button(action: onStartGuidance) {
                            Label(String(localized: "Get a plan"), systemImage: "list.number")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            Task { await open() }
                        } label: {
                            HStack(spacing: Theme.Spacing.tight) {
                                if isOpening { ProgressView().tint(Theme.Palette.ink) }
                                Label(String(localized: "View the original"), systemImage: "doc.richtext")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                        .disabled(isOpening)

                        Button {
                            showingCallLog = true
                        } label: {
                            Label(String(localized: "Calls about this policy"), systemImage: "phone.badge.waveform")
                        }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    } else if document.status == "failed" {
                        Button {
                            onReplace(.pdf)
                        } label: {
                            Label(String(localized: "Upload the original PDF"), systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        if DocumentScanner.isAvailable {
                            Button {
                                onReplace(.scan)
                            } label: {
                                Label(String(localized: "Scan it again"), systemImage: "doc.viewfinder")
                            }
                            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                        }
                    }
                }
            }
            .padding(Theme.Spacing.screen)
            // A little room under the last button, for when it is scrolled.
            .padding(.bottom, Theme.Spacing.step)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Sized to the content: enough that the last action clears the bottom
        // of the screen on opening — at .medium it opened flush against the
        // edge, where the home-indicator gesture lives — and no more, so the
        // sheet does not trail off into empty paper.
        .presentationDetents([.fraction(0.64), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Palette.background)
        .presentationCornerRadius(Theme.Radius.luxury + 6)
        .coveraLayoutDirection()
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showingCallLog) {
            CallLogView(
                store: callLog,
                documentID: document.id,
                policyName: document.displayName,
                onClose: { showingCallLog = false }
            )
        }
        .onChange(of: previewURL) { old, new in
            // The decrypted copy exists only while it is on screen.
            if new == nil, let old { try? FileManager.default.removeItem(at: old) }
        }
    }

    private var explanation: String {
        switch document.status {
        case "failed":
            String(localized: "This document could not be read with enough confidence to quote it accurately, so nothing from it is used. A clearer scan, or the original PDF from your insurer, usually works.")
        case "extracting", "uploaded":
            String(localized: "Covera is still reading this document. Nothing from it is used until every figure has been checked against its page.")
        default:
            String(localized: "Read and stored. Every figure Covera quotes from this policy links back to its page, so you can always check the wording yourself.")
        }
    }

    private func open() async {
        isOpening = true
        openError = nil
        defer { isOpening = false }
        do {
            previewURL = try await model.localCopy(of: document)
        } catch {
            openError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Upload feedback

private struct UploadOutcomeCard: View {
    let outcome: UploadResponse

    private var headline: String {
        if outcome.alreadyIngested {
            return String(localized: "Covera already had this document, so nothing was duplicated.")
        }
        if outcome.supersedes != nil {
            return String(localized: "Stored as a renewal of a policy you already had.")
        }
        return String(localized: "Stored and read.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            Eyebrow(text: String(localized: "Last upload"))
            Text(headline)
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !outcome.transcribedPages.isEmpty {
                Pill(
                    text: String(localized: "\(outcome.transcribedPages.count) page(s) transcribed from a scan"),
                    systemImage: "text.viewfinder",
                    tint: Theme.Palette.unstated
                )
            }

            if !outcome.changes.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(String(localized: "What changed since the previous version"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    ForEach(outcome.changes) { change in
                        BulletedLine(text: change.summary)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.secondaryInk)
                    }
                }
                .padding(Theme.Spacing.step + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .coveraInset()
            }
        }
        .coveraCard()
    }
}

/// Shown over the whole app while a document is being read, whichever screen
/// the upload started from.
struct UploadingOverlay: View {
    var body: some View {
        ZStack {
            Theme.Palette.background.opacity(0.78).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.block) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Palette.ink)
                VStack(spacing: Theme.Spacing.tight) {
                    Text(String(localized: "Reading the document"))
                        .font(Theme.Typeface.display(.title3))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(String(localized: "It is being read page by page, not skimmed, and every figure is checked against its page."))
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.section)
            .frame(maxWidth: 360)
            .coveraLuxury()
            .padding(Theme.Spacing.section)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Model

@MainActor
@Observable
final class DocumentsModel {
    private(set) var documents: [PolicyDocument] = []
    private(set) var lastUpload: UploadResponse?
    private(set) var isLoading = false
    private(set) var isUploading = false
    private(set) var errorMessage: String?
    private var isSample = false

    init() {}

    var readyCount: Int { documents.filter(\.isReady).count }

    func load() async {
        guard !isSample else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            documents = try await APIClient.shared.documents()
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// - Parameter isTemporary: the file is a scan Covera made itself, and is
    ///   deleted once the upload has been attempted.
    func upload(url: URL, isTemporary: Bool) async {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        // Files chosen through the importer are security-scoped.
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            if isTemporary { try? FileManager.default.removeItem(at: url) }
        }

        do {
            lastUpload = try await APIClient.shared.upload(fileURL: url, filename: url.lastPathComponent)
            await load()
        } catch {
            lastUpload = nil
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    /// A decrypted copy of the original, written with complete file protection
    /// for Quick Look. The caller deletes it when the preview closes.
    func localCopy(of document: PolicyDocument) async throws -> URL {
        let data = try await APIClient.shared.documentFile(id: document.id)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(document.originalFilename)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    #if DEBUG
    init(sample documents: [PolicyDocument]) {
        self.documents = documents
        self.isSample = true
    }
    #endif
}

#if DEBUG
#Preview("Library") {
    DocumentsView(
        model: DocumentsModel(sample: PreviewData.documents),
        callLog: CallLogStore(sample: PreviewData.callLog),
        onStartGuidance: {}
    )
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    DocumentsView(
        model: DocumentsModel(sample: []),
        callLog: CallLogStore(sample: []),
        onStartGuidance: {}
    )
        .preferredColorScheme(.dark)
}
#endif

import SwiftUI

/// Account, privacy and the two rights that must be reachable without asking
/// anyone: take everything out, and delete everything.
///
/// Deletion is in-app and unconditional (App Store Guideline 5.1.1(v)). It is
/// behind a typed confirmation because it is irreversible, not behind a support
/// email because that would be a dark pattern.
struct AccountView: View {
    @State private var model = AccountModel()
    @State private var showingDeleteConfirmation = false
    @State private var confirmationText = ""
    @State private var exportFile: ExportFile?
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.en.rawValue

    private var deleteConfirmed: Bool {
        confirmationText.trimmingCharacters(in: .whitespaces).lowercased() == "delete"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                    ScreenHeader(
                        eyebrow: String(localized: "Settings"),
                        title: String(localized: "Account")
                    )

                    if let error = model.errorMessage {
                        NoticeCard(
                            icon: "exclamationmark.triangle",
                            tint: Theme.Palette.caution,
                            title: String(localized: "That did not work"),
                            message: error
                        )
                    }

                    signedInCard.appearIn(1)
                    languageCard.appearIn(2)
                    dataCard.appearIn(2)
                    privacyCard.appearIn(3)
                    DisclaimerBanner(text: model.disclaimer).appearIn(4)
                    deleteCard.appearIn(5)
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .coveraScreen()
            .toolbar(.hidden, for: .navigationBar)
            .alert(String(localized: "Delete everything?"), isPresented: $showingDeleteConfirmation) {
                TextField(String(localized: "Type DELETE"), text: $confirmationText)
                    .textInputAutocapitalization(.characters)
                Button(String(localized: "Cancel"), role: .cancel) { confirmationText = "" }
                Button(String(localized: "Delete"), role: .destructive) {
                    // Alert buttons cannot be disabled, so the typed
                    // confirmation is enforced here: a mistaken tap does nothing.
                    guard deleteConfirmed else { return }
                    Task {
                        await model.deleteAccount()
                        confirmationText = ""
                    }
                }
            } message: {
                Text(String(localized: "Type DELETE to confirm. Your policies and everything read from them will be permanently removed. Export first if you want a copy."))
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
            }
            .task { await model.loadIdentity() }
        }
    }

    // MARK: - Sections

    private var signedInCard: some View {
        // At accessibility text sizes the button and the label cannot share a
        // row: "Sign out" broke across three lines, one letter wide. ViewThatFits
        // takes the row while it fits and stacks below it.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.step) {
                signedInLabel
                Spacer(minLength: 0)
                signOutButton
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.step) {
                signedInLabel
                signOutButton
            }
        }
        .coveraCard()
    }

    /// The signed-in identity, without the button beside it.
    private var signedInLabel: some View {
        HStack(spacing: Theme.Spacing.step) {
            IconTile(systemName: "person.crop.circle", tint: Theme.Palette.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Signed in"))
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                Text(model.email ?? "placeholder@example.com")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .redacted(reason: model.email == nil ? .placeholder : [])
            }
        }
    }

    private var signOutButton: some View {
        Button(String(localized: "Sign out")) {
            Task { await model.signOut() }
        }
        .buttonStyle(SecondaryButtonStyle())
        // Without this the label is allowed to wrap inside the capsule.
        .fixedSize(horizontal: true, vertical: false)
    }

    private var languageCard: some View {
        // Same reason as the sign-out row: the picker's value was rendering one
        // letter per line once "Language" had taken the width.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.step) {
                languageLabel
                Spacer(minLength: 0)
                languagePicker
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.step) {
                languageLabel
                languagePicker
            }
        }
        .sensoryFeedback(.selection, trigger: language)
        .coveraCard()
    }

    private var languageLabel: some View {
        HStack(spacing: Theme.Spacing.step) {
            IconTile(systemName: "globe", tint: Theme.Palette.cited, size: 36)
            Text(String(localized: "Language"))
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
        }
    }

    /// A dropdown: nine languages do not fit a segmented control.
    private var languagePicker: some View {
        Picker(String(localized: "Language"), selection: $language) {
            ForEach(AppLanguage.allCases) { Text($0.name).tag($0.rawValue) }
        }
        .pickerStyle(.menu)
        .tint(Theme.Palette.ink)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: String(localized: "Your data"))
                .padding(.bottom, Theme.Spacing.step)

            Button {
                Task {
                    if let url = await model.export() { exportFile = ExportFile(url: url) }
                }
            } label: {
                SettingsRow(
                    icon: "square.and.arrow.up",
                    title: String(localized: "Export everything"),
                    detail: String(localized: "One JSON file with your account, your policies and everything read from them, citations included."),
                    trailing: model.isWorking ? .progress : .chevron
                )
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking)
        }
        .coveraCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: String(localized: "Privacy"))
                .padding(.bottom, Theme.Spacing.step)

            SettingsRow(
                icon: "lock",
                title: String(localized: "Encrypted at rest and in transit"),
                detail: String(localized: "Documents are encrypted before they are written to storage.")
            )
            RowDivider()
            SettingsRow(
                icon: "brain",
                title: String(localized: "Never used for training"),
                detail: String(localized: "Your documents are not used to train any model.")
            )
            RowDivider()
            Link(destination: Legal.privacy) {
                SettingsRow(
                    icon: "doc.text",
                    title: String(localized: "Privacy policy"),
                    detail: nil,
                    trailing: .external
                )
            }
            .buttonStyle(.plain)
            RowDivider()
            Link(destination: Legal.terms) {
                SettingsRow(
                    icon: "doc.plaintext",
                    title: String(localized: "Terms of use"),
                    detail: nil,
                    trailing: .external
                )
            }
            .buttonStyle(.plain)
        }
        .coveraCard()
    }

    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label(String(localized: "Delete my account"), systemImage: "trash")
            }
            .buttonStyle(SecondaryButtonStyle(tint: Theme.Palette.caution, fullWidth: true))
            .disabled(model.isWorking)

            Text(String(localized: "Removes your account, your uploaded documents and everything extracted from them. It cannot be undone."))
                .font(.footnote)
                .foregroundStyle(Theme.Palette.tertiaryInk)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Spacing.tight)
    }
}

// MARK: - Rows

private struct SettingsRow: View {
    enum Trailing { case none, chevron, external, progress }

    let icon: String
    let title: String
    let detail: String?
    var detailTint: Color = Theme.Palette.tertiaryInk
    var trailing: Trailing = .none

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.step + 2) {
            IconTile(systemName: icon, tint: Theme.Palette.cited, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.ink)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(detailTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            switch trailing {
            case .none: EmptyView()
            case .chevron:
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.tertiaryInk)
            case .external:
                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.tertiaryInk)
            case .progress:
                ProgressView().tint(Theme.Palette.ink)
            }
        }
        .padding(.vertical, Theme.Spacing.tight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(height: 0.5)
            .padding(.leading, 50)
    }
}

/// Wraps the export file rather than conforming URL to Identifiable, which would
/// be a retroactive conformance on a type we do not own.
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

@MainActor
@Observable
final class AccountModel {
    /// Kept in step with the server constant; the server sends its own copy with
    /// every plan, and this is only for screens that show no plan.
    let disclaimer = String(localized: "Clausa is not a doctor and not a licensed insurance agent. This is a reading of your own documents, not medical advice and not a coverage decision. Your insurer decides what is covered.")

    private(set) var email: String?

    private(set) var isWorking = false
    private(set) var errorMessage: String?

    func loadIdentity() async {
        email = try? await APIClient.shared.currentEmail()
    }

    func signOut() async {
        // An export or a downloaded policy left in tmp must not outlive the session.
        Self.clearTemporaryFiles()
        await APIClient.shared.signOut()
        await Session.shared.signOut()
        AuthState.shared.didSignOut()
    }

    static func clearTemporaryFiles() {
        let tmp = FileManager.default.temporaryDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func export() async -> URL? {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let data = try await APIClient.shared.exportAccount()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("covera-export.json")
            try data.write(to: url, options: .completeFileProtection)
            return url
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func deleteAccount() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let accountID = Session.shared.accountID
            try await APIClient.shared.deleteAccount()
            // What the deleted account left on this phone goes with it: its
            // call log, and any export or downloaded document still in tmp.
            if let accountID { CallLogStore.erase(accountID: accountID) }
            Self.clearTemporaryFiles()
            await Session.shared.signOut()
            AuthState.shared.didSignOut()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    AccountView()
        .preferredColorScheme(.dark)
}
#endif

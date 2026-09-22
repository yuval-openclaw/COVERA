import SwiftUI

/// Shown after sign-in, before anything else, until the account has agreed to
/// the current version of the terms.
///
/// Three separate switches, all off, because they are three different acts:
/// accepting the Terms of Use (which is what makes their limits on liability
/// enforceable), consenting to the processing of health information (which the
/// GDPR does not allow to be bundled into accepting terms), and acknowledging
/// that Covera is not advice. The server records each, and refuses to process
/// any document or question until all three are on record.
struct ConsentView: View {
    let onAgreed: () -> Void

    @State private var acceptsTerms = false
    @State private var consentsToHealthData = false
    @State private var understandsNotAdvice = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var allAgreed: Bool { acceptsTerms && consentsToHealthData && understandsNotAdvice }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                Wordmark(size: .title2)
                    .padding(.top, Theme.Spacing.block)

                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(String(localized: "One last step"))
                        .font(Theme.Typeface.display(.largeTitle))
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(localized: "Please read and agree to each of these before adding a policy."))
                        .font(.body)
                        .foregroundStyle(Theme.Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Theme.Spacing.block)

                agreement(
                    isOn: $acceptsTerms,
                    icon: "doc.plaintext",
                    text: String(localized: "I am 18 or older, and I agree to the Terms of Use."),
                    link: (String(localized: "Read the Terms of Use"), Legal.terms)
                )
                .appearIn(1)

                agreement(
                    isOn: $consentsToHealthData,
                    icon: "heart.text.square",
                    text: String(localized: "I agree that Covera may process the health information in my documents to provide the service, as described in the Privacy Policy. I can withdraw this at any time by deleting my account."),
                    link: (String(localized: "Read the Privacy Policy"), Legal.privacy)
                )
                .appearIn(2)

                agreement(
                    isOn: $understandsNotAdvice,
                    icon: "exclamationmark.bubble",
                    text: String(localized: "I understand that Covera is not medical, legal or insurance advice, that it can make mistakes, and that I will confirm anything important with my insurer before relying on it."),
                    link: nil
                )
                .appearIn(3)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen + 4)
            .padding(.bottom, Theme.Spacing.section)
        }
        .coveraScreen()
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await agree() }
            } label: {
                HStack(spacing: Theme.Spacing.tight) {
                    if isSaving { ProgressView().tint(Theme.Palette.background) }
                    Text(String(localized: "Agree and continue"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!allAgreed || isSaving)
            .opacity(allAgreed ? 1 : 0.45)
            .padding(.horizontal, Theme.Spacing.screen + 4)
            .padding(.bottom, Theme.Spacing.tight)
            .background(Theme.Palette.background)
            .accessibilityHint(Text(verbatim: allAgreed ? "" : String(localized: "Turn on all three to continue")))
        }
    }

    private func agreement(
        isOn: Binding<Bool>,
        icon: String,
        text: String,
        link: (title: String, url: URL)?
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            HStack(alignment: .top, spacing: Theme.Spacing.step) {
                IconTile(systemName: icon, tint: Theme.Palette.cited, size: 36)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // The sentence is the switch's label: hidden on screen (it is
                // already beside it), read aloud by VoiceOver.
                Toggle(isOn: isOn.animation(Theme.Motion.press)) { Text(verbatim: text) }
                    .labelsHidden()
                    .tint(Theme.Palette.cited)
            }
            // The sentence is what is being agreed to, so it is a target too.
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.Motion.press) { isOn.wrappedValue.toggle() } }

            if let link {
                Link(link.title, destination: link.url)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.cited)
                    .padding(.leading, 36 + Theme.Spacing.step)
            }
        }
        .coveraCard()
    }

    private func agree() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            // Recorded on the server before continuing: an agreement that only
            // lives on the phone is not evidence of anything.
            try await APIClient.shared.recordConsent(version: Legal.version)
            onAgreed()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    ConsentView(onAgreed: {})
        .preferredColorScheme(.dark)
}
#endif

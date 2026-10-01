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

    /// Asked, checked, and never sent anywhere. The Terms require 18, and a
    /// date is a better gate than a switch someone flips without reading — but
    /// storing it would mean collecting a new piece of personal information
    /// about every user, which the Privacy Policy would then have to declare.
    /// The server keeps what it already kept: that the terms were accepted.
    @State private var birthDate: Date?

    private static let minimumAge = 18

    /// Old enough by the calendar, not by the year alone — a birthday later
    /// this year still makes someone 17.
    private var isOldEnough: Bool {
        guard let birthDate else { return false }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
        return years >= Self.minimumAge
    }

    private var allAgreed: Bool {
        isOldEnough && acceptsTerms && consentsToHealthData && understandsNotAdvice
    }

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

                birthDateCard
                    .appearIn(1)

                agreement(
                    isOn: $acceptsTerms,
                    icon: "doc.plaintext",
                    text: String(localized: "I agree to the Terms of Use."),
                    link: (String(localized: "Read the Terms of Use"), Legal.terms)
                )
                .appearIn(2)

                agreement(
                    isOn: $consentsToHealthData,
                    icon: "heart.text.square",
                    text: String(localized: "I agree that Covera may process the health information in my documents to provide the service, as described in the Privacy Policy. I can withdraw this at any time by deleting my account."),
                    link: (String(localized: "Read the Privacy Policy"), Legal.privacy)
                )
                .appearIn(3)

                agreement(
                    isOn: $understandsNotAdvice,
                    icon: "exclamationmark.bubble",
                    text: String(localized: "I understand that Covera is not medical, legal or insurance advice, that it can make mistakes, and that I will confirm anything important with my insurer before relying on it."),
                    link: nil
                )
                .appearIn(4)

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

    /// Date of birth, with the rule stated under it rather than buried in the
    /// terms. Nothing is preselected: a picker that opens on a plausible adult
    /// birthday answers the question for the user.
    private var birthDateCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            HStack(spacing: Theme.Spacing.step) {
                IconTile(systemName: "calendar", tint: Theme.Palette.cited, size: 36)
                Text(String(localized: "Your date of birth"))
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: Theme.Spacing.step)
                DatePicker(
                    String(localized: "Your date of birth"),
                    selection: Binding(
                        get: { birthDate ?? Self.pickerStart },
                        // Named, not `$0`: inside withAnimation that would bind
                        // to the animation's closure instead of the new date.
                        set: { picked in withAnimation(Theme.Motion.press) { birthDate = picked } }
                    ),
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .opacity(birthDate == nil ? 0.55 : 1)
            }

            Text(String(localized: "Covera is for people aged 18 and over."))
                .font(.caption)
                .foregroundStyle(Theme.Palette.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if birthDate != nil && !isOldEnough {
                Label(
                    String(localized: "You need to be 18 or over to use Covera."),
                    systemImage: "exclamationmark.circle"
                )
                .font(.footnote)
                .foregroundStyle(Theme.Palette.caution)
                .fixedSize(horizontal: false, vertical: true)
                .transition(Theme.Motion.unfold)
            }
        }
        .coveraCard()
    }

    /// Where the wheel opens before a choice is made. Far enough back that it
    /// is obviously a starting point and not an answer.
    private static let pickerStart: Date =
        Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now

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
